import 'dart:async';

/// Original Author: Ryan Knell (https://github.com/rknell/dart_queue/commits/master/lib/src/dart_queue_base.dart)

/// Queue to execute Futures in order.
/// It awaits each future before executing the next one.
class Queue {
  final List<_QueuedFuture> _nextCycle = [];
  final Duration? delay;
  final Duration? timeout;
  int parallel;
  int _lastProcessId = 0;
  bool _isCancelled = false;
  bool get isCancelled => _isCancelled;
  StreamController<int>? _remainingItemsController;

  Stream<int>? get remainingItems {
    _remainingItemsController ??= StreamController<int>();
    return _remainingItemsController?.stream.asBroadcastStream();
  }

  final List<Completer<void>> _completeListeners = [];
  Future get onComplete {
    final completer = Completer();
    _completeListeners.add(completer);
    return completer.future;
  }

  Set<int> activeItems = {};

  void cancel() {
    for (final item in _nextCycle) {
      item.completer.completeError(QueueCancelledException());
    }
    _nextCycle.removeWhere((item) => item.completer.isCompleted);
    _isCancelled = true;
  }

  void dispose() {
    _remainingItemsController?.close();
    cancel();
  }

  Queue({this.delay, this.parallel = 1, this.timeout});

  Future<T> add<T>(Future<T> Function() closure) {
    if (isCancelled) throw QueueCancelledException();
    final completer = Completer<T>();
    _nextCycle.add(_QueuedFuture<T>(closure, completer, timeout));
    _updateRemainingItems();
    unawaited(_process());
    return completer.future;
  }

  Future<void> _process() async {
    if (activeItems.length < parallel) {
      _queueUpNext();
    }
  }

  void _updateRemainingItems() {
    final remainingItemsController = _remainingItemsController;
    if (remainingItemsController != null &&
        remainingItemsController.isClosed == false) {
      remainingItemsController.sink.add(_nextCycle.length + activeItems.length);
    }
  }

  void _queueUpNext() {
    if (_nextCycle.isNotEmpty &&
        !isCancelled &&
        activeItems.length <= parallel) {
      final processId = _lastProcessId;
      activeItems.add(processId);
      final item = _nextCycle.first;
      _lastProcessId++;
      _nextCycle.remove(item);
      item.onComplete = () async {
        activeItems.remove(processId);
        var completionDelay = delay;
        if (completionDelay != null) {
          await Future.delayed(completionDelay);
        }
        _updateRemainingItems();
        _queueUpNext();
      };
      unawaited(item.execute());
    } else if (activeItems.isEmpty && _nextCycle.isEmpty) {
      for (final completer in _completeListeners) {
        if (completer.isCompleted != true) {
          completer.complete();
        }
      }
      _completeListeners.clear();
    }
  }
}

class QueueCancelledException implements Exception {}

class _QueuedFuture<T> {
  final Completer completer;
  final Future<T> Function() closure;
  final Duration? timeout;
  Function? onComplete;

  _QueuedFuture(this.closure, this.completer, this.timeout, {this.onComplete});

  bool _timedOut = false;

  Future<void> execute() async {
    try {
      T result;
      Timer? timeoutTimer;

      var executionTimeout = timeout;
      if (executionTimeout != null) {
        timeoutTimer = Timer(executionTimeout, () {
          _timedOut = true;
          if (onComplete != null) {
            onComplete?.call();
          }
        });
      }
      result = await closure();
      if (result != null) {
        completer.complete(result);
      } else {
        completer.complete(null);
      }
      timeoutTimer?.cancel();
      await Future.microtask(() {});
    } catch (e) {
      completer.completeError(e);
    } finally {
      if (onComplete != null && !_timedOut) onComplete?.call();
    }
  }
}
