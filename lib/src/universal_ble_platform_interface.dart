import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';
import 'package:universal_ble/universal_ble.dart';

abstract class UniversalBlePlatform {
  StreamController<BleDevice>? _scanStreamController;
  StreamController<({String deviceId, bool isConnected})>?
      _connectionStreamController;
  StreamController<
          ({String deviceId, String characteristicId, Uint8List value})>?
      _characteristicStreamController;

  final Map<String, bool> _pairStateMap = {};

  OnScanResult? onScanResult;
  OnConnectionChange? onConnectionChange;
  OnValueChange? onValueChange;
  OnAvailabilityChange? onAvailabilityChange;
  OnPairingStateChange? onPairingStateChange;

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

  Future<List<BleDevice>> getSystemDevices(List<String>? withServices);

  bool receivesAdvertisements(String deviceId) => true;

  Stream<BleDevice> scanStream() => _getScanStreamController().stream;

  Stream<bool> connectionStream(String deviceId) =>
      _getConnectionStreamController()
          .stream
          .where((event) => event.deviceId == deviceId)
          .map((event) => event.isConnected);

  Stream<Uint8List> characteristicStream(
          String deviceId, String characteristicId) =>
      _getCharacteristicStreamController()
          .stream
          .where((event) =>
              event.deviceId == deviceId &&
              event.characteristicId == characteristicId)
          .map((event) => event.value);

  void updateScanResult(BleDevice bleDevice) {
    onScanResult?.call(bleDevice);
    _scanStreamController?.add(bleDevice);
  }

  void updateConnection(String deviceId, bool isConnected) {
    onConnectionChange?.call(deviceId, isConnected);
    _connectionStreamController?.add((
      deviceId: deviceId,
      isConnected: isConnected,
    ));
  }

  void updateCharacteristicValue(
      String deviceId, String characteristicId, Uint8List value) {
    onValueChange?.call(
        deviceId, BleUuidParser.string(characteristicId), value);
    _characteristicStreamController?.add((
      deviceId: deviceId,
      characteristicId: BleUuidParser.string(characteristicId),
      value: value,
    ));
  }

  void updateAvailability(AvailabilityState state) {
    onAvailabilityChange?.call(state);
  }

  void updatePairingState(String deviceId, bool isPaired) {
    if (_pairStateMap[deviceId] == isPaired) return;
    _pairStateMap[deviceId] = isPaired;
    onPairingStateChange?.call(deviceId, isPaired);
  }

  /// Setup autoDisposable StreamControllers
  StreamController<({String deviceId, bool isConnected})>
      _getConnectionStreamController() {
    if (_connectionStreamController != null) {
      _connectionStreamController =
          StreamController<({String deviceId, bool isConnected})>.broadcast();
      _connectionStreamController?.onCancel = () {
        _connectionStreamController?.close();
        _connectionStreamController = null;
      };
    }
    return _connectionStreamController!;
  }

  StreamController<
          ({String deviceId, String characteristicId, Uint8List value})>
      _getCharacteristicStreamController() {
    if (_characteristicStreamController == null) {
      _characteristicStreamController = StreamController<
          ({
            String deviceId,
            String characteristicId,
            Uint8List value
          })>.broadcast();
      _characteristicStreamController?.onCancel = () {
        _characteristicStreamController?.close();
        _characteristicStreamController = null;
      };
    }
    return _characteristicStreamController!;
  }

  StreamController<BleDevice> _getScanStreamController() {
    if (_scanStreamController == null) {
      _scanStreamController = StreamController<BleDevice>.broadcast();
      _scanStreamController?.onCancel = () {
        _scanStreamController?.close();
        _scanStreamController = null;
      };
    }
    return _scanStreamController!;
  }

  static void logInfo(String message, {bool isError = false}) {
    if (isError) message = '\x1B[31m$message\x1B[31m';
    log(message, name: 'UniversalBle');
  }
}

// Callback types
typedef OnConnectionChange = void Function(String deviceId, bool isConnected);

typedef OnValueChange = void Function(
    String deviceId, String characteristicId, Uint8List value);

typedef OnScanResult = void Function(BleDevice scanResult);

typedef OnAvailabilityChange = void Function(AvailabilityState state);

typedef OnPairingStateChange = void Function(String deviceId, bool isPaired);

typedef OnQueueUpdate = void Function(String id, int remainingQueueItems);
