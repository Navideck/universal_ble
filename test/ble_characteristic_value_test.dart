import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';

import 'universal_ble_test_mock.dart';

class _MockPlatform extends UniversalBlePlatformMock {}

void main() {
  const deviceId = 'AA:BB:CC:DD:EE:FF';
  const charId = '0000fff1-0000-1000-8000-00805f9b34fb';

  test('onValueChange receives a BleCharacteristicValue with all fields',
      () async {
    final platform = _MockPlatform();
    final received = <BleCharacteristicValue>[];
    platform.onValueChange = received.add;
    platform.updateCharacteristicValue(
        deviceId, charId, Uint8List.fromList([1, 2, 3]), 1234567890);
    final update = received.single;
    expect(update.deviceId, deviceId);
    expect(update.characteristicId, charId);
    expect(update.value, [1, 2, 3]);
    expect(update.timestamp, 1234567890);
  });

  test('onValueChange carries a null timestamp when the platform reports none',
      () async {
    final platform = _MockPlatform();
    final received = <BleCharacteristicValue>[];
    platform.onValueChange = received.add;
    platform.updateCharacteristicValue(
        deviceId, charId, Uint8List.fromList([1]), null);
    expect(received.single.timestamp, isNull);
  });
}
