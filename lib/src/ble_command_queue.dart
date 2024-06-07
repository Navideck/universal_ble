import 'package:universal_ble/src/queue.dart';
import 'package:universal_ble/universal_ble.dart';

/// Execute Commands in queue, and manage queue per device
class BleCommandQueue {
  QueueType queueType = QueueType.global;
  Duration? timeout = const Duration(seconds: 10);
  OnQueueUpdate? onQueueUpdate;
  final Queue _globalQueue = Queue();
  final Map<String, Queue> _queueMap = {};

  BleCommandQueue() {
    _globalQueue.onRemainingItemsUpdate = (int items) {
      onQueueUpdate?.call(QueueType.global.name, items);
    };
  }

  Future<T> executeCommand<T>(
    Future<T> Function() command, {
    bool withTimeout = true,
    String? deviceId,
  }) {
    Duration? duration = withTimeout ? timeout : null;
    switch (queueType) {
      case QueueType.none:
        return duration != null ? command().timeout(duration) : command();
      case QueueType.global:
        return _globalQueue.add(command, timeout: duration);
      case QueueType.perDevice:
        // If deviceId not available, use global queue
        if (deviceId != null) {
          return _getQueue(deviceId).add(command, timeout: duration);
        } else {
          return _globalQueue.add(command, timeout: duration);
        }
    }
  }

  Queue _getQueue(String deviceId) {
    Queue? queue = _queueMap[deviceId];
    if (queue == null) {
      queue = Queue();
      queue.onRemainingItemsUpdate = (int items) {
        onQueueUpdate?.call(deviceId, items);
      };
      _queueMap[deviceId] = queue;
    }
    return queue;
  }
}
