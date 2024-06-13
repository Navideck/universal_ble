import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

class BleDevice {
  String deviceId;
  String? name;
  int? rssi;
  bool? isPaired;
  List<String> services;
  bool? isSystemDevice;
  Uint8List? manufacturerDataHead;
  Uint8List? manufacturerData;

  Future<bool> get isConnected => UniversalBle.isConnected(deviceId);

  BleDevice({
    required this.deviceId,
    required this.name,
    this.rssi,
    this.isPaired,
    this.services = const [],
    this.isSystemDevice,
    Uint8List? manufacturerData,
    Uint8List? manufacturerDataHead,
  }) {
    this.manufacturerDataHead = manufacturerDataHead ?? Uint8List.fromList([]);
    this.manufacturerData = manufacturerData ?? manufacturerDataHead;
  }
}

/// Represents the manufacturer data of a BLE device.
/// Use [BleDevice.manufacturerData] with [ManufacturerData.fromData] to create an instance of this class.
class ManufacturerData {
  final int? companyId;
  final Uint8List? data;
  String? companyIdRadix16;
  ManufacturerData(this.companyId, this.data) {
    if (companyId != null) {
      companyIdRadix16 = "0x0${companyId!.toRadixString(16)}";
    }
  }

  factory ManufacturerData.fromData(Uint8List data) {
    if (data.length < 2) return ManufacturerData(null, data);
    int manufacturerIdInt = (data[0] + (data[1] << 8));
    return ManufacturerData(
      manufacturerIdInt,
      data.sublist(2),
    );
  }

  @override
  String toString() {
    return 'ManufacturerData: companyId: $companyIdRadix16, data: $data';
  }
}
