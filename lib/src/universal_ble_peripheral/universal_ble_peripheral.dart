import 'package:flutter/foundation.dart';
import 'package:universal_ble/src/universal_ble_peripheral/universal_ble_peripheral_pigeon.dart';
import 'package:universal_ble/universal_ble.dart';

class UniversalBlePeripheralClient {
  UniversalBlePeripheralPlatform _platform;

  UniversalBlePeripheralClient({UniversalBlePeripheralPlatform? platform})
      : _platform = platform ?? UniversalBlePeripheral._defaultPlatform();

  void setPlatform(UniversalBlePeripheralPlatform platform) {
    _platform.dispose();
    _platform = platform;
  }

  Stream<UniversalBlePeripheralEvent> get eventStream => _platform.eventStream;

  void setRequestHandlers({
    OnPeripheralReadRequest? onReadRequest,
    OnPeripheralWriteRequest? onWriteRequest,
  }) {
    _platform.setRequestHandlers(
      onReadRequest: onReadRequest,
      onWriteRequest: onWriteRequest,
    );
  }

  Future<UniversalBlePeripheralReadinessState> getReadinessState() =>
      _platform.getReadinessState();

  Future<UniversalBlePeripheralAdvertisingState> getAdvertisingState() =>
      _platform.getAdvertisingState();

  Future<UniversalBlePeripheralCapabilities> getCapabilities() =>
      _platform.getCapabilities();

  Future<void> addService(
    BleService service, {
    bool primary = true,
    Duration? timeout,
  }) =>
      _platform.addService(service, primary: primary, timeout: timeout);

  Future<void> removeService(PeripheralServiceId serviceId) =>
      _platform.removeService(
        PeripheralServiceId(BleUuidParser.string(serviceId.value)),
      );

  Future<void> clearServices() => _platform.clearServices();

  Future<List<PeripheralServiceId>> getServices() => _platform.getServices();

  Future<void> startAdvertising({
    required List<PeripheralServiceId> services,
    String? localName,
    int? timeout,
    ManufacturerData? manufacturerData,
    bool addManufacturerDataInScanResponse = false,
  }) =>
      _platform.startAdvertising(
        services: services
            .map((e) => PeripheralServiceId(BleUuidParser.string(e.value)))
            .toList(),
        localName: localName,
        timeout: timeout,
        manufacturerData: manufacturerData,
        addManufacturerDataInScanResponse: addManufacturerDataInScanResponse,
      );

  Future<void> stopAdvertising() => _platform.stopAdvertising();

  Future<void> updateCharacteristicValue({
    required String characteristicId,
    required Uint8List value,
    PeripheralUpdateTarget target = const PeripheralUpdateAllSubscribed(),
  }) =>
      _platform.updateCharacteristicValue(
        characteristicId: characteristicId,
        value: value,
        target: target,
      );

  Future<List<String>> getSubscribedClients(String characteristicId) =>
      _platform.getSubscribedClients(BleUuidParser.string(characteristicId));
}

class UniversalBlePeripheral {
  static UniversalBlePeripheralClient? _clientInstance;
  static UniversalBlePeripheralClient get _client =>
      _clientInstance ??= UniversalBlePeripheralClient();

  static UniversalBlePeripheralPlatform _defaultPlatform() {
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.linux) {
      return UniversalBlePeripheralUnsupported();
    }
    return UniversalBlePeripheralPigeon.instance;
  }

  static void setInstance(UniversalBlePeripheralPlatform instance) {
    if (_clientInstance == null) {
      _clientInstance = UniversalBlePeripheralClient(platform: instance);
      return;
    }
    _client.setPlatform(instance);
  }

  static Stream<UniversalBlePeripheralEvent> get eventStream =>
      _client.eventStream;

  static void setRequestHandlers({
    OnPeripheralReadRequest? onReadRequest,
    OnPeripheralWriteRequest? onWriteRequest,
  }) {
    _client.setRequestHandlers(
      onReadRequest: onReadRequest,
      onWriteRequest: onWriteRequest,
    );
  }

  static Future<UniversalBlePeripheralReadinessState> getReadinessState() =>
      _client.getReadinessState();

  static Future<UniversalBlePeripheralAdvertisingState> getAdvertisingState() =>
      _client.getAdvertisingState();

  static Future<UniversalBlePeripheralCapabilities> getCapabilities() =>
      _client.getCapabilities();

  static Future<void> addService(
    BleService service, {
    bool primary = true,
    Duration? timeout,
  }) =>
      _client.addService(service, primary: primary, timeout: timeout);

  static Future<void> removeService(PeripheralServiceId serviceId) =>
      _client.removeService(serviceId);
  static Future<void> clearServices() => _client.clearServices();
  static Future<List<PeripheralServiceId>> getServices() => _client.getServices();

  static Future<void> startAdvertising({
    required List<PeripheralServiceId> services,
    String? localName,
    int? timeout,
    ManufacturerData? manufacturerData,
    bool addManufacturerDataInScanResponse = false,
  }) =>
      _client.startAdvertising(
        services: services,
        localName: localName,
        timeout: timeout,
        manufacturerData: manufacturerData,
        addManufacturerDataInScanResponse: addManufacturerDataInScanResponse,
      );

  static Future<void> stopAdvertising() => _client.stopAdvertising();

  static Future<void> updateCharacteristicValue({
    required String characteristicId,
    required Uint8List value,
    PeripheralUpdateTarget target = const PeripheralUpdateAllSubscribed(),
  }) =>
      _client.updateCharacteristicValue(
          characteristicId: characteristicId, value: value, target: target);

  /// Returns client device ids currently subscribed to [characteristicId]
  /// (e.g. HID report characteristic). Used to restore in-app state after restart.
  static Future<List<String>> getSubscribedClients(String characteristicId) =>
      _client.getSubscribedClients(characteristicId);
}
