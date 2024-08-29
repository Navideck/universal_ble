import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

class BleDevice {
  String deviceId;
  String? name;
  int? rssi;
  bool? isPaired;
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
    required this.name,
    this.rssi,
    this.isPaired,
    this.services = const [],
    this.isSystemDevice,
    this.manufacturerDataList = const [],
  });

  @override
  String toString() {
    return 'BleDevice: '
        'deviceId: $deviceId, '
        'name: $name, '
        'rssi: $rssi, '
        'isPaired: $isPaired, '
        'services: $services, '
        'isSystemDevice: $isSystemDevice, '
        'manufacturerDataList: $manufacturerDataList';
  }
}

/// Represents the manufacturer data of a BLE device.
class ManufacturerData {
  final int companyId;
  final Uint8List data;

  ManufacturerData(this.companyId, this.data);
  String get companyIdRadix16 => "0x0${companyId.toRadixString(16)}";

  factory ManufacturerData.fromData(Uint8List data) {
    if (data.length < 2) {
      throw const FormatException("Invalid Manufacturer Data");
    }
    return ManufacturerData(
      (data[0] + (data[1] << 8)),
      data.sublist(2),
    );
  }

  Uint8List toUint8List() {
    final byteData = ByteData(2);
    byteData.setInt16(0, companyId, Endian.host);
    return Uint8List.fromList(
      byteData.buffer.asUint8List() + data.toList(),
    );
  }

  @override
  String toString() {
    return 'Manufacturer: $companyIdRadix16 - $data';
  }
}
