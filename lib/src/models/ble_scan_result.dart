import 'dart:typed_data';

class BleDevice {
  String deviceId;
  String? name;
  bool? isPaired;
  Uint8List? manufacturerDataHead;
  Uint8List? manufacturerData;
  int? rssi;
  List<String> services;

  BleDevice({
    required this.name,
    required this.deviceId,
    this.rssi,
    this.isPaired,
    Uint8List? manufacturerData,
    Uint8List? manufacturerDataHead,
    this.services = const [],
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
