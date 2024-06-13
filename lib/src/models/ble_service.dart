class BleService {
  String uuid;
  List<BleCharacteristic> characteristics;
  BleService(this.uuid, this.characteristics);
}

class BleCharacteristic {
  String uuid;
  List<CharacteristicProperty> properties;
  BleCharacteristic(this.uuid, this.properties);
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
