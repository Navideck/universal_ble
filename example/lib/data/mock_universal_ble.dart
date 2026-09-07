import 'dart:convert';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

/// Mock implementation of [UniversalBlePlatform] for testing
class MockUniversalBle extends UniversalBlePlatform {
  final _mockBleDevice = BleDevice(
    name: 'MockDevice',
    deviceId: 'MockDeviceId',
    rssi: 50,
    manufacturerDataList: [],
  );

  Uint8List _serviceValue = utf8.encode('Result');
  bool _isScanning = false;

  final BleService _mockService = BleService('180', [
    BleCharacteristic('180A', [
      CharacteristicProperty.read,
      CharacteristicProperty.write,
      CharacteristicProperty.notify,
    ], []),
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
  Future<void> connect(String deviceId,
      {Duration? connectionTimeout,
      bool autoConnect = false,
      ConnectionPlatformConfig? platformConfig}) async {
    updateConnection(deviceId, true);
  }

  @override
  Future<void> disconnect(String deviceId) async {
    updateConnection(deviceId, false);
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
    return [];
  }

  @override
  Future<Uint8List> readValue(
    String deviceId,
    String service,
    String characteristic, {
    Duration? timeout,
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
  Future<Uint8List> readDescriptorValue(
    String deviceId,
    String service,
    String characteristic,
    String descriptor, {
    Duration? timeout,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return _serviceValue;
  }

  @override
  Future<void> writeDescriptorValue(
    String deviceId,
    String service,
    String characteristic,
    String descriptor,
    Uint8List value,
  ) async {
    await Future.delayed(const Duration(milliseconds: 500));
    _serviceValue = value;
  }

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) async {
    await Future.delayed(const Duration(seconds: 1));
    return 512;
  }

  @override
  Future<void> requestConnectionPriority(
    String deviceId,
    BleConnectionPriority priority,
  ) async {}

  final Set<String> _subscribedCharacteristics = {};

  @override
  Future<void> setNotifiable(String deviceId, String service,
      String characteristic, BleInputProperty bleInputProperty) async {
    if (bleInputProperty == BleInputProperty.disabled) {
      _subscribedCharacteristics.remove(characteristic);
    } else {
      _subscribedCharacteristics.add(characteristic);
    }
  }

  @override
  Future<bool> isSubscribed(
    String deviceId,
    String service,
    String characteristic,
  ) async {
    return _subscribedCharacteristics.contains(characteristic);
  }

  @override
  Future<List<String>> getSubscribedCharacteristics(String deviceId) async {
    return _subscribedCharacteristics.toList();
  }

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
  Future<BleConnectionState> getConnectionState(String deviceId) {
    throw UnimplementedError();
  }

  @override
  Future<bool> disableBluetooth() {
    throw UnimplementedError();
  }

  @override
  Future<void> requestPermissions({bool withAndroidFineLocation = false}) {
    throw UnimplementedError();
  }

  @override
  Future<int> readRssi(String deviceId) {
    throw UnimplementedError();
  }
}
