import 'dart:typed_data';

class BleScanResult {
  String deviceId;
  String? name;
  bool? isPaired;
  Uint8List? manufacturerDataHead;
  Uint8List? manufacturerData;
  int? rssi;
  List<String> services;

  BleScanResult({
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
