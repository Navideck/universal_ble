import 'package:flutter/foundation.dart';
import 'package:universal_ble/src/universal_ble_peripheral/universal_ble_peripheral_pigeon.dart';
import 'package:universal_ble/universal_ble.dart';

class UniversalBlePeripheral {
  static UniversalBlePeripheralPlatform _platform = _defaultPlatform();

  static UniversalBlePeripheralPlatform _defaultPlatform() {
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.linux) {
      return UniversalBlePeripheralUnsupported();
    }
    return UniversalBlePeripheralPigeon.instance;
  }

  static void setInstance(UniversalBlePeripheralPlatform instance) {
    _platform.dispose();
    _platform = instance;
  }

  static Future<void> initialize() => _platform.initialize();
  static Future<bool> isSupported() => _platform.isSupported();
  static Future<bool> isAdvertising() => _platform.isAdvertising();

  static Future<void> addService(
    BleService service, {
    bool primary = true,
    Duration? timeout,
  }) =>
      _platform.addService(service, primary: primary, timeout: timeout);

  static Future<void> removeService(String serviceId) =>
      _platform.removeService(serviceId);
  static Future<void> clearServices() => _platform.clearServices();
  static Future<List<String>> getServices() => _platform.getServices();

  static Future<void> startAdvertising({
    required List<String> services,
    String? localName,
    int? timeout,
    ManufacturerData? manufacturerData,
    bool addManufacturerDataInScanResponse = false,
  }) =>
      _platform.startAdvertising(
        services: services.map(BleUuidParser.string).toList(),
        localName: localName,
        timeout: timeout,
        manufacturerData: manufacturerData,
        addManufacturerDataInScanResponse: addManufacturerDataInScanResponse,
      );

  static Future<void> stopAdvertising() => _platform.stopAdvertising();

  static Future<void> updateCharacteristic({
    required String characteristicId,
    required Uint8List value,
    String? deviceId,
  }) =>
      _platform.updateCharacteristic(
        characteristicId: characteristicId,
        value: value,
        deviceId: deviceId,
      );

  /// Returns central device ids currently subscribed to [characteristicId]
  /// (e.g. HID report characteristic). Used to restore in-app state after restart.
  static Future<List<String>> getSubscribedCentrals(String characteristicId) =>
      _platform.getSubscribedCentrals(BleUuidParser.string(characteristicId));

  static set onAdvertisingStatusUpdate(
    OnPeripheralAdvertisingStatusUpdate? callback,
  ) {
    _platform.advertisingStatusUpdateCallback = callback;
  }

  static set onSubscriptionChange(
    OnPeripheralCharacteristicSubscriptionChange? callback,
  ) {
    _platform.subscriptionChangeCallback = callback;
  }

  static set onConnectionStateChange(
    OnPeripheralConnectionStateChange? callback,
  ) {
    _platform.connectionStateChangeCallback = callback;
  }

  static set onReadRequest(OnPeripheralReadRequest? callback) {
    _platform.readRequestCallback = callback;
  }

  static set onServiceAdded(OnPeripheralServiceAdded? callback) {
    _platform.serviceAddedCallback = callback;
  }

  static set onWriteRequest(OnPeripheralWriteRequest? callback) {
    _platform.writeRequestCallback = callback;
  }

  static set onMtuChange(OnPeripheralMtuChange? callback) {
    _platform.mtuChangeCallback = callback;
  }
}
