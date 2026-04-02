import 'dart:typed_data';

class BleReadRequestResult {
  final Uint8List value;
  final int? offset;
  final int? status;

  const BleReadRequestResult({
    required this.value,
    this.offset,
    this.status,
  });
}

class BleWriteRequestResult {
  final Uint8List? value;
  final int? offset;
  final int? status;

  const BleWriteRequestResult({
    this.value,
    this.offset,
    this.status,
  });
}
