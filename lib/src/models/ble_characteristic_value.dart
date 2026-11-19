import 'dart:typed_data';

/// A characteristic value update, delivered by notifications, indications or
/// reads that report their value through the value callback.
class BleCharacteristicValue {
  /// Device id as reported by the platform.
  final String deviceId;

  /// Characteristic id, normalized (short UUIDs expanded to their 128-bit form).
  final String characteristicId;

  /// Service id, normalized (short UUIDs expanded to their 128-bit form), of
  /// the service that owns the characteristic.
  ///
  /// A GATT database may hold several characteristics with the same
  /// [characteristicId] in different services, so this identifies which one
  /// produced the value. It is `null` on a platform that cannot report the
  /// owning service.
  final String? serviceId;

  /// The characteristic value.
  final Uint8List value;

  /// Platform timestamp of the update in milliseconds since the Unix epoch,
  /// where the platform provides one. `null` where it does not.
  final int? timestamp;

  const BleCharacteristicValue({
    required this.deviceId,
    required this.characteristicId,
    this.serviceId,
    required this.value,
    this.timestamp,
  });

  @override
  String toString() => 'BleCharacteristicValue(deviceId: $deviceId, '
      'serviceId: $serviceId, characteristicId: $characteristicId, '
      'value: $value, timestamp: $timestamp)';
}
