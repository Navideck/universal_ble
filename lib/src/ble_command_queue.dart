import 'dart:async';

/// Original Author: Ryan Knell (https://github.com/rknell/dart_queue)

/// Queue to execute Futures in order.
/// It awaits each future before executing the next one.
class BleCommandQueue {
  Set<int> activeItems = {};
  Function(int)? onRemainingItemsUpdate;

  int _lastProcessId = 0;
  bool _isCancelled = false;
  final List<_QueuedFuture> _nextCycle = [];

  Future<T> add<T>(Future<T> Function() closure, {Duration? timeout}) {
    if (_isCancelled) throw Exception('Queue Cancelled');
    final completer = Completer<T>();
    _nextCycle.add(_QueuedFuture<T>(closure, completer, timeout));
    _updateRemainingItems();
    if (activeItems.isEmpty) _queueUpNext();
    return completer.future;
  }

  void dispose() {
    for (final item in _nextCycle) {
      item.completer.completeError(Exception('Queue Cancelled'));
    }
    _nextCycle.removeWhere((item) => item.completer.isCompleted);
    _isCancelled = true;
  }

  void _queueUpNext() {
    if (_nextCycle.isNotEmpty && !_isCancelled && activeItems.length <= 1) {
      final processId = _lastProcessId;
      activeItems.add(processId);
      final item = _nextCycle.first;
      _lastProcessId++;
      _nextCycle.remove(item);
      item.onComplete = () async {
        activeItems.remove(processId);
        _updateRemainingItems();
        _queueUpNext();
      };
      unawaited(item.execute());
    }
  }

  void _updateRemainingItems() =>
      onRemainingItemsUpdate?.call(_nextCycle.length + activeItems.length);
}

class _QueuedFuture<T> {
  final Completer completer;
  final Future<T> Function() closure;
  Function? onComplete;
  final Duration? timeout;

  _QueuedFuture(this.closure, this.completer, this.timeout, {this.onComplete});

  Future<void> execute() async {
    try {
      T result;
      if (timeout != null) {
        result = await closure().timeout(timeout!);
      } else {
        result = await closure();
      }
      if (result != null) {
        completer.complete(result);
      } else {
        completer.complete(null);
      }
      await Future.microtask(() {});
    } catch (e, stack) {
      completer.completeError(e, stack);
    } finally {
      if (onComplete != null) onComplete?.call();
    }
  }
}
