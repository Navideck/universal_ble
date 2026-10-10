import 'dart:typed_data';

/// A characteristic value update, delivered by notifications, indications or
/// reads that report their value through the value callback.
class BleCharacteristicValue {
  /// Device id as reported by the platform.
  final String deviceId;

  /// Characteristic id, normalized (short UUIDs expanded to their 128-bit form).
  final String characteristicId;

  /// The characteristic value.
  final Uint8List value;

  /// Platform timestamp of the update in milliseconds since the Unix epoch,
  /// where the platform provides one. `null` where it does not.
  final int? timestamp;

  const BleCharacteristicValue({
    required this.deviceId,
    required this.characteristicId,
    required this.value,
    this.timestamp,
  });

  @override
  String toString() => 'BleCharacteristicValue(deviceId: $deviceId, '
      'characteristicId: $characteristicId, value: $value, '
      'timestamp: $timestamp)';
}
