import 'dart:async';

/// Original Author: Ryan Knell (https://github.com/rknell/dart_queue)

/// Builds the error reported to a command cancelled for [ownerId].
typedef QueueCancelledError = Exception Function(String? ownerId);

/// Queue to execute Futures in order.
/// It awaits each future before executing the next one.
class Queue {
  /// Creates an empty queue.
  ///
  /// [cancelledError] builds the error reported to cancelled commands, so the
  /// queue can report the caller's own error type without depending on it. It
  /// defaults to a plain [Exception].
  Queue({QueueCancelledError? cancelledError})
      : _cancelledError =
            cancelledError ?? ((_) => Exception('Queue Cancelled'));

  final QueueCancelledError _cancelledError;

  final Set<int> _activeItems = {};
  int _lastProcessId = 0;
  bool _isCancelled = false;
  final List<_QueuedFuture> _nextCycle = [];
  Function(int)? onRemainingItemsUpdate;

  /// Adds [closure] to the end of the queue and returns its result.
  ///
  /// [closure] runs once every earlier command has finished. [timeout] bounds
  /// its execution when given. [ownerId] identifies who queued the command (the
  /// canonical device id), so [cancelPendingWhere] can cancel it without
  /// disturbing another owner's work.
  Future<T> add<T>(
    Future<T> Function() closure, {
    Duration? timeout,
    String? ownerId,
  }) {
    if (_isCancelled) throw _cancelledError(ownerId);
    final completer = Completer<T>();
    _nextCycle.add(_QueuedFuture<T>(closure, completer, timeout, ownerId));
    _updateRemainingItems();
    if (_activeItems.isEmpty) _queueUpNext();
    return completer.future;
  }

  /// Cancel queued work for an owner without interrupting another owner's work.
  ///
  /// [cancelledError] overrides how the error reported to the cancelled
  /// commands is built, so a caller can name its own cause (a disconnect) while
  /// the queue's default error stays generic.
  ///
  /// Returns whether anything was cancelled. Listeners are not notified here:
  /// the caller notifies with [notifyRemainingItems] once the command that
  /// motivated the cancellation has reached the platform, so listeners cannot
  /// re-enter the queue ahead of it.
  bool cancelPendingWhere(
    bool Function(String? ownerId) predicate, {
    QueueCancelledError? cancelledError,
  }) {
    final canceled =
        _nextCycle.where((item) => predicate(item.ownerId)).toList();
    if (canceled.isEmpty) return false;
    _nextCycle.removeWhere(canceled.contains);
    for (final item in canceled) {
      item.completer.completeError(
        cancelledError?.call(item.ownerId) ?? _cancelledError(item.ownerId),
      );
    }
    return true;
  }

  /// Reports the current number of queued and active commands to
  /// [onRemainingItemsUpdate]. Called by the queue on every change; exposed so
  /// a caller that cancelled items can notify after dispatching its command.
  void notifyRemainingItems() => _updateRemainingItems();

  void dispose() {
    for (final item in _nextCycle) {
      item.completer.completeError(_cancelledError(item.ownerId));
    }
    _nextCycle.removeWhere((item) => item.completer.isCompleted);
    _isCancelled = true;
  }

  void _queueUpNext() {
    if (_nextCycle.isNotEmpty && !_isCancelled && _activeItems.length <= 1) {
      final processId = _lastProcessId;
      _activeItems.add(processId);
      final item = _nextCycle.first;
      _lastProcessId++;
      _nextCycle.remove(item);
      item.onComplete = () async {
        _activeItems.remove(processId);
        _updateRemainingItems();
        _queueUpNext();
      };
      unawaited(item.execute());
    }
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
  final String? ownerId;

  _QueuedFuture(this.closure, this.completer, this.timeout, this.ownerId,
      {this.onComplete});

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
