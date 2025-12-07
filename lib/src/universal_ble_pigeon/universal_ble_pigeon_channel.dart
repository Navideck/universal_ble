import 'package:flutter/foundation.dart';
import 'package:universal_ble/src/universal_ble_pigeon/universal_ble.g.dart';
import 'package:universal_ble/src/utils/universal_ble_filter_util.dart';
import 'package:universal_ble/universal_ble.dart';

class UniversalBlePigeonChannel extends UniversalBlePlatform {
  static UniversalBlePigeonChannel? _instance;
  static UniversalBlePigeonChannel get instance =>
      _instance ??= UniversalBlePigeonChannel._();
  late final UniversalBleFilterUtil _bleFilter = UniversalBleFilterUtil();

  UniversalBlePigeonChannel._() {
    _setupListeners();
  }

  final _channel = UniversalBlePlatformChannel();

  @override
  Future<AvailabilityState> getBluetoothAvailabilityState() async {
    int state = await _executeWithErrorHandling(
      () => _channel.getBluetoothAvailabilityState(),
    );
    return AvailabilityState.parse(state);
  }

  @override
  Future<bool> enableBluetooth() {
    if (!BleCapabilities.supportsBluetoothEnableApi) {
      throw UnsupportedError("Not supported");
    }
    return _executeWithErrorHandling(() => _channel.enableBluetooth());
  }

  @override
  Future<bool> disableBluetooth() {
    if (!BleCapabilities.supportsBluetoothEnableApi) {
      throw UnsupportedError("Not supported");
    }
    return _executeWithErrorHandling(() => _channel.disableBluetooth());
  }

  @override
  Future<void> startScan({
    ScanFilter? scanFilter,
    PlatformConfig? platformConfig,
  }) async {
    await _ensureInitialized(platformConfig);
    _bleFilter.scanFilter = scanFilter;
    await _executeWithErrorHandling(
      () => _channel.startScan(scanFilter.toUniversalScanFilter()),
    );
  }

  @override
  Future<void> stopScan() =>
      _executeWithErrorHandling(() => _channel.stopScan());

  @override
  Future<bool> isScanning() =>
      _executeWithErrorHandling(() => _channel.isScanning());

  @override
  Future<BleConnectionState> getConnectionState(String deviceId) async {
    int state = await _executeWithErrorHandling(
      () => _channel.getConnectionState(deviceId),
    );
    return BleConnectionState.parse(state);
  }

  @override
  Future<void> connect(String deviceId, {Duration? connectionTimeout}) =>
      _executeWithErrorHandling(() => _channel.connect(deviceId));

  @override
  Future<void> disconnect(String deviceId) =>
      _executeWithErrorHandling(() => _channel.disconnect(deviceId));

  @override
  Future<List<BleService>> discoverServices(String deviceId) async {
    List<UniversalBleService?> universalBleServices =
        await _executeWithErrorHandling(
          () => _channel.discoverServices(deviceId),
        );
    return List<BleService>.from(
      universalBleServices
          .where((e) => e != null)
          .map((e) => e!.toBleService(deviceId))
          .toList(),
    );
  }

  @override
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) {
    return _executeWithErrorHandling(
      () => _channel.setNotifiable(
        deviceId,
        service,
        characteristic,
        bleInputProperty.index,
      ),
    );
  }

  @override
  Future<Uint8List> readValue(
    String deviceId,
    String service,
    String characteristic, {
    final Duration? timeout,
  }) {
    return _executeWithErrorHandling(
      () => _channel.readValue(deviceId, service, characteristic),
    );
  }

  @override
  Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  ) {
    return _executeWithErrorHandling(
      () => _channel.writeValue(
        deviceId,
        service,
        characteristic,
        value,
        bleOutputProperty.index,
      ),
    );
  }

  @override
  Future<void> batchWrite(List<UniversalBleWriteCommand> commands) {
    return _executeWithErrorHandling(() => _channel.batchWrite(commands));
  }

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) =>
      _executeWithErrorHandling(
        () => _channel.requestMtu(deviceId, expectedMtu),
      );

  @override
  Future<bool> isPaired(String deviceId) =>
      _executeWithErrorHandling(() => _channel.isPaired(deviceId));

  @override
  Future<bool> pair(String deviceId) =>
      _executeWithErrorHandling(() => _channel.pair(deviceId));

  @override
  Future<void> unpair(String deviceId) =>
      _executeWithErrorHandling(() => _channel.unPair(deviceId));

  @override
  Future<void> requestPermissions({
    bool withAndroidFineLocation = false,
  }) async {
    await _executeWithErrorHandling(
      () => _channel.requestPermissions(withAndroidFineLocation),
    );
  }

  @override
  Future<List<BleDevice>> getSystemDevices(List<String>? withServices) async {
    var devices = await _executeWithErrorHandling(
      () => _channel.getSystemDevices(withServices ?? []),
    );
    return List<BleDevice>.from(
      devices.map((e) => e.toBleDevice(isSystemDevice: true)).toList(),
    );
  }

  /// To set listeners
  void _setupListeners() {
    UniversalBleCallbackChannel.setUp(
      _UniversalBleCallbackHandler(
        scanResult: (bleDevice) {
          // Only check for exclusion filter here,
          // scan filter handled natively on platform side
          if (_bleFilter.matchesExclusionFilter(bleDevice)) return;
          updateScanResult(bleDevice);
        },
        availabilityChange: updateAvailability,
        connectionChanged: updateConnection,
        valueChanged: updateCharacteristicValue,
        pairStateChange: updatePairingState,
      ),
    );
  }

  /// Executes a platform call with error handling
  /// Converts any errors to UniversalBleException
  Future<T> _executeWithErrorHandling<T>(Future<T> Function() future) async {
    try {
      return await future();
    } catch (error) {
      throw UniversalBleException.fromError(error);
    }
  }

  Future<void> _ensureInitialized(PlatformConfig? platformConfig) async {
    // Check bluetooth availability on Apple and Android
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      await requestPermissions(
        withAndroidFineLocation:
            platformConfig?.android?.requestLocationPermission ?? false,
      );
    }
  }
}

extension _BleServiceExtension on UniversalBleService {
  BleService toBleService(String deviceId) {
    List<BleCharacteristic> bleCharacteristics = [];
    for (UniversalBleCharacteristic? characteristic in characteristics ?? []) {
      if (characteristic == null) continue;
      List<int?>? properties = List<int?>.from(characteristic.properties);
      bleCharacteristics.add(
        BleCharacteristic.withMetaData(
          deviceId: deviceId,
          serviceId: uuid,
          uuid: characteristic.uuid,
          descriptors: List<BleDescriptor>.from(
            characteristic.descriptors.map((e) => BleDescriptor(e.uuid)),
          ),
          properties: List<CharacteristicProperty>.from(
            properties.map((e) => CharacteristicProperty.parse(e ?? 1)),
          ),
        ),
      );
    }
    return BleService(uuid, bleCharacteristics);
  }
}

class _UniversalBleCallbackHandler extends UniversalBleCallbackChannel {
  OnAvailabilityChange availabilityChange;
  OnScanResult scanResult;
  OnConnectionChange connectionChanged;
  OnValueChange valueChanged;
  OnPairingStateChange pairStateChange;

  _UniversalBleCallbackHandler({
    required this.availabilityChange,
    required this.scanResult,
    required this.connectionChanged,
    required this.valueChanged,
    required this.pairStateChange,
  });

  @override
  void onAvailabilityChanged(int state) =>
      availabilityChange(AvailabilityState.parse(state));

  @override
  void onConnectionChanged(String deviceId, bool connected, String? error) =>
      connectionChanged(deviceId, connected, error);

  @override
  void onScanResult(UniversalBleScanResult result) =>
      scanResult(result.toBleDevice());

  @override
  void onValueChanged(
    String deviceId,
    String characteristicId,
    Uint8List value,
  ) => valueChanged(deviceId, characteristicId, value);

  @override
  void onPairStateChange(String deviceId, bool isPaired, String? error) =>
      pairStateChange(deviceId, isPaired);
}

extension _UniversalBleScanResultExtension on UniversalBleScanResult {
  BleDevice toBleDevice({bool? isSystemDevice}) {
    return BleDevice(
      name: name,
      deviceId: deviceId,
      rssi: rssi,
      paired: isPaired,
      isSystemDevice: isSystemDevice,
      services: services?.map(BleUuidParser.string).toList() ?? [],
      manufacturerDataList:
          manufacturerDataList
              ?.map((e) => ManufacturerData(e.companyIdentifier, e.data))
              .toList() ??
          [],
    );
  }
}

extension _ScanFilterExtension on ScanFilter? {
  UniversalScanFilter? toUniversalScanFilter() {
    List<UniversalManufacturerDataFilter>? manufacturerDataFilters = this
        ?.withManufacturerData
        .map(
          (e) => UniversalManufacturerDataFilter(
            companyIdentifier: e.companyIdentifier,
            data: e.payloadPrefix,
            mask: e.payloadMask,
          ),
        )
        .toList();

    // Windows crashes if it's null, so we need to pass empty scan filter in this case
    return UniversalScanFilter(
      withServices: this?.withServices.toValidUUIDList() ?? [],
      withNamePrefix: this?.withNamePrefix ?? [],
      withManufacturerData: manufacturerDataFilters ?? [],
    );
  }
}
