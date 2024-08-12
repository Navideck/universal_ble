import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';
import 'package:universal_ble/universal_ble.dart';

abstract class UniversalBlePlatform {
  ScanFilter? _scanFilter;
  StreamController? _connectionStreamController;

  Future<AvailabilityState> getBluetoothAvailabilityState();

  Future<bool> enableBluetooth();

  Future<void> startScan({
    ScanFilter? scanFilter,
    PlatformConfig? platformConfig,
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
    String deviceId,
    String service,
    String characteristic, {
    final Duration? timeout,
  });

  Future<void> writeValue(
      String deviceId,
      String service,
      String characteristic,
      Uint8List value,
      BleOutputProperty bleOutputProperty);

  Future<int> requestMtu(String deviceId, int expectedMtu);

  Future<bool> isPaired(String deviceId);

  Future<void> pair(String deviceId);

  Future<void> unpair(String deviceId);

  Future<BleConnectionState> getConnectionState(String deviceId);

  Future<List<BleDevice>> getSystemDevices(
    List<String>? withServices,
  );

  bool receivesAdvertisements(String deviceId) => true;

  Stream<bool> connectionStream(String deviceId) {
    _setupConnectionStreamIfRequired();
    return _connectionStreamController!.stream
        .where((event) => event.deviceId == deviceId)
        .map((event) => event.isConnected);
  }

  void updateScanResult(BleDevice bleDevice) {
    // Filter by name
    ScanFilter? scanFilter = _scanFilter;
    if (scanFilter != null && scanFilter.withNamePrefix.isNotEmpty) {
      if (bleDevice.name == null ||
          !scanFilter.withNamePrefix
              .any((e) => bleDevice.name?.startsWith(e) == true)) return;
    }
    onScanResult?.call(bleDevice);
  }

  void updateConnection(String deviceId, bool isConnected) {
    onConnectionChange?.call(deviceId, isConnected);
    _connectionStreamController
        ?.add((deviceId: deviceId, isConnected: isConnected));
  }

  void updateCharacteristicValue(
      String deviceId, String characteristicId, Uint8List value) {
    onValueChange?.call(
        deviceId, BleUuidParser.string(characteristicId), value);
  }

  void updateAvailability(AvailabilityState state) {
    onAvailabilityChange?.call(state);
  }

  void updatePairingState(String deviceId, bool isPaired, String? error) {
    onPairingStateChange?.call(deviceId, isPaired, error);
  }

  // Do not use these directly to push updates
  OnScanResult? onScanResult;
  OnConnectionChange? onConnectionChange;
  OnValueChange? onValueChange;
  OnAvailabilityChange? onAvailabilityChange;
  OnPairingStateChange? onPairingStateChange;

  static void logInfo(String message, {bool isError = false}) {
    if (isError) message = '\x1B[31m$message\x1B[31m';
    log(message, name: 'UniversalBle');
  }

  /// Creates an auto disposable streamController
  void _setupConnectionStreamIfRequired() {
    if (_connectionStreamController != null) return;

    _connectionStreamController =
        StreamController<({String deviceId, bool isConnected})>.broadcast();

    // Auto dispose if no more subscribers
    _connectionStreamController?.onCancel = () {
      // logInfo('Disposing Connection Stream');
      _connectionStreamController?.close();
      _connectionStreamController = null;
    };
  }
}

// Callback types
typedef OnConnectionChange = void Function(String deviceId, bool isConnected);

typedef OnValueChange = void Function(
    String deviceId, String characteristicId, Uint8List value);

typedef OnScanResult = void Function(BleDevice scanResult);

typedef OnAvailabilityChange = void Function(AvailabilityState state);

typedef OnPairingStateChange = void Function(
    String deviceId, bool isPaired, String? error);

typedef OnQueueUpdate = void Function(String id, int remainingQueueItems);
