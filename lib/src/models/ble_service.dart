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
  broadcast(0),
  read(1),
  writeWithoutResponse(2),
  write(3),
  notify(4),
  indicate(5),
  authenticatedSignedWrites(6),
  extendedProperties(7);

  final int value;
  const CharacteristicProperty(this.value);

  factory CharacteristicProperty.parse(int value) =>
      CharacteristicProperty.values
          .firstWhere((element) => element.value == value);
}
