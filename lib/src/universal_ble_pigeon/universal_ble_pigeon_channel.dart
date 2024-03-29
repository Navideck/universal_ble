import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/src/universal_ble_pigeon/universal_ble.g.dart';
import 'package:universal_ble/universal_ble.dart';

class UniversalBlePigeonChannel extends UniversalBlePlatform {
  static UniversalBlePigeonChannel? _instance;
  static UniversalBlePigeonChannel get instance =>
      _instance ??= UniversalBlePigeonChannel._();

  UniversalBlePigeonChannel._() {
    _setupListeners();
  }

  final _channel = UniversalBlePlatformChannel();

  @override
  Future<AvailabilityState> getBluetoothAvailabilityState() async {
    int state = await _channel.getBluetoothAvailabilityState();
    return AvailabilityState.parse(state);
  }

  @override
  Future<bool> enableBluetooth() {
    if (Platform.isIOS || Platform.isMacOS) throw UnimplementedError();
    return _channel.enableBluetooth();
  }

  @override
  Future<void> startScan({
    ScanFilter? scanFilter,
  }) async {
    await _channel.startScan(
      scanFilter.toUniversalScanFilter(),
    );
  }

  @override
  Future<void> stopScan() => _channel.stopScan();

  @override
  Future<void> connect(String deviceId, {Duration? connectionTimeout}) =>
      _channel.connect(deviceId);

  @override
  Future<void> disconnect(String deviceId) => _channel.disconnect(deviceId);

  @override
  Future<List<BleService>> discoverServices(String deviceId) async {
    List<UniversalBleService?> universalBleServices =
        await _channel.discoverServices(deviceId);
    return List<BleService>.from(universalBleServices
        .where((e) => e != null)
        .map((e) => e!.toBleService())
        .toList());
  }

  @override
  Future<void> setNotifiable(String deviceId, String service,
      String characteristic, BleInputProperty bleInputProperty) {
    return _channel.setNotifiable(
      deviceId,
      service,
      characteristic,
      bleInputProperty.value,
    );
  }

  @override
  Future<Uint8List> readValue(
      String deviceId, String service, String characteristic) {
    return _channel.readValue(deviceId, service, characteristic);
  }

  @override
  Future<void> writeValue(
      String deviceId,
      String service,
      String characteristic,
      Uint8List value,
      BleOutputProperty bleOutputProperty) {
    return _channel.writeValue(
      deviceId,
      service,
      characteristic,
      value,
      bleOutputProperty.value,
    );
  }

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) =>
      _channel.requestMtu(deviceId, expectedMtu);

  @override
  Future<bool> isPaired(String deviceId) => _channel.isPaired(deviceId);

  @override
  Future<void> pair(String deviceId) => _channel.pair(deviceId);

  @override
  Future<void> unPair(String deviceId) => _channel.unPair(deviceId);

  @override
  Future<List<BleScanResult>> getConnectedDevices(
    List<String>? withServices,
  ) async {
    var devices = await _channel.getConnectedDevices(withServices ?? []);
    return List<BleScanResult>.from(devices
        .map((e) => e?.toBleScanResult())
        .where((e) => e != null)
        .toList());
  }

  /// To set listeners
  void _setupListeners() {
    UniversalBleCallbackChannel.setup(_UniversalBleCallbackHandler(
      scanResult: (BleScanResult scanResult) => onScanResult?.call(scanResult),
      availabilityChange: (AvailabilityState state) =>
          onAvailabilityChange?.call(state),
      connectionChanged: (String deviceId, BleConnectionState state) =>
          onConnectionChanged?.call(deviceId, state),
      valueChanged:
          (String deviceId, String characteristicId, Uint8List value) =>
              onValueChanged?.call(deviceId, characteristicId, value),
      pairStateChange: (String deviceId, bool isPaired, String? error) =>
          onPairingStateChange?.call(deviceId, isPaired, error),
    ));
  }
}

extension _BleServiceExtension on UniversalBleService {
  BleService toBleService() {
    List<BleCharacteristic> bleCharacteristics = [];
    for (UniversalBleCharacteristic? characteristic in characteristics ?? []) {
      if (characteristic == null) continue;
      List<int?>? properties = List<int?>.from(characteristic.properties);
      bleCharacteristics.add(BleCharacteristic(
        characteristic.uuid,
        List<CharacteristicProperty>.from(
          properties.map((e) => CharacteristicProperty.parse(e ?? 1)),
        ),
      ));
    }
    return BleService(uuid, bleCharacteristics);
  }
}

class _UniversalBleCallbackHandler extends UniversalBleCallbackChannel {
  OnAvailabilityChange availabilityChange;
  OnScanResult scanResult;
  OnConnectionChanged connectionChanged;
  OnValueChanged valueChanged;
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
  void onConnectionChanged(String deviceId, int state) =>
      connectionChanged(deviceId, BleConnectionState.parse(state));

  @override
  void onScanResult(UniversalBleScanResult result) =>
      scanResult(result.toBleScanResult());

  @override
  void onValueChanged(
          String deviceId, String characteristicId, Uint8List value) =>
      valueChanged(deviceId, characteristicId, value);

  @override
  void onPairStateChange(String deviceId, bool isPaired, String? error) =>
      pairStateChange(deviceId, isPaired, error);
}

extension _UniversalBleScanResultExtension on UniversalBleScanResult {
  BleScanResult toBleScanResult() {
    var mnfDataHead = manufacturerDataHead ?? Uint8List.fromList([]);
    var mnfData = manufacturerData ?? mnfDataHead;
    return BleScanResult(
      name: name,
      deviceId: deviceId,
      isPaired: isPaired,
      manufacturerData: mnfData,
      manufacturerDataHead: mnfDataHead,
      rssi: rssi,
      services: services
              ?.where((e) => e != null)
              .map((e) => UUID(e!).toString())
              .toList() ??
          [],
    );
  }
}

extension _ScanFilterExtension on ScanFilter? {
  UniversalScanFilter? toUniversalScanFilter() {
    List<UniversalManufacturerDataFilter>? manufacturerDataFilters = this
        ?.withManufacturerData
        .map((e) => UniversalManufacturerDataFilter(
              companyIdentifier: e.companyIdentifier,
              data: e.data,
              mask: e.mask,
            ))
        .toList();

    // Windows crashes if it's null, so we need to pass empty scan filter in this case
    return UniversalScanFilter(
      withServices: this?.withServices.toValidUUIDList() ?? [],
      withManufacturerData: manufacturerDataFilters ?? [],
    );
  }
}
