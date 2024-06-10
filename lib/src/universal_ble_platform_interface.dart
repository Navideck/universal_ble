import 'dart:developer';
import 'dart:typed_data';
import 'package:universal_ble/universal_ble.dart';

abstract class UniversalBlePlatform {
  ScanFilter? _scanFilter;

  Future<AvailabilityState> getBluetoothAvailabilityState();

  Future<bool> enableBluetooth();

  Future<void> startScan({
    ScanFilter? scanFilter,
  }) async {
    _scanFilter = scanFilter;
  }

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

  void updateScanResult(BleScanResult scanResult) {
    // Filter by name
    ScanFilter? scanFilter = _scanFilter;
    if (scanFilter != null && scanFilter.withNamePrefix.isNotEmpty) {
      if (scanResult.name == null ||
          !scanFilter.withNamePrefix
              .any((e) => scanResult.name?.startsWith(e) == true)) return;
    }
    onScanResult?.call(scanResult);
  }

  OnAvailabilityChange? onAvailabilityChange;
  OnScanResult? onScanResult;
  OnConnectionChanged? onConnectionChanged;
  OnValueChanged? onValueChanged;
  OnPairingStateChange? onPairingStateChange;
  OnPinPairRequest? onPinPairRequest;

  static void logInfo(String message, {bool isError = false}) {
    if (isError) message = '\x1B[31m$message\x1B[31m';
    log(message, name: 'UniversalBle');
  }
}

// Callback types
typedef OnConnectionChanged = void Function(
    String deviceId, BleConnectionState state);

typedef OnValueChanged = void Function(
    String deviceId, String characteristicId, Uint8List value);

typedef OnScanResult = void Function(BleScanResult scanResult);

typedef OnAvailabilityChange = void Function(AvailabilityState state);

typedef OnPairingStateChange = void Function(
    String deviceId, bool isPaired, String? error);

typedef OnPinPairRequest = Future<String?> Function();

typedef OnQueueUpdate = void Function(String id, int remainingQueueItems);