import 'dart:developer';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

abstract class UniversalBlePlatform {
  Future<AvailabilityState> getBluetoothAvailabilityState();

  Future<bool> enableBluetooth();

  Future<void> startScan({
    WebRequestOptionsBuilder? webRequestOptions,
  });

  Future<void> stopScan();

  Future<void> connect(String deviceId, {Duration? connectionTimeout});

  Future<void> disconnect(String deviceId);

  Future<List<BleService>> discoverServices(String deviceId);

  Future<void> setNotifiable(String deviceId, String service,
      String characteristic, BleInputProperty bleInputProperty);

  Future<Uint8List> readValue(
      String deviceId, String service, String characteristic);

  Future<void> writeValue(
      String deviceId,
      String service,
      String characteristic,
      Uint8List value,
      BleOutputProperty bleOutputProperty);

  Future<int> requestMtu(String deviceId, int expectedMtu);

  Future<bool> isPaired(String deviceId);

  Future<void> pair(String deviceId);

  Future<void> unPair(String deviceId);

  Future<List<BleScanResult>> getConnectedDevices(
    List<String>? withServices,
  );

  OnAvailabilityChange? onAvailabilityChange;
  OnScanResult? onScanResult;
  OnConnectionChanged? onConnectionChanged;
  OnValueChanged? onValueChanged;
  OnPairingStateChange? onPairingStateChange;

  static void logInfo(String message, {bool isError = false}) {
    if (isError) message = '\x1B[31m$message\x1B[31m';
    log(message, name: 'UniversalBle');
  }
}
