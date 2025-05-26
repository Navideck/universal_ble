import 'dart:typed_data';
import 'package:universal_ble/universal_ble.dart';

extension BleCharacteristicExtension on BleCharacteristic {
  Stream<Uint8List> get onValueReceived =>
      UniversalBle.characteristicValueStream(_deviceId, uuid);

  Future<void> disableNotify() => UniversalBle.setNotifiable(
        _deviceId,
        _serviceId,
        uuid,
        BleInputProperty.disabled,
      );

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

  Future<Uint8List> read() => UniversalBle.readValue(
        _deviceId,
        _serviceId,
        uuid,
      );

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
