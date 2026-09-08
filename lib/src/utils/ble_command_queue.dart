import 'package:flutter/foundation.dart';
import 'package:universal_ble/src/queue.dart';
import 'package:universal_ble/universal_ble.dart';

/// Set queue type and queue commands
class BleCommandQueue {
  QueueType queueType;
  Duration? timeout = const Duration(seconds: 10);
  OnQueueUpdate? onQueueUpdate;
  final Map<String, Queue> _queueMap = {};
  static const String globalQueueId = 'global';

  BleCommandQueue({this.queueType = QueueType.auto});

  /// Resolve [QueueType.auto] to a concrete queue type based on the
  /// current platform. Android is the only platform whose native BLE stack
  /// requires serialization (its `mDeviceBusy` GATT state machine rejects
  /// overlapping operations), so it gets a per-device queue. All other
  /// platforms pipeline natively and run commands in parallel.
  QueueType get _resolvedQueueType => queueType == QueueType.auto
      ? (!kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? QueueType.perDevice
          : QueueType.none)
      : queueType;

  Future<T> queueCommand<T>(
    Future<T> Function() command, {
    String? deviceId,
    Duration? timeout,
    String? queueId,
  }) {
    Duration? timeoutDuration = timeout ?? this.timeout;
    if (timeoutDuration == null) {
      return queueCommandWithoutTimeout(
        command,
        deviceId: deviceId,
        queueId: queueId,
      );
    }
    return switch (_resolvedQueueType) {
      QueueType.global => _queue(queueId).add(command, timeoutDuration),
      QueueType.perDevice => _queue(
          queueId ?? deviceId,
        ).add(command, timeoutDuration),
      QueueType.none || QueueType.auto => command().timeout(timeoutDuration),
    };
  }

  Future<T> queueCommandWithoutTimeout<T>(
    Future<T> Function() command, {
    String? deviceId,
    String? queueId,
  }) {
    return switch (_resolvedQueueType) {
      QueueType.global => _queue(queueId).add(command),
      QueueType.perDevice => _queue(queueId ?? deviceId).add(command),
      QueueType.none || QueueType.auto => command(),
    };
  }

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
