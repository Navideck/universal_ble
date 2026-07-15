import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';

void main() {
  group('BleCharacteristic equality', () {
    test('equal when uuid and properties have equal content', () {
      // Two separate list instances with the same content.
      final a = BleCharacteristic('2a00', [
        CharacteristicProperty.read,
        CharacteristicProperty.notify,
      ], []);
      final b = BleCharacteristic('2a00', [
        CharacteristicProperty.read,
        CharacteristicProperty.notify,
      ], []);

      expect(a == b, isTrue);
      // Equal objects MUST have equal hashCodes (equality contract).
      expect(a.hashCode, b.hashCode);
    });

    test('not equal when properties differ', () {
      final a = BleCharacteristic('2a00', [CharacteristicProperty.read], []);
      final b = BleCharacteristic('2a00', [CharacteristicProperty.write], []);

      expect(a == b, isFalse);
    });

    test('not equal when uuid differs', () {
      final a = BleCharacteristic('2a00', [CharacteristicProperty.read], []);
      final b = BleCharacteristic('2a01', [CharacteristicProperty.read], []);

      expect(a == b, isFalse);
    });

    test('usable as Set/Map key with equal-content instances', () {
      final a = BleCharacteristic('2a00', [
        CharacteristicProperty.read,
        CharacteristicProperty.notify,
      ], []);
      final b = BleCharacteristic('2a00', [
        CharacteristicProperty.read,
        CharacteristicProperty.notify,
      ], []);

      final set = {a};
      expect(set.contains(b), isTrue);
    });
  });
}
