import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/src/stopwatch.dart';

/// Original Author: Ryan Knell (https://github.com/rknell/dart_queue)

/// Queue to execute Futures in order.
/// It awaits each future before executing the next one.
class Queue {
  Queue(this.id);

  final String id;
  final Set<int> _activeItems = {};
  int _lastProcessId = 0;
  bool _isCancelled = false;
  final List<_QueuedFuture> _nextCycle = [];
  Function(int)? onRemainingItemsUpdate;

  Future<T> add<T>(Future<T> Function() closure, String? deviceId,
      {Duration? timeout}) {
    int remainingQueueItems = _nextCycle.length + _activeItems.length;
    debugPrint(
        'Queueing command $remainingQueueItems to $deviceId: ${stopwatch.elapsed}');
    if (_isCancelled) throw Exception('Queue Cancelled');
    final completer = Completer<T>();
    _nextCycle.add(_QueuedFuture<T>(
        closure, completer, timeout, deviceId, remainingQueueItems));
    _updateRemainingItems();
    if (_activeItems.isEmpty) _queueUpNext();
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
  String? deviceId;
  int id;

  _QueuedFuture(
      this.closure, this.completer, this.timeout, this.deviceId, this.id,
      {this.onComplete});

  Future<void> execute() async {
    debugPrint(
        'Queue executing command $id to $deviceId: ${stopwatch.elapsed}');
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
      debugPrint(
          'Queue completed command $id to $deviceId: ${stopwatch.elapsed}');
      await Future.microtask(() {});
    } catch (e, stack) {
      completer.completeError(e, stack);
    } finally {
      if (onComplete != null) onComplete?.call();
    }
  }
}
