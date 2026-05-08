import 'dart:typed_data';
import 'package:universal_ble/src/universal_ble.g.dart';
import 'package:universal_ble/universal_ble.dart';

class BleService {
  String uuid;
  List<BleCharacteristic> characteristics;

  BleService(String uuid, this.characteristics)
    : uuid = BleUuidParser.string(uuid);

  @override
  String toString() {
    return 'BleService{uuid: $uuid, characteristics: $characteristics}';
  }
}

class BleCharacteristic {
  String uuid;
  List<CharacteristicProperty> properties;
  List<BleDescriptor> descriptors;

  /// Metadata for this characteristic.
  ({String deviceId, String serviceId})? metaData;

  BleCharacteristic(String uuid, this.properties, this.descriptors)
    : uuid = BleUuidParser.string(uuid);

  BleCharacteristic.withMetaData({
    required String deviceId,
    required String serviceId,
    required String uuid,
    required this.properties,
    required this.descriptors,
  }) : uuid = BleUuidParser.string(uuid),
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

class BleDescriptor {
  String uuid;
  BleDescriptor(String uuid) : uuid = BleUuidParser.string(uuid);

  @override
  String toString() => 'BleDescriptor{uuid: $uuid}';

  @override
  bool operator ==(Object other) {
    if (other is! BleDescriptor) return false;
    return other.uuid == uuid;
  }

  @override
  int get hashCode => uuid.hashCode;
}

/// Peripheral/GATT server service model that reuses [BleService].
///
/// This extends [BleService] with peripheral-only fields such as [primary].
class BlePeripheralService extends BleService {
  bool primary;

  @override
  List<BlePeripheralCharacteristic> get characteristics =>
      super.characteristics.cast<BlePeripheralCharacteristic>();

  BlePeripheralService({
    this.primary = true,
    required String uuid,
    required List<BlePeripheralCharacteristic> characteristics,
  }) : super(uuid, characteristics);

  PeripheralService toPeripheralService() => PeripheralService(
    uuid: uuid,
    primary: primary,
    characteristics: characteristics
        .map((characteristic) => characteristic.toPeripheralCharacteristic())
        .toList(),
  );
}

/// Peripheral/GATT server characteristic model that reuses [BleCharacteristic].
///
/// This extends [BleCharacteristic] with peripheral-only fields such as
/// [permissions] and optional initial [value].
class BlePeripheralCharacteristic extends BleCharacteristic {
  List<PeripheralAttributePermission> permissions;
  Uint8List? value;

  @override
  List<BlePeripheralDescriptor> get descriptors =>
      super.descriptors.cast<BlePeripheralDescriptor>();

  BlePeripheralCharacteristic({
    required String uuid,
    required List<CharacteristicProperty> properties,
    List<BlePeripheralDescriptor> descriptors = const [],
    required this.permissions,
    this.value,
  }) : super(uuid, properties, descriptors);

  PeripheralCharacteristic toPeripheralCharacteristic() =>
      PeripheralCharacteristic(
        uuid: uuid,
        properties: properties,
        permissions: permissions,
        descriptors: descriptors
            .map((e) => e.toPeripheralDescriptor())
            .toList(),
        value: value,
      );
}

/// Peripheral/GATT server descriptor model that reuses [BleDescriptor].
class BlePeripheralDescriptor extends BleDescriptor {
  Uint8List? value;
  List<PeripheralAttributePermission>? permissions;

  BlePeripheralDescriptor({required String uuid, this.value, this.permissions})
    : super(uuid);

  PeripheralDescriptor toPeripheralDescriptor() =>
      PeripheralDescriptor(uuid: uuid, value: value, permissions: permissions);
}
