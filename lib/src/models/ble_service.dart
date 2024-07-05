import 'package:universal_ble/universal_ble.dart';

class BleService {
  late String uuid;
  List<BleCharacteristic> characteristics;

  BleService(String uuid, this.characteristics) {
    this.uuid = BleUuid.parse(uuid);
  }
}

class BleCharacteristic {
  late String uuid;
  List<CharacteristicProperty> properties;

  BleCharacteristic(String uuid, this.properties) {
    this.uuid = BleUuid.parse(uuid);
  }
}

enum CharacteristicProperty {
  broadcast,
  read,
  writeWithoutResponse,
  write,
  notify,
  indicate,
  authenticatedSignedWrites,
  extendedProperties;

  const CharacteristicProperty();

  factory CharacteristicProperty.parse(int index) =>
      CharacteristicProperty.values[index];
}
