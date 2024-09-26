import 'dart:async';
import 'dart:typed_data';
import 'package:universal_ble/universal_ble.dart';

abstract class UniversalBlePlatform {
  StreamController<({String deviceId, bool isConnected, String? error})>?
      _connectionStreamController;

  final Map<String, bool> _pairStateMap = {};

  Future<AvailabilityState> getBluetoothAvailabilityState();

  Future<bool> enableBluetooth();

  Future<void> startScan({
    ScanFilter? scanFilter,
    PlatformConfig? platformConfig,
  });

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

  Future<bool> pair(String deviceId);

  Future<void> unpair(String deviceId);

  Future<BleConnectionState> getConnectionState(String deviceId);

  Future<List<BleDevice>> getSystemDevices(
    List<String>? withServices,
  );

  bool receivesAdvertisements(String deviceId) => true;

  Stream<BleConnectionUpdate> connectionStream(String deviceId) {
    _setupConnectionStreamIfRequired();
    return _connectionStreamController!.stream
        .where((event) => event.deviceId == deviceId)
        .map((event) => BleConnectionUpdate(
              isConnected: event.isConnected,
              error: event.error,
            ));
  }

  void updateScanResult(BleDevice bleDevice) {
    onScanResult?.call(bleDevice);
  }

  void updateConnection(String deviceId, bool isConnected, [String? error]) {
    onConnectionChange?.call(deviceId, isConnected, error);
    _connectionStreamController?.add((
      deviceId: deviceId,
      isConnected: isConnected,
      error: error,
    ));
  }

  void updateCharacteristicValue(
      String deviceId, String characteristicId, Uint8List value) {
    onValueChange?.call(
        deviceId, BleUuidParser.string(characteristicId), value);
  }

  void updateAvailability(AvailabilityState state) {
    onAvailabilityChange?.call(state);
  }

  void updatePairingState(String deviceId, bool isPaired) {
    if (_pairStateMap[deviceId] == isPaired) return;
    _pairStateMap[deviceId] = isPaired;
    onPairingStateChange?.call(deviceId, isPaired);
  }

  // Do not use these directly to push updates
  OnScanResult? onScanResult;
  OnConnectionChange? onConnectionChange;
  OnValueChange? onValueChange;
  OnAvailabilityChange? onAvailabilityChange;
  OnPairingStateChange? onPairingStateChange;

  /// Creates an auto disposable streamController
  void _setupConnectionStreamIfRequired() {
    if (_connectionStreamController != null) return;

    _connectionStreamController = StreamController.broadcast();

    // Auto dispose if no more subscribers
    _connectionStreamController?.onCancel = () {
      // logInfo('Disposing Connection Stream');
      _connectionStreamController?.close();
      _connectionStreamController = null;
    };
  }
}

// Callback types
typedef OnConnectionChange = void Function(
    String deviceId, bool isConnected, String? error);

typedef OnValueChange = void Function(
    String deviceId, String characteristicId, Uint8List value);

typedef OnScanResult = void Function(BleDevice scanResult);

typedef OnAvailabilityChange = void Function(AvailabilityState state);

typedef OnPairingStateChange = void Function(String deviceId, bool isPaired);

typedef OnQueueUpdate = void Function(String id, int remainingQueueItems);
