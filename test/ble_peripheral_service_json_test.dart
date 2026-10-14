import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';

void main() {
  group('BlePeripheralService JSON', () {
    test('fromJson parses nested peripheral models', () {
      final json = <String, dynamic>{
        'uuid': '180f',
        'primary': false,
        'characteristics': [
          <String, dynamic>{
            'uuid': '2a19',
            'properties': ['read', 'notify'],
            'permissions': ['readable', 'writeable'],
            'value': [1, 2, 3],
            'descriptors': [
              <String, dynamic>{
                'uuid': '2902',
                'permissions': ['readable'],
                'value': [7, 8],
              },
            ],
          },
        ],
      };

      final service = BlePeripheralService.fromJson(json);

      expect(service.uuid, BleUuidParser.string('180f'));
      expect(service.primary, isFalse);
      expect(service.characteristics, hasLength(1));

      final characteristic = service.characteristics.single;
      expect(characteristic.uuid, BleUuidParser.string('2a19'));
      expect(
        characteristic.properties,
        equals([CharacteristicProperty.read, CharacteristicProperty.notify]),
      );
      expect(
        characteristic.permissions,
        equals([
          PeripheralAttributePermission.readable,
          PeripheralAttributePermission.writeable,
        ]),
      );
      expect(characteristic.value, Uint8List.fromList([1, 2, 3]));
      expect(characteristic.descriptors, hasLength(1));

      final descriptor = characteristic.descriptors.single;
      expect(descriptor.uuid, BleUuidParser.string('2902'));
      expect(
        descriptor.permissions,
        equals([PeripheralAttributePermission.readable]),
      );
      expect(descriptor.value, Uint8List.fromList([7, 8]));
    });

    test('toJson serializes peripheral fields and enum names', () {
      final service = BlePeripheralService(
        primary: true,
        uuid: '180d',
        characteristics: [
          BlePeripheralCharacteristic(
            uuid: '2a37',
            properties: const [
              CharacteristicProperty.read,
              CharacteristicProperty.indicate,
            ],
            permissions: const [
              PeripheralAttributePermission.readable,
              PeripheralAttributePermission.writeEncryptionRequired,
            ],
            value: Uint8List.fromList([0x01, 0x02]),
            descriptors: [
              BlePeripheralDescriptor(
                uuid: '2901',
                value: Uint8List.fromList([0x09]),
                permissions: const [PeripheralAttributePermission.writeable],
              ),
            ],
          ),
        ],
      );

      final json = service.toJson();
      final characteristic =
          (json['characteristics'] as List<dynamic>).single
              as Map<String, dynamic>;
      final descriptor =
          (characteristic['descriptors'] as List<dynamic>).single
              as Map<String, dynamic>;

      expect(json['uuid'], BleUuidParser.string('180d'));
      expect(json['primary'], isTrue);
      expect(characteristic['uuid'], BleUuidParser.string('2a37'));
      expect(characteristic['properties'], ['read', 'indicate']);
      expect(characteristic['permissions'], [
        'readable',
        'writeEncryptionRequired',
      ]);
      expect(characteristic['value'], [1, 2]);
      expect(descriptor['uuid'], BleUuidParser.string('2901'));
      expect(descriptor['permissions'], ['writeable']);
      expect(descriptor['value'], [9]);
    });
  });
}
