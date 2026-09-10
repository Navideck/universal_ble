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

  /// Canonical form of [deviceId] as emitted and matched by the Dart layer.
  ///
  /// On every native platform a device id is a case-insensitive address (a MAC on
  /// Android/Windows/Linux, a UUID on Apple) that platforms report in different cases — Android
  /// upper-cases MACs, Windows/WinRT lower-cases them (`mac_address_to_str` emits lower-case hex).
  /// So the default canonical form is LOWER-CASE: the update* handlers below canonicalise on
  /// ingestion, making every stream event, callback and per-device map key lower-case, and the
  /// stream filters canonicalise the query so consumers may still pass an id in any case. Native
  /// BLE calls want the upper-case form (Android's getRemoteDevice REQUIRES it), so the platform
  /// implementations convert back at their boundary (see `nativeDeviceId`).
  ///
  /// Platforms whose ids are NOT case-insensitive addresses override this. Web Bluetooth ids are
  /// opaque, case-sensitive browser tokens (Chromium emits Base64 of a random value), so
  /// `UniversalBleWeb` returns them unchanged — case-folding one would both corrupt the id the
  /// caller sees and break the device lookup it is passed back to.
  ///
  /// Emission and matching both go through this method, so any override stays self-consistent.
  String canonicalDeviceId(String deviceId) => deviceId.toLowerCase();

  Stream<bool> connectionStream(String deviceId) {
    final target = canonicalDeviceId(deviceId);
    return bleConnectionUpdateStreamController.stream
        .where((e) => e.deviceId == target)
        .map((e) => e.isConnected);
  }

  Stream<Uint8List> characteristicValueStream(
    String deviceId,
    String characteristicId,
  ) {
    final target = canonicalDeviceId(deviceId);
    characteristicId = BleUuidParser.string(characteristicId);
    return _valueStreamController.stream
        .where((e) => e.deviceId == target && e.characteristicId == characteristicId)
        .map((e) => e.value);
  }

  Stream<bool> pairingStateStream(String deviceId) {
    final target = canonicalDeviceId(deviceId);
    return _pairStateStreamController.stream
        .where((e) => e.deviceId == target)
        .map((e) => e.isPaired);
  }

  /// Update Handlers
  void updateScanResult(BleDevice bleDevice) {
    bleDevice.deviceId = canonicalDeviceId(bleDevice.deviceId);
    _scanStreamController.add(bleDevice);

    try {
      onScanResultUpdate?.call(bleDevice);
    } catch (_) {}
  }

  void updateConnection(String deviceId, bool isConnected, [String? error]) {
    deviceId = canonicalDeviceId(deviceId);
    bleConnectionUpdateStreamController.add((
      deviceId: deviceId,
      isConnected: isConnected,
      error: error,
    ));

    try {
      onConnectionChange?.call(deviceId, isConnected, error);
    } catch (_) {}

    if (!isConnected) {
      // Clear per-device state (all keyed by the canonical id).
      CacheHandler.instance.resetDeviceCache(deviceId);
      _lastConnectionParametersMap.remove(deviceId);
    }
  }

  void updateCharacteristicValue(
    String deviceId,
    String characteristicId,
    Uint8List value,
    int? timestamp,
  ) {
    deviceId = canonicalDeviceId(deviceId);
    characteristicId = BleUuidParser.string(characteristicId);
    // StandardMessageCodec decodes typed data as a view into the complete
    // platform-message buffer. Normalize that view before exposing it so
    // consumers which pass `value.buffer` to another binary API cannot
    // accidentally include Pigeon envelope bytes.
    final normalizedValue =
        value.offsetInBytes == 0 &&
            value.lengthInBytes == value.buffer.lengthInBytes
        ? value
        : Uint8List.fromList(value);
    _valueStreamController.add((
      deviceId: deviceId,
      characteristicId: characteristicId,
      value: normalizedValue,
    ));
    try {
      onValueChange?.call(
        deviceId,
        characteristicId,
        normalizedValue,
        timestamp,
      );
    } catch (_) {}
  }

  void updateAvailability(AvailabilityState state) {
    _availabilityStreamController.add(state);

    try {
      onAvailabilityChange?.call(state);
    } catch (_) {}
  }

  void updatePairingState(String deviceId, bool isPaired) {
    deviceId = canonicalDeviceId(deviceId);
    if (_pairStateMap[deviceId] == isPaired) return;
    _pairStateMap[deviceId] = isPaired;

    _pairStateStreamController.add((deviceId: deviceId, isPaired: isPaired));

    try {
      onPairingStateChange?.call(deviceId, isPaired);
    } catch (_) {}
  }

  void updateConnectionParameters(BleConnectionParametersUpdated update) {
    update.deviceId = canonicalDeviceId(update.deviceId);
    final last = _lastConnectionParametersMap[update.deviceId];
    if (last != null &&
        last.interval == update.interval &&
        last.latency == update.latency &&
        last.supervisionTimeout == update.supervisionTimeout &&
        last.status == update.status) {
      return;
    }
    _lastConnectionParametersMap[update.deviceId] = update;

    try {
      onConnectionParametersChange?.call(update);
    } catch (_) {}
  }
}
