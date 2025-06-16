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
  }) {
    Duration? timeoutDuration = timeout ?? this.timeout;
    if (timeoutDuration == null) {
      return queueCommandWithoutTimeout(command, deviceId: deviceId);
    }
    return switch (queueType) {
      QueueType.global => _queue().add(command, timeoutDuration),
      QueueType.perDevice => _queue(deviceId).add(command, timeoutDuration),
      QueueType.none => command().timeout(timeoutDuration),
    };
  }

  Future<T> queueCommandWithoutTimeout<T>(
    Future<T> Function() command, {
    String? deviceId,
  }) {
    return switch (queueType) {
      QueueType.global => _queue().add(command),
      QueueType.perDevice => _queue(deviceId).add(command),
      QueueType.none => command(),
    };
  }

  Queue _queue([String? id = globalQueueId]) =>
      _queueMap[id] ?? _newQueue(id ?? globalQueueId);

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
}
