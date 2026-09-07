import 'package:flutter/foundation.dart';
import 'package:universal_ble/src/universal_ble_pigeon/universal_ble_peripheral_pigeon.dart';
import 'package:universal_ble/src/utils/ble_command_queue.dart';
import 'package:universal_ble/src/utils/universal_logger.dart';
import 'package:universal_ble/universal_ble.dart';

class UniversalBlePeripheral {
  static UniversalBlePeripheralPlatform? _instance;
  static UniversalBlePeripheralPlatform get _platform =>
      _instance ??= _defaultPlatform();
  static final BleCommandQueue _bleCommandQueue = BleCommandQueue();

  static void setInstance(UniversalBlePeripheralPlatform instance) {
    _instance?.dispose();
    _instance = instance;
  }

  /// Set global timeout for all peripheral commands.
  /// Default timeout is 10 seconds.
  /// Set to null to disable.
  static set timeout(Duration? duration) {
    _bleCommandQueue.timeout = duration;
  }

  /// Set how peripheral commands will be executed. By default, all commands are executed in a global queue (`QueueType.global`),
  /// with each command waiting for the previous one to finish.
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

  static void setReadRequestHandlers(OnPeripheralReadRequest? handlers) =>
      _platform.setReadRequestHandler(handlers);

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
        () => _platform.addService(service.toPeripheralService(),
            timeout: timeout),
        timeout: timeout,
      );

  static Future<void> removeService(String serviceId) =>
      _bleCommandQueue.queueCommand(
        () => _platform.removeService(BleUuidParser.string(serviceId)),
      );

  static Future<void> clearServices() => _bleCommandQueue.queueCommand(
        () => _platform.clearServices(),
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
    required Uint8List value,
    String? deviceId,
    String? queueId,
  }) =>
      _bleCommandQueue.queueCommand(
        () => _platform.updateCharacteristicValue(
          characteristicId: BleUuidParser.string(characteristicId),
          value: value,
          deviceId: deviceId,
        ),
        deviceId: deviceId,
        queueId: queueId,
      );

  /// Returns client device ids currently subscribed to [characteristicId]
  /// (e.g. HID report characteristic). Used to restore in-app state after restart.
  static Future<List<String>> getSubscribedClients(String characteristicId) =>
      _platform.getSubscribedClients(BleUuidParser.string(characteristicId));

  static Future<int?> getMaximumNotifyLength(String deviceId) =>
      _platform.getMaximumNotifyLength(deviceId);

  static UniversalBlePeripheralPlatform _defaultPlatform() {
    if (!BleCapabilities.supportsPeripheralApi) {
      return UniversalBlePeripheralUnsupported();
    }
    return UniversalBlePeripheralPigeon.instance;
  }
}
