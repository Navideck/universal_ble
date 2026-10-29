import 'package:flutter/foundation.dart';
import 'package:universal_ble/src/universal_ble_pigeon/universal_ble_peripheral_pigeon.dart';
import 'package:universal_ble/src/utils/ble_central_tracker.dart';
import 'package:universal_ble/src/utils/ble_command_queue.dart';
import 'package:universal_ble/src/utils/universal_logger.dart';
import 'package:universal_ble/universal_ble.dart';

class UniversalBlePeripheral {
  static UniversalBlePeripheralPlatform? _instance;
  static UniversalBlePeripheralPlatform get _platform {
    _instance ??= _defaultPlatform();
    _ensureTrackerBound();
    return _instance!;
  }

  static final BleCommandQueue _bleCommandQueue = BleCommandQueue(
    isAddressSupplier: () => _platform.hasAddressDeviceIds,
  );
  static final BleCentralTracker _centralTracker = BleCentralTracker();
  static bool _trackerBound = false;

  static void _ensureTrackerBound() {
    if (_trackerBound) return;
    final platform = _instance ??= _defaultPlatform();
    _trackerBound = true;
    try {
      _centralTracker.bindStreams(
        characteristicSubscriptionStream:
            platform.characteristicSubscriptionStream,
        connectionStateStream: platform.connectionStateStream,
      );
    } catch (_) {
      _trackerBound = false;
      // Platform implementation may not support or mock these streams.
    }
  }

  static void setInstance(UniversalBlePeripheralPlatform instance) {
    _instance?.dispose();
    _instance = instance;
    _trackerBound = false;
    _centralTracker.reset();
    _ensureTrackerBound();
  }

  /// Set global timeout for all peripheral commands.
  /// Default timeout is 10 seconds.
  /// Set to null to disable.
  static set timeout(Duration? duration) {
    _bleCommandQueue.timeout = duration;
  }

  /// Set how peripheral commands will be executed. By default, [QueueType.auto] is used,
  /// which automatically picks the best strategy for the current platform: Android, Web
  /// and Linux use a per-device queue (their BLE stacks reject or misbehave on overlapping
  /// operations), while all other platforms run commands in parallel (they pipeline natively).
  ///
  /// [QueueType.global] will execute commands in a single queue.
  /// [QueueType.perDevice] will execute commands of each device in separate queues.
  /// [QueueType.none] will execute all commands in parallel.
  static set queueType(QueueType queueType) {
    _bleCommandQueue.queueType = queueType;
    UniversalLogger.logInfo('Peripheral Queue ${queueType.name}');
  }

  /// Clear all pending queued peripheral commands.
  /// If [id] is provided, clears the queue for that specific device or queueId.
  static void clearQueue([String? id]) {
    _bleCommandQueue.clearQueue(id);
  }

  /// Callback when the remaining items in a peripheral command queue changes.
  static set onQueueUpdate(OnQueueUpdate? onQueueUpdate) {
    _bleCommandQueue.onQueueUpdate = onQueueUpdate;
  }

  /// Advertising state update stream.
  static Stream<BlePeripheralAdvertisingStateChanged>
      get advertisingStateStream => _platform.advertisingStateStream;

  /// Characteristic subscription update stream.
  static Stream<BlePeripheralCharacteristicSubscriptionChanged>
      get characteristicSubscriptionStream =>
          _platform.characteristicSubscriptionStream;

  /// Connection state update stream.
  static Stream<BlePeripheralConnectionStateChanged>
      get connectionStateStream => _platform.connectionStateStream;

  /// Service addition update stream.
  static Stream<BlePeripheralServiceAdded> get serviceAddedStream =>
      _platform.serviceAddedStream;

  /// MTU update stream.
  static Stream<BlePeripheralMtuChanged> get mtuChangedStream =>
      _platform.mtuChangedStream;

  /// Stream of currently subscribed BLE central devices.
  ///
  /// Emits the current list of subscribed centrals upon listening and
  /// whenever a central subscribes to/unsubscribes from characteristics
  /// or disconnects.
  static Stream<List<BleCentral>> get subscribedCentralsStream {
    _ensureTrackerBound();
    return _centralTracker.stream;
  }

  /// Returns the current list of central devices subscribed to at least
  /// one characteristic.
  static List<BleCentral> get subscribedCentrals {
    _ensureTrackerBound();
    return _centralTracker.subscribedCentrals;
  }

  static void setReadRequestHandlers(OnPeripheralReadRequest? handlers) =>
      _platform.setReadRequestHandler(handlers);

  /// Sets the handler for individual characteristic writes.
  ///
  /// On Apple platforms, multi-request write batches are rejected with
  /// `requestNotSupported` before any handler is invoked. This API cannot
  /// validate or roll back the entire batch atomically.
  static void setWriteRequestHandlers(OnPeripheralWriteRequest? handlers) =>
      _platform.setWriteRequestHandler(handlers);

  static void setDescriptorReadRequestHandlers(
    OnPeripheralDescriptorReadRequest? handlers,
  ) =>
      _platform.setDescriptorReadRequestHandler(handlers);

  static void setDescriptorWriteRequestHandlers(
    OnPeripheralDescriptorWriteRequest? handlers,
  ) =>
      _platform.setDescriptorWriteRequestHandler(handlers);

  /// Instance-aware read handler; used when several characteristics share a
  /// UUID (HID Report characteristics).
  static void setReadRequestHandlersWithInstance(
    OnPeripheralReadRequestWithInstance? handlers,
  ) =>
      _platform.setReadRequestHandlerWithInstance(handlers);

  /// Instance-aware variant of [setWriteRequestHandlers], with the same
  /// restriction on multi-request write batches on Apple platforms.
  static void setWriteRequestHandlersWithInstance(
    OnPeripheralWriteRequestWithInstance? handlers,
  ) =>
      _platform.setWriteRequestHandlerWithInstance(handlers);

  static void setDescriptorReadRequestHandlersWithInstance(
    OnPeripheralDescriptorReadRequestWithInstance? handlers,
  ) =>
      _platform.setDescriptorReadRequestHandlerWithInstance(handlers);

  static void setDescriptorWriteRequestHandlersWithInstance(
    OnPeripheralDescriptorWriteRequestWithInstance? handlers,
  ) =>
      _platform.setDescriptorWriteRequestHandlerWithInstance(handlers);

  static Future<PeripheralReadinessState> getAvailabilityState() =>
      _platform.getAvailabilityState();

  static Future<PeripheralAdvertisingState> getAdvertisingState() =>
      _platform.getAdvertisingState();

  static Future<BlePeripheralCapabilities> getCapabilities() =>
      _platform.getCapabilities();

  static Future<void> addService(
    BlePeripheralService service, {
    Duration? timeout,
  }) =>
      _bleCommandQueue.queueCommand(
        () async {
          await _platform.addService(
            service.toPeripheralService(),
            timeout: timeout,
          );
          _centralTracker.registerService(
            service.uuid,
            service.characteristics.map((c) => c.uuid),
          );
        },
        timeout: timeout,
      );

  static Future<void> removeService(String serviceId) =>
      _bleCommandQueue.queueCommand(
        () async {
          final normalizedServiceId = BleUuidParser.string(serviceId);
          await _platform.removeService(normalizedServiceId);
          _centralTracker.removeService(normalizedServiceId);
        },
      );

  static Future<void> clearServices() => _bleCommandQueue.queueCommand(
        () async {
          await _platform.clearServices();
          _centralTracker.clear();
        },
      );

  static Future<List<String>> getServices() => _bleCommandQueue.queueCommand(
        () => _platform.getServices(),
      );

  static Future<void> startAdvertising({
    required List<String> services,
    String? localName,
    Duration? timeout,
    ManufacturerData? manufacturerData,
    PeripheralPlatformConfig? platformConfig,
  }) =>
      _bleCommandQueue.queueCommand(
        () => _platform.startAdvertising(
          services: services.map(BleUuidParser.string).toList(),
          localName: localName,
          timeout: timeout,
          manufacturerData: manufacturerData,
          platformConfig: platformConfig,
        ),
        timeout: timeout,
      );

  static Future<void> stopAdvertising() => _bleCommandQueue.queueCommand(
        () => _platform.stopAdvertising(),
      );

  static Future<void> updateCharacteristicValue({
    required String characteristicId,
    String? instanceId,
    required Uint8List value,
    String? deviceId,
    String? queueId,
  }) =>
      _bleCommandQueue.queueCommand(
        () => _platform.updateCharacteristicValue(
          characteristicId: BleUuidParser.string(characteristicId),
          instanceId: instanceId,
          value: value,
          deviceId: deviceId,
        ),
        deviceId: deviceId,
        queueId: queueId,
      );

  /// Returns client device ids currently subscribed to the characteristic
  /// identified by [characteristicId] (and [instanceId], when the service
  /// exposes several characteristics with the same UUID). Used to restore
  /// in-app state after restart.
  static Future<List<String>> getSubscribedClients(
    String characteristicId, {
    String? instanceId,
  }) =>
      _platform.getSubscribedClients(
        BleUuidParser.string(characteristicId),
        instanceId: instanceId,
      );

  /// Enables Apple peripheral restoration with a stable identifier per engine.
  /// Set `UniversalBlePeripheralRestorationIdentifier` to the same value in the
  /// host Info.plist to recreate the manager early during an OS relaunch.
  /// Call after installing handlers/listeners. No-op on other platforms.
  static Future<void> configureRestoration(String restorationIdentifier) =>
      _platform.configureRestoration(restorationIdentifier);

  /// Discards unsent native notifications and queued Dart updates for a client.
  /// Already submitted packets cannot be recalled.
  static Future<void> clearPendingNotifications([String? deviceId]) {
    clearQueue(deviceId);
    return _platform.clearPendingNotifications(deviceId);
  }

  static Future<int?> getMaximumNotifyLength(String deviceId) =>
      _platform.getMaximumNotifyLength(deviceId);

  static UniversalBlePeripheralPlatform _defaultPlatform() {
    if (!BleCapabilities.supportsPeripheralApi) {
      return UniversalBlePeripheralUnsupported();
    }
    return UniversalBlePeripheralPigeon.instance;
  }
}
