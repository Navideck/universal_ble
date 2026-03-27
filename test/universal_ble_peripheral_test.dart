import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
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
}
