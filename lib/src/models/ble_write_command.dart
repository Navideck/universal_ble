import 'dart:typed_data';

/// A command for batch write operations.
/// Used with [UniversalBle.batchWrite] to write to multiple devices in parallel.
class BleWriteCommand {
  /// The device ID to write to.
  final String deviceId;

  /// The service UUID containing the characteristic.
  final String service;

  /// The characteristic UUID to write to.
  final String characteristic;

  /// The value to write.
  final Uint8List value;

  /// Whether to write without waiting for a response.
  /// Default is false (write with response).
  final bool withoutResponse;

  const BleWriteCommand({
    required this.deviceId,
    required this.service,
    required this.characteristic,
    required this.value,
    this.withoutResponse = false,
  });
}
