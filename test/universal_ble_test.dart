import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';

void main() {
  group('Throws exception', () {
    test('when length is less than 4', () {
      expect(
        () => BleUuid.parse('123'),
        throwsFormatException,
      );
    });
    test('when having more "-"s', () {
      expect(
        () => BleUuid.parse('0000-180a-0000-1000-8000-0080-5f9b-34fb'),
        throwsFormatException,
      );
    });

    test('when is too short', () {
      expect(
        () => BleUuid.parse('0000180a-0000-1000-8000-00805f9b34f'),
        throwsFormatException,
      );
    });

    test('when is too long', () {
      expect(
        () => BleUuid.parse('0000180a-0000-1000-8000-00805f9b34fba'),
        throwsFormatException,
      );
    });
  });

  group('Valid UUID', () {
    test('128-bit Lowercase', () {
      expect(
        BleUuid.parse('0000180a-0000-1000-8000-00805f9b34fb'),
        equals('0000180a-0000-1000-8000-00805f9b34fb'),
      );
    });

    test('128-bit Uppercase', () {
      expect(
        BleUuid.parse('0000180A-0000-1000-8000-00805F9B34FB'),
        equals('0000180a-0000-1000-8000-00805f9b34fb'),
      );
    });

    test('lowercase 16-bit String to 128-bit', () {
      expect(
        BleUuid.parse('180a'),
        equals('0000180a-0000-1000-8000-00805f9b34fb'),
      );
    });

    test('uppercase 16-bit String to 128-bit', () {
      expect(
        BleUuid.parse('180A'),
        equals('0000180a-0000-1000-8000-00805f9b34fb'),
      );
    });

    test('lowercase 16-bit String to 128-bit starting with 0x', () {
      expect(
        () => BleUuid.parse('0x0180a'),
        equals('0000180a-0000-1000-8000-00805f9b34fb'),
      );
    });

    test('uppercase 16-bit String to 128-bit starting with 0x', () {
      expect(
        () => BleUuid.parse('0x0180A'),
        equals('0000180a-0000-1000-8000-00805f9b34fb'),
      );
    });

    test('lowercase 16-bit to 128-bit', () {
      expect(
        BleUuid.extend(0x180a),
        equals('0000180a-0000-1000-8000-00805f9b34fb'),
      );
    });

    test('uppercase 16-bit to 128-bit', () {
      expect(
        BleUuid.extend(0x180A),
        equals('0000180a-0000-1000-8000-00805f9b34fb'),
      );
    });

    test('lowercase 16-bit to 128-bit', () {
      expect(
        BleUuid.extend(0x180a),
        equals('0000180a-0000-1000-8000-00805f9b34fb'),
      );
    });

    test('32-bit', () {
      expect(
        BleUuid.parse('0000180a'),
        equals('0000180a-0000-1000-8000-00805f9b34fb'),
      );
    });

    test('Without Dashes', () {
      expect(
        BleUuid.parse('0000180a00001000800000805f9b34fb'),
        equals('0000180a-0000-1000-8000-00805f9b34fb'),
      );
    });
  });

  group('Compare UUIDs', () {
    test('Case and Format Insensitive', () {
      expect(
        BleUuid.equals('0000180a-0000-1000-8000-00805f9b34fb', '180a'),
        isTrue,
      );
    });

    test('Case Insensitive', () {
      expect(
        BleUuid.equals('180A', '180a'),
        isTrue,
      );
    });

    test('Full Format', () {
      expect(
        BleUuid.equals('0000180A00001000800000805F9B34FB', '180a'),
        isTrue,
      );
    });

    test('32-bit to 128-bit', () {
      expect(
        BleUuid.equals('0000180A', '0000180a-0000-1000-8000-00805f9b34fb'),
        isTrue,
      );
    });
  });
}
