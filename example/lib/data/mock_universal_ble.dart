import 'dart:convert';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

/// Mock implementation of [UniversalBlePlatform] for testing
class MockUniversalBle extends UniversalBlePlatform {
  final _mockBleDevice = BleDevice(
    name: 'MockDevice',
    deviceId: 'MockDeviceId',
    rssi: 50,
    manufacturerData: Uint8List(0),
  );

  Uint8List _serviceValue = utf8.encode('Result');

  final BleService _mockService = BleService('180', [
    BleCharacteristic('180A', [
      CharacteristicProperty.read,
      CharacteristicProperty.write,
      CharacteristicProperty.notify,
    ]),
  ]);

  @override
  Future<void> startScan({
    ScanFilter? scanFilter,
    PlatformConfig? platformConfig,
  }) async =>
      updateScanResult(_mockBleDevice);

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> connect(String deviceId, {Duration? connectionTimeout}) async {
    updateConnection(deviceId, true);
  }

  @override
  Future<void> disconnect(String deviceId) async {
    updateConnection(deviceId, false);
  }

  @override
  Future<List<BleService>> discoverServices(String deviceId) async {
    return [_mockService];
  }

  @override
  Future<bool> enableBluetooth() async {
    await Future.delayed(const Duration(milliseconds: 500));
    return true;
  }

  @override
  Future<AvailabilityState> getBluetoothAvailabilityState() async {
    return AvailabilityState.poweredOn;
  }

  @override
  Future<List<BleDevice>> getSystemDevices(List<String>? withServices) async {
    return [];
  }

  @override
  Future<Uint8List> readValue(
      String deviceId, String service, String characteristic) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return _serviceValue;
  }

  @override
  Future<void> writeValue(
      String deviceId,
      String service,
      String characteristic,
      Uint8List value,
      BleOutputProperty bleOutputProperty) async {
    await Future.delayed(const Duration(milliseconds: 500));
    _serviceValue = value;
  }

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) async {
    await Future.delayed(const Duration(seconds: 1));
    return 512;
  }

  @override
  Future<void> setNotifiable(String deviceId, String service,
      String characteristic, BleInputProperty bleInputProperty) async {}

  @override
  Future<bool> isPaired(String deviceId) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return true;
  }

  @override
  Future<void> pair(String deviceId) async {
    updatePairingState(deviceId, true, null);
  }

  @override
  Future<void> unpair(String deviceId) async {
    updatePairingState(deviceId, false, null);
  }

  @override
  Future<BleConnectionState> getConnectionState(String deviceId) {
    throw UnimplementedError();
  }
}
