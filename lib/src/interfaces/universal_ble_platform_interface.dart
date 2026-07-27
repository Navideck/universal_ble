import 'dart:async';
import 'dart:typed_data';
import 'package:universal_ble/src/utils/cache_handler.dart';
import 'package:universal_ble/src/utils/universal_ble_stream_controller.dart';
import 'package:universal_ble/src/utils/universal_logger.dart';
import 'package:universal_ble/universal_ble.dart';

abstract class UniversalBlePlatform {
  // Do not use these directly to push updates
  OnScanResult? onScanResultUpdate;
  OnConnectionChange? onConnectionChange;
  OnValueChange? onValueChange;
  OnAvailabilityChange? onAvailabilityChange;
  OnPairingStateChange? onPairingStateChange;
  OnConnectionParametersChange? onConnectionParametersChange;
  final Map<String, bool> _pairStateMap = {};
  final Map<String, BleConnectionParametersUpdated>
  _lastConnectionParametersMap = {};

  final _scanStreamController = UniversalBleStreamController<BleDevice>();

  final bleConnectionUpdateStreamController =
      UniversalBleStreamController<
        ({String deviceId, bool isConnected, String? error})
      >();

  final _valueStreamController =
      UniversalBleStreamController<
        ({String deviceId, String characteristicId, Uint8List value})
      >();

  final _pairStateStreamController =
      UniversalBleStreamController<({String deviceId, bool isPaired})>();

  /// Send latest availability state upon subscribing
  late final _availabilityStreamController =
      UniversalBleStreamController<AvailabilityState>(
        initialEvent: getBluetoothAvailabilityState,
      );

  Future<AvailabilityState> getBluetoothAvailabilityState();

  Future<bool> enableBluetooth();

  Future<bool> disableBluetooth();

  Future<bool> hasPermissions({bool withAndroidFineLocation = false}) async {
    return true;
  }

  Future<void> requestPermissions({
    bool withAndroidFineLocation = false,
  }) async {}

  Future<void> startScan({
    ScanFilter? scanFilter,
    PlatformConfig? platformConfig,
  });

  Future<void> stopScan();

  Future<bool> isScanning();

  Future<void> connect(
    String deviceId, {
    Duration? connectionTimeout,
    bool autoConnect = false,
    ConnectionPlatformConfig? platformConfig,
  });

  Future<void> disconnect(String deviceId);

  Future<List<BleService>> discoverServices(
    String deviceId,
    bool withDescriptors,
  );

  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  );

  Future<Uint8List> readValue(
    String deviceId,
    String service,
    String characteristic, {
    Duration? timeout,
  });

  Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  );

  Future<int> requestMtu(String deviceId, int expectedMtu);

  Future<int> readRssi(String deviceId);

  Future<void> requestConnectionPriority(
    String deviceId,
    BleConnectionPriority priority,
  );

  Future<bool> isPaired(String deviceId);

  Future<bool> pair(String deviceId);

  Future<void> unpair(String deviceId);

  Future<BleConnectionState> getConnectionState(String deviceId);

  Future<List<BleDevice>> getSystemDevices(List<String>? withServices);

  Future<void> setLogLevel(BleLogLevel logLevel) async =>
      UniversalLogger.setLogLevel(logLevel);

  bool receivesAdvertisements(String deviceId) => true;

  /// Streams
  Stream<BleDevice> get scanStream => _scanStreamController.stream;

  Stream<AvailabilityState> get availabilityStream =>
      _availabilityStreamController.stream;

  // A BLE device id is a case-insensitive identifier (a MAC on Android/Windows/Linux, a UUID on Apple), but
  // platforms report it in different cases — Android upper-cases MACs, Windows/WinRT lower-cases them
  // (`mac_address_to_str` emits lower-case hex). So we (a) match the event streams case-insensitively, and
  // (b) key all per-device state by a canonical lower-case id (see updatePairingState /
  // updateConnectionParameters / CacheHandler) so a device reported in two cases can't split across map
  // entries. Emitted device ids are left AS the platform reports them, so this is non-breaking for consumers.
  // Hot paths short-circuit on an exact match before lower-casing.
  Stream<bool> connectionStream(String deviceId) {
    final target = deviceId.toLowerCase();
    return bleConnectionUpdateStreamController.stream
        .where((e) => e.deviceId == deviceId || e.deviceId.toLowerCase() == target)
        .map((e) => e.isConnected);
  }

  Stream<Uint8List> characteristicValueStream(
    String deviceId,
    String characteristicId,
  ) {
    final target = deviceId.toLowerCase();
    characteristicId = BleUuidParser.string(characteristicId);
    return _valueStreamController.stream
        .where((e) {
          return (e.deviceId == deviceId || e.deviceId.toLowerCase() == target) &&
              e.characteristicId == characteristicId;
        })
        .map((e) => e.value);
  }

  Stream<bool> pairingStateStream(String deviceId) {
    final target = deviceId.toLowerCase();
    return _pairStateStreamController.stream
        .where((e) => e.deviceId == deviceId || e.deviceId.toLowerCase() == target)
        .map((e) => e.isPaired);
  }

  /// Update Handlers
  void updateScanResult(BleDevice bleDevice) {
    _scanStreamController.add(bleDevice);

    try {
      onScanResultUpdate?.call(bleDevice);
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

    if (!isConnected) {
      // Clear per-device state by the canonical id so cleanup can't miss an entry stored under another case
      // (CacheHandler normalizes internally).
      CacheHandler.instance.resetDeviceCache(deviceId);
      _lastConnectionParametersMap.remove(deviceId.toLowerCase());
    }
  }

  void updateCharacteristicValue(
    String deviceId,
    String characteristicId,
    Uint8List value,
    int? timestamp,
  ) {
    characteristicId = BleUuidParser.string(characteristicId);
    _valueStreamController.add((
      deviceId: deviceId,
      characteristicId: characteristicId,
      value: value,
    ));
    try {
      onValueChange?.call(deviceId, characteristicId, value, timestamp);
    } catch (_) {}
  }

  void updateAvailability(AvailabilityState state) {
    _availabilityStreamController.add(state);

    try {
      onAvailabilityChange?.call(state);
    } catch (_) {}
  }

  void updatePairingState(String deviceId, bool isPaired) {
    // Key by the canonical id so the same device reported in another case doesn't create a second entry and
    // slip past this dedup. The emitted deviceId keeps the platform's case.
    final key = deviceId.toLowerCase();
    if (_pairStateMap[key] == isPaired) return;
    _pairStateMap[key] = isPaired;

    _pairStateStreamController.add((deviceId: deviceId, isPaired: isPaired));

    try {
      onPairingStateChange?.call(deviceId, isPaired);
    } catch (_) {}
  }

  void updateConnectionParameters(BleConnectionParametersUpdated update) {
    // Key by the canonical id (dropping the now-redundant last.deviceId == update.deviceId check, which would
    // itself have failed across cases and broken dedup for a device reported in two cases).
    final key = update.deviceId.toLowerCase();
    final last = _lastConnectionParametersMap[key];
    if (last != null &&
        last.interval == update.interval &&
        last.latency == update.latency &&
        last.supervisionTimeout == update.supervisionTimeout &&
        last.status == update.status) {
      return;
    }
    _lastConnectionParametersMap[key] = update;

    try {
      onConnectionParametersChange?.call(update);
    } catch (_) {}
  }
}
