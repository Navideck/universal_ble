import 'dart:async';
import 'dart:typed_data';
import 'package:universal_ble/universal_ble.dart';

/// Extension methods for [BleDescriptor] to simplify common operations.
extension BleDescriptorExtension on BleDescriptor {
  /// Reads the value of a descriptor of this characteristic.
  Future<Uint8List> read({Duration? timeout, String? queueId}) =>
      UniversalBle.readDescriptor(
        _metaData.deviceId,
        _metaData.serviceId,
        _metaData.characteristicId,
        uuid,
        timeout: timeout,
        queueId: queueId,
      );

  /// Writes a value to a descriptor of this characteristic.
  Future<void> write(Uint8List value, {Duration? timeout, String? queueId}) =>
      UniversalBle.writeDescriptor(
        _metaData.deviceId,
        _metaData.serviceId,
        _metaData.characteristicId,
        uuid,
        value,
        timeout: timeout,
        queueId: queueId,
      );

  BleCharOperationMetadata get _metaData {
    BleCharOperationMetadata? metaData = this.metaData;
    if (metaData == null) throw "Characteristic metaData is not preset";
    return metaData;
  }
}
