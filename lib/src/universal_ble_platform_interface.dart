import 'dart:async';
import 'dart:typed_data';
import 'package:universal_ble/src/universal_ble_stream_controller.dart';
import 'package:universal_ble/universal_ble.dart';

abstract class UniversalBlePlatform {
  // Do not use these directly to push updates
  OnScanResult? onScanResult;
  OnConnectionChange? onConnectionChange;
  OnValueChange? onValueChange;
  OnAvailabilityChange? onAvailabilityChange;
  OnPairingStateChange? onPairingStateChange;
  final Map<String, bool> _pairStateMap = {};

  final _scanStreamController = UniversalBleStreamController<BleDevice>();

  final bleConnectionUpdateStreamController = UniversalBleStreamController<
      ({String deviceId, bool isConnected, String? error})>();

  final _valueStreamController = UniversalBleStreamController<
      ({String deviceId, String characteristicId, Uint8List value})>();

  final _pairStateStreamController =
      UniversalBleStreamController<({String deviceId, bool isPaired})>();

  /// Send latest availability state on subscribing
  late final _availabilityStreamController =
      UniversalBleStreamController<AvailabilityState>(
    initialEvent: getBluetoothAvailabilityState,
  );

  Future<AvailabilityState> getBluetoothAvailabilityState();

  Future<bool> enableBluetooth();

  Future<bool> disableBluetooth();

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

  /// Streams
  Stream<BleDevice> get scanStream => _scanStreamController.stream;

  Stream<AvailabilityState> get availabilityStream =>
      _availabilityStreamController.stream;

  Stream<bool> connectionStream(String deviceId) =>
      bleConnectionUpdateStreamController.stream
          .where((e) => e.deviceId == deviceId)
          .map((e) => e.isConnected);

  Stream<Uint8List> characteristicValueStream(
          String deviceId, String characteristicId) =>
      _valueStreamController.stream.where((e) {
        return e.deviceId == deviceId && e.characteristicId == characteristicId;
      }).map((e) => e.value);

  Stream<bool> pairingStateStream(String deviceId) =>
      _pairStateStreamController.stream
          .where((e) => e.deviceId == deviceId)
          .map((e) => e.isPaired);

  /// Update Handlers
  void updateScanResult(BleDevice bleDevice) {
    _scanStreamController.add(bleDevice);

    try {
      onScanResult?.call(bleDevice);
    } catch (_) {}
  }

  void updateConnection(String deviceId, bool isConnected, [String? error]) {
    bleConnectionUpdateStreamController.add((
      deviceId: deviceId,
      isConnected: isConnected,
      error: error,
    ));

    try {
      onConnectionChange?.call(deviceId, isConnected, error);
    } catch (_) {}
  }

  void updateCharacteristicValue(
    String deviceId,
    String characteristicId,
    Uint8List value,
  ) {
    _valueStreamController.add((
      deviceId: deviceId,
      characteristicId: characteristicId,
      value: value,
    ));

    try {
      onValueChange?.call(
          deviceId, BleUuidParser.string(characteristicId), value);
    } catch (_) {}
  }

  void updateAvailability(AvailabilityState state) {
    _availabilityStreamController.add(state);

    try {
      onAvailabilityChange?.call(state);
    } catch (_) {}
  }

  void updatePairingState(String deviceId, bool isPaired) {
    if (_pairStateMap[deviceId] == isPaired) return;
    _pairStateMap[deviceId] = isPaired;

    _pairStateStreamController.add((deviceId: deviceId, isPaired: isPaired));

    try {
      onPairingStateChange?.call(deviceId, isPaired);
    } catch (_) {}
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
