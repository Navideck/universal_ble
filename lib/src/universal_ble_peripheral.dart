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

  static Stream<UniversalBlePeripheralEvent> get eventStream =>
      _platform.eventStream;

  static void setRequestHandlers(PeripheralRequestHandlers handlers) =>
      _platform.setRequestHandlers(handlers);

  static Future<PeripheralReadinessState> getAvailabilityState() =>
      _platform.getAvailabilityState();

  static Future<PeripheralAdvertisingState> getAdvertisingState() =>
      _platform.getAdvertisingState();

  static Future<UniversalBlePeripheralCapabilities> getCapabilities() =>
      _platform.getCapabilities();

  static Future<void> addService(
    PeripheralService service, {
    Duration? timeout,
  }) => _platform.addService(service, timeout: timeout);

  static Future<void> removeService(String serviceId) =>
      _platform.removeService(BleUuidParser.string(serviceId));

  static Future<void> clearServices() => _platform.clearServices();

  static Future<List<String>> getServices() => _platform.getServices();

  static Future<void> startAdvertising({
    required List<String> services,
    String? localName,
    Duration? timeout,
    ManufacturerData? manufacturerData,
    bool addManufacturerDataInScanResponse = false,
  }) => _platform.startAdvertising(
    services: services.map(BleUuidParser.string).toList(),
    localName: localName,
    timeout: timeout,
    manufacturerData: manufacturerData,
    addManufacturerDataInScanResponse: addManufacturerDataInScanResponse,
  );

  static Future<void> stopAdvertising() => _platform.stopAdvertising();

  static Future<void> updateCharacteristicValue({
    required String characteristicId,
    required Uint8List value,
    PeripheralUpdateTarget target = const PeripheralUpdateAllSubscribed(),
  }) => _platform.updateCharacteristicValue(
    characteristicId: BleUuidParser.string(characteristicId),
    value: value,
    target: target,
  );

  /// Returns client device ids currently subscribed to [characteristicId]
  /// (e.g. HID report characteristic). Used to restore in-app state after restart.
  static Future<List<String>> getSubscribedClients(String characteristicId) =>
      _platform.getSubscribedClients(BleUuidParser.string(characteristicId));

  static Future<int?> getMaximumNotifyLength(String deviceId) =>
      _platform.getMaximumNotifyLength(deviceId);

  static UniversalBlePeripheralPlatform _defaultPlatform() {
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.linux) {
      return UniversalBlePeripheralUnsupported();
    }
    return UniversalBlePeripheralPigeon.instance;
  }
}
