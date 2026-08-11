import 'package:universal_ble/src/queue.dart';
import 'package:universal_ble/universal_ble.dart';

/// Set queue type and queue commands
class BleCommandQueue {
  QueueType queueType;
  Duration? timeout = const Duration(seconds: 10);
  OnQueueUpdate? onQueueUpdate;
  final Map<String, Queue> _queueMap = {};
  static const String globalQueueId = 'global';

  BleCommandQueue({this.queueType = QueueType.global});

  Future<T> queueCommand<T>(
    Future<T> Function() command, {
    String? deviceId,
    Duration? timeout,
    String? queueId,
    bool canRunConcurrently = false,
  }) {
    Duration? timeoutDuration = timeout ?? this.timeout;
    if (timeoutDuration == null) {
      return queueCommandWithoutTimeout(
        command,
        deviceId: deviceId,
        queueId: queueId,
        canRunConcurrently: canRunConcurrently,
      );
    }
    return switch (queueType) {
      QueueType.global => _add(
        _queue(queueId),
        command,
        timeoutDuration,
        canRunConcurrently,
      ),
      QueueType.perDevice => _add(
        _queue(queueId ?? deviceId),
        command,
        timeoutDuration,
        canRunConcurrently,
      ),
      QueueType.none => command().timeout(timeoutDuration),
    };
  }

  Future<T> queueCommandWithoutTimeout<T>(
    Future<T> Function() command, {
    String? deviceId,
    String? queueId,
    bool canRunConcurrently = false,
  }) {
    return switch (queueType) {
      QueueType.global => _add(
        _queue(queueId),
        command,
        null,
        canRunConcurrently,
      ),
      QueueType.perDevice => _add(
        _queue(queueId ?? deviceId),
        command,
        null,
        canRunConcurrently,
      ),
      QueueType.none => command(),
    };
  }

  Future<T> _add<T>(
    Queue queue,
    Future<T> Function() command,
    Duration? timeout,
    bool canRunConcurrently,
  ) => canRunConcurrently
      ? queue.addConcurrent(command, timeout)
      : queue.add(command, timeout);

  Queue _queue(String? id) {
    final queueKey = id ?? globalQueueId;
    return _queueMap[queueKey] ?? _newQueue(queueKey);
  }

  Queue _newQueue(String id) {
    final queue = Queue();
    queue.onRemainingItemsUpdate = (int items) {
      try {
        onQueueUpdate?.call(id, items);
      } catch (_) {}
    };
    _queueMap[id] = queue;
    return queue;
  }

  void clearQueue(String? id) {
    if (id == null) {
      _queueMap.forEach((k, v) => v.dispose());
      _queueMap.clear();
    } else {
      _queueMap[id]?.dispose();
      _queueMap.remove(id);
    }
  }
}
