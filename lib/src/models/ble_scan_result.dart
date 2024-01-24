import 'dart:typed_data';

class BleScanResult {
  String deviceId;
  String? name;
  bool? isPaired;
  Uint8List? manufacturerDataHead;
  Uint8List? manufacturerData;
  int? rssi;

  BleScanResult({
    required this.name,
    required this.deviceId,
    this.rssi,
    this.isPaired,
    Uint8List? manufacturerData,
    Uint8List? manufacturerDataHead,
  }) {
    this.manufacturerDataHead = manufacturerDataHead ?? Uint8List.fromList([]);
    this.manufacturerData = manufacturerData ?? manufacturerDataHead;
  }
}
