import 'dart:async';

/// Original Author: Ryan Knell (https://github.com/rknell/dart_queue)

/// Queue to execute Futures in order.
/// It awaits each future before executing the next one unless consecutive
/// commands opt into [addConcurrent].
class Queue {
  final Map<int, bool> _activeItems = {};
  int _lastProcessId = 0;
  bool _isCancelled = false;
  final List<_QueuedFuture> _nextCycle = [];
  Function(int)? onRemainingItemsUpdate;

  Future<T> add<T>(Future<T> Function() closure, [Duration? timeout]) =>
      _add(closure, timeout);

  Future<T> addConcurrent<T>(
    Future<T> Function() closure, [
    Duration? timeout,
  ]) => _add(closure, timeout, canRunConcurrently: true);

  Future<T> _add<T>(
    Future<T> Function() closure,
    Duration? timeout, {
    bool canRunConcurrently = false,
  }) {
    if (_isCancelled) throw Exception('Queue Cancelled');
    final completer = Completer<T>();
    _nextCycle.add(
      _QueuedFuture<T>(
        closure,
        completer,
        timeout,
        canRunConcurrently: canRunConcurrently,
      ),
    );
    _updateRemainingItems();
    _queueUpNext();
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
    while (_nextCycle.isNotEmpty && !_isCancelled && _canRunNext()) {
      final processId = _lastProcessId;
      final item = _nextCycle.removeAt(0);
      _activeItems[processId] = item.canRunConcurrently;
      _lastProcessId++;
      item.onComplete = () async {
        _activeItems.remove(processId);
        _updateRemainingItems();
        _queueUpNext();
      };
      unawaited(item.execute());
    }
  }

  bool _canRunNext() {
    if (_activeItems.isEmpty) return true;
    return _nextCycle.first.canRunConcurrently &&
        _activeItems.values.every((canRunConcurrently) => canRunConcurrently);
  }

  void _updateRemainingItems() {
    int remainingQueueItems = _nextCycle.length + _activeItems.length;
    onRemainingItemsUpdate?.call(remainingQueueItems);
  }
}

class _QueuedFuture<T> {
  final Completer completer;
  final Future<T> Function() closure;
  Function? onComplete;
  final Duration? timeout;
  final bool canRunConcurrently;

  _QueuedFuture(
    this.closure,
    this.completer,
    this.timeout, {
    this.onComplete,
    this.canRunConcurrently = false,
  });

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
