import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

typedef OnPeripheralAdvertisingStatusUpdate = void Function(
    bool advertising, String? error);
typedef OnPeripheralBleStateChange = void Function(bool enabled);
typedef OnPeripheralBondStateChange = void Function(
  String deviceId,
  PeripheralBondState state,
);
typedef OnPeripheralCharacteristicSubscriptionChange = void Function(
  String deviceId,
  String characteristicId,
  bool isSubscribed,
  String? name,
);
typedef OnPeripheralConnectionStateChange = void Function(
  String deviceId,
  bool connected,
);
typedef OnPeripheralReadRequest = BleReadRequestResult? Function(
  String deviceId,
  String characteristicId,
  int offset,
  Uint8List? value,
);
typedef OnPeripheralServiceAdded = void Function(
    String serviceId, String? error);
typedef OnPeripheralWriteRequest = BleWriteRequestResult? Function(
  String deviceId,
  String characteristicId,
  int offset,
  Uint8List? value,
);
typedef OnPeripheralMtuChange = void Function(String deviceId, int mtu);

enum PeripheralBondState { bonding, bonded, none }

abstract class UniversalBlePeripheralPlatform {
  OnPeripheralAdvertisingStatusUpdate? advertisingStatusUpdateCallback;
  OnPeripheralBleStateChange? bleStateChangeCallback;
  OnPeripheralBondStateChange? bondStateChangeCallback;
  OnPeripheralCharacteristicSubscriptionChange? subscriptionChangeCallback;
  OnPeripheralConnectionStateChange? connectionStateChangeCallback;
  OnPeripheralReadRequest? readRequestCallback;
  OnPeripheralServiceAdded? serviceAddedCallback;
  OnPeripheralWriteRequest? writeRequestCallback;
  OnPeripheralMtuChange? mtuChangeCallback;

  Future<void> initialize();
  Future<bool> isSupported();
  Future<bool> isAdvertising();

  Future<void> addService(
    BleService service, {
    bool primary = true,
    Duration? timeout,
  });

  Future<void> removeService(String serviceId);
  Future<void> clearServices();
  Future<List<String>> getServices();
  Future<void> startAdvertising({
    required List<String> services,
    String? localName,
    int? timeout,
    ManufacturerData? manufacturerData,
    bool addManufacturerDataInScanResponse = false,
  });
  Future<void> stopAdvertising();
  Future<void> updateCharacteristic({
    required String characteristicId,
    required Uint8List value,
    String? deviceId,
  });

  /// Returns GATT central device ids currently subscribed to [characteristicId].
  Future<List<String>> getSubscribedCentrals(String characteristicId);

  /// Called when this platform implementation is being replaced.
  ///
  /// Default is no-op so existing custom implementations remain compatible.
  void dispose() {}
}

class UniversalBlePeripheralUnsupported extends UniversalBlePeripheralPlatform {
  UnsupportedError _notSupported() =>
      UnsupportedError('BLE peripheral mode is not supported on this platform');

  @override
  Future<void> addService(
    BleService service, {
    bool primary = true,
    Duration? timeout,
  }) async {
    throw _notSupported();
  }

  @override
  Future<void> clearServices() async {
    throw _notSupported();
  }

  @override
  Future<List<String>> getServices() async {
    throw _notSupported();
  }

  @override
  Future<void> initialize() async {
    throw _notSupported();
  }

  @override
  Future<bool> isAdvertising() async {
    throw _notSupported();
  }

  @override
  Future<bool> isSupported() async => false;

  @override
  Future<void> removeService(String serviceId) async {
    throw _notSupported();
  }

  @override
  Future<void> startAdvertising({
    required List<String> services,
    String? localName,
    int? timeout,
    ManufacturerData? manufacturerData,
    bool addManufacturerDataInScanResponse = false,
  }) async {
    throw _notSupported();
  }

  @override
  Future<void> stopAdvertising() async {
    throw _notSupported();
  }

  @override
  Future<void> updateCharacteristic({
    required String characteristicId,
    required Uint8List value,
    String? deviceId,
  }) async {
    throw _notSupported();
  }

  @override
  Future<List<String>> getSubscribedCentrals(String characteristicId) async {
    throw _notSupported();
  }
}
