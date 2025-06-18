import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

class BleDevice {
  String deviceId;
  String? name;
  String? rawName;
  int? rssi;
  bool? paired;

  /// List of services advertised by the device.
  List<String> services;
  bool? isSystemDevice;
  List<ManufacturerData> manufacturerDataList;

  @Deprecated("Use `manufacturerDataList` instead")
  Uint8List? get manufacturerData => manufacturerDataList.isEmpty
      ? null
      : manufacturerDataList.first.toUint8List();

  /// Returns connection state of the device.
  /// All platforms will return `Connected/Disconnected` states.
  /// `Android` and `Apple` can also return `Connecting/Disconnecting` states.
  Future<BleConnectionState> get connectionState =>
      UniversalBle.getConnectionState(deviceId);

  /// On web, it returns true if the web browser supports receiving advertisements from this device.
  /// The rest of the platforms will always return true.
  bool get receivesAdvertisements =>
      UniversalBle.receivesAdvertisements(deviceId);

  BleDevice({
    required this.deviceId,
    required String? name,
    this.rssi,
    this.paired,
    this.services = const [],
    this.isSystemDevice,
    this.manufacturerDataList = const [],
  }) {
    rawName = name;
    this.name = name?.replaceAll(RegExp(r'[^ -~]'), '').trim();
  }

  @override
  String toString() {
    return 'BleDevice: '
        'deviceId: $deviceId, '
        'name: $name, '
        'rssi: $rssi, '
        'paired: $paired, '
        'services: $services, '
        'isSystemDevice: $isSystemDevice, '
        'manufacturerDataList: $manufacturerDataList';
  }
}
