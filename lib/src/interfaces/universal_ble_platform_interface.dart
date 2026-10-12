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
  // Last pairing/bond state seen per canonical device id (see updatePairingState). Bond state outlives a
  // connection, so unlike _lastConnectionParametersMap this is not cleared on disconnect.
  final Map<String, bool> _lastPairStateMap = {};
  final Map<String, BleConnectionParametersChange>
      _lastConnectionParametersMap = {};

  final _scanStreamController = UniversalBleStreamController<BleDevice>();

  final bleConnectionChangeStreamController =
      UniversalBleStreamController<BleConnectionChange>();

  final _valueStreamController =
      UniversalBleStreamController<BleCharacteristicValue>();

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

  Future<BleDevice> requestDevice({
    ScanFilter? scanFilter,
    PickerPlatformConfig? platformConfig,
  }) async {
    throw UniversalBleException(
      code: UniversalBleErrorCode.notSupported,
      message: 'requestDevice is not supported on this platform',
    );
  }

  Future<void> connect(
    String deviceId, {
    Duration? connectionTimeout,
    bool autoConnect = false,
    ConnectionPlatformConfig? platformConfig,
  });

  Future<void> disconnect(String deviceId);

  Future<List<BleService>> discoverServices(
    String deviceId,
    bool withDescriptors, {
    DiscoverServicesPlatformConfig? platformConfig,
  });

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

  Future<Uint8List> readDescriptorValue(
    String deviceId,
    String service,
    String characteristic,
    String descriptor, {
    Duration? timeout,
  });

  Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  );

  Future<void> writeDescriptorValue(
    String deviceId,
    String service,
    String characteristic,
    String descriptor,
    Uint8List value,
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
  Stream<bool> connectionStream(String deviceId) =>
      connectionChangeStream(deviceId).map((e) => e.isConnected);

  Stream<BleConnectionChange> connectionChangeStream(String deviceId) {
    final target = deviceId.toLowerCase();
    return bleConnectionChangeStreamController.stream.where(
      (e) => e.deviceId == deviceId || e.deviceId.toLowerCase() == target,
    );
  }

  Stream<Uint8List> characteristicValueStream(
    String deviceId,
    String characteristicId,
  ) {
    final target = deviceId.toLowerCase();
    characteristicId = BleUuidParser.string(characteristicId);
    return _valueStreamController.stream.where((e) {
      return (e.deviceId == deviceId || e.deviceId.toLowerCase() == target) &&
          e.characteristicId == characteristicId;
    }).map((e) => e.value);
  }

  Stream<bool> pairingStateStream(String deviceId) {
    final target = deviceId.toLowerCase();
    return _pairStateStreamController.stream
        .where(
            (e) => e.deviceId == deviceId || e.deviceId.toLowerCase() == target)
        .map((e) => e.isPaired);
  }

  /// Update Handlers
  void updateScanResult(BleDevice bleDevice) {
    _scanStreamController.add(bleDevice);

    try {
      onScanResultUpdate?.call(bleDevice);
    } catch (_) {}
  }

  void updateConnection(
    String deviceId,
    bool isConnected, [
    String? error,
    UniversalBleErrorCode? errorCode,
    int? nativeErrorCode,
  ]) {
    final update = BleConnectionChange(
      deviceId: deviceId,
      isConnected: isConnected,
      error: error,
      errorCode: errorCode,
      nativeErrorCode: nativeErrorCode,
    );
    bleConnectionChangeStreamController.add(update);

    try {
      onConnectionChange?.call(update);
    } catch (_) {}

    if (!isConnected) {
      // Clear per-device state by the canonical id so cleanup can't miss an entry stored under another case
      // (CacheHandler normalizes internally).
      CacheHandler.instance.resetDeviceCache(deviceId);
      // Connection parameters belong to this connection, so drop them. Pairing/bond state deliberately
      // outlives the connection (a bonded device stays bonded across reconnects) and is left in
      // _lastPairStateMap.
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
    // StandardMessageCodec decodes typed data as a view into the complete
    // platform-message buffer. Normalize that view before exposing it so
    // consumers which pass `value.buffer` to another binary API cannot
    // accidentally include Pigeon envelope bytes.
    final normalizedValue = value.offsetInBytes == 0 &&
            value.lengthInBytes == value.buffer.lengthInBytes
        ? value
        : Uint8List.fromList(value);
    final update = BleCharacteristicValue(
      deviceId: deviceId,
      characteristicId: characteristicId,
      value: normalizedValue,
      timestamp: timestamp,
    );
    _valueStreamController.add(update);
    try {
      onValueChange?.call(update);
    } catch (_) {}
  }

  void updateAvailability(AvailabilityState state) {
    _availabilityStreamController.add(state);

    try {
      onAvailabilityChange?.call(state);
    } catch (_) {}
  }

  void updatePairingState(String deviceId, bool isPaired) {
    if (_isDuplicateState(_lastPairStateMap, deviceId, isPaired)) return;
    _emitPairingState(deviceId, isPaired);
  }

  /// A failed bond is an event, not a state: it reports `isPaired: false` regardless of what was cached before,
  /// so it must not go through [updatePairingState]'s dedup — otherwise every failure after the first is
  /// swallowed (#325). The cached value is still refreshed so later genuine transitions dedup as usual.
  void updatePairingFailure(String deviceId) {
    _lastPairStateMap[deviceId.toLowerCase()] = false;
    _emitPairingState(deviceId, false);
  }

  void _emitPairingState(String deviceId, bool isPaired) {
    _pairStateStreamController.add((deviceId: deviceId, isPaired: isPaired));

    try {
      onPairingStateChange?.call(deviceId, isPaired);
    } catch (_) {}
  }

  void updateConnectionParameters(BleConnectionParametersChange update) {
    final isDuplicate = _isDuplicateState(
      _lastConnectionParametersMap,
      update.deviceId,
      update,
      equals: (previous, next) =>
          previous.interval == next.interval &&
          previous.latency == next.latency &&
          previous.supervisionTimeout == next.supervisionTimeout &&
          previous.status == next.status,
    );
    if (isDuplicate) return;

    try {
      onConnectionParametersChange?.call(update);
    } catch (_) {}
  }

  /// True when [value] equals the last value cached for [deviceId] (matched case-insensitively), in which case
  /// the cache is left untouched. Otherwise [value] is cached under the canonical id and this returns false.
  /// [equals] defaults to `==`; pass a comparator for payloads whose identity is field-based.
  bool _isDuplicateState<T>(
    Map<String, T> cache,
    String deviceId,
    T value, {
    bool Function(T previous, T next)? equals,
  }) {
    final key = deviceId.toLowerCase();
    final previous = cache[key];
    if (previous != null &&
        (equals == null ? previous == value : equals(previous, value))) {
      return true;
    }
    cache[key] = value;
    return false;
  }
}
