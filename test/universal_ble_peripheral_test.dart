import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/src/universal_ble_peripheral/universal_ble_peripheral_mapper.dart';
import 'package:universal_ble/universal_ble.dart';

void main() {
  test('peripheral request result models store values', () {
    final read = BleReadRequestResult(
      value: Uint8List.fromList([1, 2, 3]),
      offset: 1,
      status: 0,
    );
    const write = BleWriteRequestResult(offset: 2, status: 0);

    expect(read.value, Uint8List.fromList([1, 2, 3]));
    expect(read.offset, 1);
    expect(read.status, 0);
    expect(write.offset, 2);
    expect(write.status, 0);
  });

  test('peripheral uses shared model types', () {
    final service = BleService('180f', [
      BleCharacteristic(
        '2a19',
        [CharacteristicProperty.read, CharacteristicProperty.notify],
        [BleDescriptor('2908')],
      ),
    ]);

    expect(service.uuid, BleUuidParser.string('180f'));
    expect(service.characteristics.single.uuid, BleUuidParser.string('2a19'));
    expect(
      service.characteristics.single.properties.contains(
        CharacteristicProperty.notify,
      ),
      true,
    );
  });

  test('mapper converts service/characteristic/descriptor to pigeon types', () {
    final service = BleService('180f', [
      BleCharacteristic(
        '2a19',
        [CharacteristicProperty.read, CharacteristicProperty.indicate],
        [BleDescriptor('2902')],
      ),
    ]);

    final mapped = UniversalBlePeripheralMapper.toPigeonService(
      service,
      primary: true,
    );

    expect(mapped.uuid, BleUuidParser.string('180f'));
    expect(mapped.primary, isTrue);
    expect(mapped.characteristics, hasLength(1));

    final characteristic = mapped.characteristics.single;
    expect(characteristic.uuid, BleUuidParser.string('2a19'));
    expect(
      characteristic.properties,
      equals([
        CharacteristicProperty.read.index,
        CharacteristicProperty.indicate.index,
      ]),
    );
    expect(characteristic.descriptors, hasLength(1));
    final descriptors = characteristic.descriptors;
    expect(descriptors, isNotNull);
    expect(
      descriptors!.single.uuid,
      BleUuidParser.string('2902'),
    );
    expect(descriptors.single.value, isNull);
  });

  test('mapper forwards descriptor initial value to pigeon', () {
    final service = BleService('1812', [
      BleCharacteristic(
        '2a4d',
        [CharacteristicProperty.notify],
        [
          BleDescriptor(
            '2908',
            value: Uint8List.fromList([0x00, 0x01]),
          ),
        ],
      ),
    ]);

    final mapped = UniversalBlePeripheralMapper.toPigeonService(
      service,
      primary: true,
    );

    expect(
      mapped.characteristics.single.descriptors!.single.value,
      Uint8List.fromList([0x00, 0x01]),
    );
  });

  test('mapper converts manufacturer data to pigeon type', () {
    final data = ManufacturerData(0x004C, Uint8List.fromList([0x01, 0x02]));

    final mapped = UniversalBlePeripheralMapper.toPigeonManufacturerData(data);

    expect(mapped, isNotNull);
    expect(mapped!.manufacturerId, 0x004C);
    expect(mapped.data, Uint8List.fromList([0x01, 0x02]));
  });
}
