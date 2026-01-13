import 'dart:convert';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

/// Mock implementation of [UniversalBlePlatform] for testing
class MockUniversalBle extends UniversalBlePlatform {
  final Map<String, BleConnectionState> _connectionStateMap = {};
  final _mockBleDevice = BleDevice(
    name: 'MockDevice',
    deviceId: 'MockDeviceId',
    rssi: 50,
    manufacturerDataList: [],
  );

  Uint8List _serviceValue = utf8.encode('Result');
  bool _isScanning = false;

  final BleService _mockService = BleService('180a', [
    BleCharacteristic.withMetaData(
      deviceId: 'MockDeviceId',
      serviceId: '180a',
      uuid: '220a',
      properties: [
        CharacteristicProperty.read,
        CharacteristicProperty.write,
        CharacteristicProperty.notify,
      ],
      descriptors: [
        BleDescriptor('220b'),
      ],
    ),
  ]);

  @override
  Future<void> startScan({
    ScanFilter? scanFilter,
    PlatformConfig? platformConfig,
  }) async {
    _isScanning = true;
    updateScanResult(_mockBleDevice);
  }

  @override
  Future<void> stopScan() async {
    _isScanning = false;
  }

  @override
  Future<bool> isScanning() async {
    return _isScanning;
  }

  @override
  Future<void> connect(String deviceId, {bool autoConnect = false, Duration? connectionTimeout}) async {
    updateConnection(deviceId, true);
    _connectionStateMap[deviceId] = BleConnectionState.connected;
  }

  @override
  Future<void> disconnect(String deviceId) async {
    updateConnection(deviceId, false);
    _connectionStateMap[deviceId] = BleConnectionState.disconnected;
  }

  @override
  Future<List<BleService>> discoverServices(
      String deviceId, bool withDescriptors) async {
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
    return [_mockBleDevice];
  }

  @override
  Future<Uint8List> readValue(
    String deviceId,
    String service,
    String characteristic, {
    final Duration? timeout,
  }) async {
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
  Future<int> readRssi(String deviceId) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return -50; // Mock RSSI value in dBm
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
  Future<bool> pair(String deviceId) async {
    updatePairingState(deviceId, true);
    return true;
  }

  @override
  Future<void> unpair(String deviceId) async {
    updatePairingState(deviceId, false);
  }

  @override
  Future<BleConnectionState> getConnectionState(String deviceId) async {
    return _connectionStateMap[deviceId] ?? BleConnectionState.disconnected;
  }

  @override
  Future<bool> disableBluetooth() async {
    return true;
  }

  @override
  Future<void> requestPermissions(
      {bool withAndroidFineLocation = false}) async {
    return;
  }
}
