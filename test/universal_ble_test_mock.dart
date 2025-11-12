import 'dart:typed_data';
import 'package:universal_ble/universal_ble.dart';

abstract class UniversalBlePlatformMock extends UniversalBlePlatform {
  @override
  Future<void> connect(String deviceId, {Duration? connectionTimeout}) {
    throw UnimplementedError();
  }

  @override
  Future<bool> disableBluetooth() {
    throw UnimplementedError();
  }

  @override
  Future<void> disconnect(String deviceId) {
    throw UnimplementedError();
  }

  @override
  Future<List<BleService>> discoverServices(String deviceId) {
    throw UnimplementedError();
  }

  @override
  Future<bool> enableBluetooth() {
    throw UnimplementedError();
  }

  @override
  Future<AvailabilityState> getBluetoothAvailabilityState() {
    throw UnimplementedError();
  }

  @override
  Future<BleConnectionState> getConnectionState(String deviceId) {
    throw UnimplementedError();
  }

  @override
  Future<List<BleDevice>> getSystemDevices(List<String>? withServices) {
    throw UnimplementedError();
  }

  @override
  Future<bool> isPaired(String deviceId) {
    throw UnimplementedError();
  }

  @override
  Future<bool> pair(String deviceId) {
    throw UnimplementedError();
  }

  @override
  Future<Uint8List> readValue(
      String deviceId, String service, String characteristic,
      {Duration? timeout}) {
    throw UnimplementedError();
  }

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) {
    throw UnimplementedError();
  }

  @override
  Future<void> setNotifiable(String deviceId, String service,
      String characteristic, BleInputProperty bleInputProperty) {
    throw UnimplementedError();
  }

  @override
  Future<void> startScan(
      {ScanFilter? scanFilter, PlatformConfig? platformConfig}) {
    throw UnimplementedError();
  }

  @override
  Future<void> stopScan() {
    throw UnimplementedError();
  }

  @override
  Future<void> unpair(String deviceId) {
    throw UnimplementedError();
  }

  @override
  Future<void> writeValue(
      String deviceId,
      String service,
      String characteristic,
      Uint8List value,
      BleOutputProperty bleOutputProperty) {
    throw UnimplementedError();
  }

  @override
  Future<bool> isScanning() {
    throw UnimplementedError();
  }
}
