import 'package:universal_ble/universal_ble.dart';

class BleService {
  String uuid;
  List<BleCharacteristic> characteristics;

  BleService(
    String uuid,
    this.characteristics,
  ) : uuid = BleUuidParser.string(uuid);

  @override
  String toString() {
    return 'BleService{uuid: $uuid, characteristics: $characteristics}';
  }
}

class BleCharacteristic {
  String uuid;
  List<CharacteristicProperty> properties;
  ({String deviceId, String serviceId})? metaData;

  BleCharacteristic(
    String uuid,
    this.properties,
  ) : uuid = BleUuidParser.string(uuid);

  BleCharacteristic.withMetaData({
    required String deviceId,
    required String serviceId,
    required String uuid,
    required this.properties,
  })  : uuid = BleUuidParser.string(uuid),
        metaData = (
          deviceId: deviceId,
          serviceId: BleUuidParser.string(serviceId),
        );

  @override
  String toString() {
    return 'BleCharacteristic{uuid: $uuid, properties: $properties}';
  }

  @override
  bool operator ==(Object other) {
    if (other is! BleCharacteristic) return false;
    if (other.uuid != uuid) return false;
    if (other.properties != properties) return false;
    if (other.metaData?.deviceId != metaData?.deviceId) return false;
    if (other.metaData?.serviceId != metaData?.serviceId) return false;
    return true;
  }

  @override
  int get hashCode => uuid.hashCode ^ properties.hashCode ^ metaData.hashCode;
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

  @override
  String toString() => name;
}
