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

  factory BleCharacteristic.fromJson(Map<String, dynamic> json) {
    final propertiesJson = (json['properties'] as List<dynamic>? ?? <dynamic>[])
        .whereType<String>()
        .map(_propertyFromName)
        .whereType<CharacteristicProperty>()
        .toList();
    final descriptorsJson =
        (json['descriptors'] as List<dynamic>? ?? <dynamic>[])
            .whereType<Map>()
            .map((e) => BleDescriptor.fromJson(Map<String, dynamic>.from(e)))
            .toList();
    return BleCharacteristic(
      json['uuid'] as String,
      propertiesJson,
      descriptorsJson,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'uuid': uuid,
    'properties': properties.map((e) => e.name).toList(),
    'descriptors': descriptors.map((e) => e.toJson()).toList(),
  };

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

  factory BleDescriptor.fromJson(Map<String, dynamic> json) {
    return BleDescriptor(json['uuid'] as String);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{'uuid': uuid};

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

  factory BlePeripheralService.fromJson(Map<String, dynamic> json) {
    final characteristics =
        (json['characteristics'] as List<dynamic>? ?? <dynamic>[])
            .whereType<Map>()
            .map(
              (e) => BlePeripheralCharacteristic.fromJson(
                Map<String, dynamic>.from(e),
              ),
            )
            .toList();
    return BlePeripheralService(
      primary: json['primary'] as bool? ?? true,
      uuid: json['uuid'] as String,
      characteristics: characteristics,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'uuid': uuid,
    'primary': primary,
    'characteristics': characteristics
        .map((characteristic) => characteristic.toJson())
        .toList(),
  };

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

  factory BlePeripheralCharacteristic.fromJson(Map<String, dynamic> json) {
    final propertiesJson = (json['properties'] as List<dynamic>? ?? <dynamic>[])
        .whereType<String>()
        .map(_propertyFromName)
        .whereType<CharacteristicProperty>()
        .toList();
    final descriptorsJson =
        (json['descriptors'] as List<dynamic>? ?? <dynamic>[])
            .whereType<Map>()
            .map(
              (e) => BlePeripheralDescriptor.fromJson(
                Map<String, dynamic>.from(e),
              ),
            )
            .toList();
    final permissions = (json['permissions'] as List<dynamic>? ?? <dynamic>[])
        .whereType<String>()
        .map(_permissionFromName)
        .whereType<PeripheralAttributePermission>()
        .toList();
    final valueList = json['value'] as List<dynamic>?;
    return BlePeripheralCharacteristic(
      uuid: json['uuid'] as String,
      properties: propertiesJson,
      descriptors: descriptorsJson,
      permissions: permissions,
      value: valueList == null || valueList.isEmpty
          ? null
          : Uint8List.fromList(valueList.whereType<int>().toList()),
    );
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'uuid': uuid,
    'properties': properties.map((e) => e.name).toList(),
    'descriptors': descriptors.map((e) => e.toJson()).toList(),
    'permissions': permissions.map((e) => e.name).toList(),
    'value': value?.toList(),
  };

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

  factory BlePeripheralDescriptor.fromJson(Map<String, dynamic> json) {
    final permissions = (json['permissions'] as List<dynamic>? ?? <dynamic>[])
        .whereType<String>()
        .map(_permissionFromName)
        .whereType<PeripheralAttributePermission>()
        .toList();
    final valueList = json['value'] as List<dynamic>?;
    return BlePeripheralDescriptor(
      uuid: json['uuid'] as String,
      value: valueList == null || valueList.isEmpty
          ? null
          : Uint8List.fromList(valueList.whereType<int>().toList()),
      permissions: permissions.isEmpty ? null : permissions,
    );
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'uuid': uuid,
    'value': value?.toList(),
    'permissions': permissions?.map((e) => e.name).toList(),
  };

  PeripheralDescriptor toPeripheralDescriptor() =>
      PeripheralDescriptor(uuid: uuid, value: value, permissions: permissions);
}

CharacteristicProperty? _propertyFromName(String propertyName) {
  try {
    return CharacteristicProperty.values.byName(propertyName);
  } catch (_) {
    return null;
  }
}

PeripheralAttributePermission? _permissionFromName(String permissionName) {
  try {
    return PeripheralAttributePermission.values.byName(permissionName);
  } catch (_) {
    return null;
  }
}
