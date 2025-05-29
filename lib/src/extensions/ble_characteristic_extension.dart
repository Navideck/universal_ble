import 'dart:typed_data';
import 'package:universal_ble/universal_ble.dart';

/// Extension methods for [BleCharacteristic] to simplify common operations.
extension BleCharacteristicExtension on BleCharacteristic {
  /// A stream of [Uint8List] that emits values received from the characteristic.
  Stream<Uint8List> get onValueReceived =>
      UniversalBle.characteristicValueStream(_deviceId, uuid);

  /// Disables notifications for this characteristic.
  Future<void> disableNotify() => UniversalBle.setNotifiable(
        _deviceId,
        _serviceId,
        uuid,
        BleInputProperty.disabled,
      );

  /// Enables notifications for this characteristic.
  ///
  /// Throws an exception if the characteristic does not support notifications.
  Future<void> setNotify() {
    if (!properties.contains(CharacteristicProperty.notify)) {
      throw Exception(
        'Notification is not supported for this characteristic',
      );
    }
    return UniversalBle.setNotifiable(
      _deviceId,
      _serviceId,
      uuid,
      BleInputProperty.notification,
    );
  }

  /// Enables indications for this characteristic.
  ///
  /// Throws an exception if the characteristic does not support indications.
  Future<void> setIndication() {
    if (!properties.contains(CharacteristicProperty.indicate)) {
      throw Exception(
        'Indication is not supported for this characteristic',
      );
    }
    return UniversalBle.setNotifiable(
      _deviceId,
      _serviceId,
      uuid,
      BleInputProperty.indication,
    );
  }

  /// Reads the current value of the characteristic.
  Future<Uint8List> read() => UniversalBle.readValue(
        _deviceId,
        _serviceId,
        uuid,
      );

  /// Writes a value to the characteristic.
  ///
  /// [value] is the list of bytes to write.
  /// [withoutResponse] indicates whether the write should be performed without a response from the peripheral.
  Future<void> write(List<int> value, {bool withoutResponse = false}) async {
    await UniversalBle.writeValue(
      _deviceId,
      _serviceId,
      uuid,
      Uint8List.fromList(value),
      withoutResponse
          ? BleOutputProperty.withoutResponse
          : BleOutputProperty.withResponse,
    );
  }

  String get _deviceId {
    String? deviceId = metaData?.deviceId;
    if (deviceId == null) {
      throw "DeviceId is not preset in characteristic metaData";
    }
    return deviceId;
  }

  String get _serviceId {
    String? serviceId = metaData?.serviceId;
    if (serviceId == null) {
      throw "ServiceId is not preset in characteristic metaData";
    }
    return serviceId;
  }
}
