import 'package:flutter/foundation.dart';
import 'package:universal_ble/src/universal_ble_pigeon/universal_ble_peripheral_pigeon.dart';
import 'package:universal_ble/universal_ble.dart';

class UniversalBlePeripheral {
  static UniversalBlePeripheralPlatform? _instance;
  static UniversalBlePeripheralPlatform get _platform =>
      _instance ??= _defaultPlatform();

  static void setInstance(UniversalBlePeripheralPlatform instance) {
    _instance?.dispose();
    _instance = instance;
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
  ) => _platform.setDescriptorReadRequestHandler(handlers);

  static void setDescriptorWriteRequestHandlers(
    OnPeripheralDescriptorWriteRequest? handlers,
  ) => _platform.setDescriptorWriteRequestHandler(handlers);

  static Future<PeripheralReadinessState> getAvailabilityState() =>
      _platform.getAvailabilityState();

  static Future<PeripheralAdvertisingState> getAdvertisingState() =>
      _platform.getAdvertisingState();

  static Future<BlePeripheralCapabilities> getCapabilities() =>
      _platform.getCapabilities();

  static Future<void> addService(
    BlePeripheralService service, {
    Duration? timeout,
  }) => _platform.addService(service.toPeripheralService(), timeout: timeout);

  static Future<void> removeService(String serviceId) =>
      _platform.removeService(BleUuidParser.string(serviceId));

  static Future<void> clearServices() => _platform.clearServices();

  static Future<List<String>> getServices() => _platform.getServices();

  static Future<void> startAdvertising({
    required List<String> services,
    String? localName,
    Duration? timeout,
    ManufacturerData? manufacturerData,
    PeripheralPlatformConfig? platformConfig,
  }) => _platform.startAdvertising(
    services: services.map(BleUuidParser.string).toList(),
    localName: localName,
    timeout: timeout,
    manufacturerData: manufacturerData,
    platformConfig: platformConfig,
  );

  static Future<void> stopAdvertising() => _platform.stopAdvertising();

  static Future<void> updateCharacteristicValue({
    required String characteristicId,
    required Uint8List value,
    String? deviceId,
  }) => _platform.updateCharacteristicValue(
    characteristicId: BleUuidParser.string(characteristicId),
    value: value,
    deviceId: deviceId,
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
