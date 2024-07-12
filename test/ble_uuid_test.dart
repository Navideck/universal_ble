// TODO add Github Action for running on Linux and web
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';

void main() {
  group('parse', () {
    // TODO test all parse code paths
    group('throws exception when', () {
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

    group('with success when', () {
      test('128-bit UUID in lowercase', () {
        expect(
          BleUuid.parse('0000180a-0000-1000-8000-00805f9b34fb'),
          equals('0000180a-0000-1000-8000-00805f9b34fb'),
        );
      });

      test('128-bit UUID in uppercase', () {
        expect(
          BleUuid.parse('0000180A-0000-1000-8000-00805F9B34FB'),
          equals('0000180a-0000-1000-8000-00805f9b34fb'),
        );
      });

      test('16-bit UUID in lowercase', () {
        expect(
          BleUuid.parse('180a'),
          equals('0000180a-0000-1000-8000-00805f9b34fb'),
        );
      });

      test('16-bit UUID in uppercase', () {
        expect(
          BleUuid.parse('180A'),
          equals('0000180a-0000-1000-8000-00805f9b34fb'),
        );
      });

      test('32-bit UUID', () {
        expect(
          BleUuid.parse('0000180a'),
          equals('0000180a-0000-1000-8000-00805f9b34fb'),
        );
      });

      test('UUID without dashes', () {
        expect(
          BleUuid.parse('0000180a00001000800000805f9b34fb'),
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
    });
  });

  group('extend', () {
    test('16-bit UUID in lowercase', () {
      expect(
        BleUuid.extend(0x180a),
        equals('0000180a-0000-1000-8000-00805f9b34fb'),
      );
    });

    test('16-bit UUID in uppercase', () {
      expect(
        BleUuid.extend(0x180A),
        equals('0000180a-0000-1000-8000-00805f9b34fb'),
      );
    });

    // TODO Add 32 and 128 bit tests
    // TODO Add tests for failure cases (empty, null, shorter or longer value, non hex)
  });

  group('equals', () {
    test('true for Identical UUIDs', () {
      expect(
        BleUuid.equals('0000180a-0000-1000-8000-00805f9b34fb',
            '0000180a-0000-1000-8000-00805f9b34fb'),
        isTrue,
      );
    });

    test('true for UUIDs with different character case', () {
      expect(
        BleUuid.equals('180A', '180a'),
        isTrue,
      );
    });

    test('true for the 16-bit and 128-bit representation of the same UUID', () {
      expect(
        BleUuid.equals('0000180a-0000-1000-8000-00805f9b34fb', '180a'),
        isTrue,
      );
    });

    test(
        'true for the 16-bit and 128-bit representation of the same UUID without dashes',
        () {
      expect(
        BleUuid.equals('0000180A00001000800000805F9B34FB', '180a'),
        isTrue,
      );
    });

    test('true for the 32-bit and 128-bit representation of the same UUID', () {
      expect(
        BleUuid.equals('0000180A', '0000180a-0000-1000-8000-00805f9b34fb'),
        isTrue,
      );
    });

    test('false for different UUIDs', () {
      expect(
        BleUuid.equals('180A', '180B'),
        isFalse,
      );
    });

    test('false for different UUIDs of different format', () {
      expect(
        BleUuid.equals('0000180A', '0000180b-0000-1000-8000-00805f9b34fb'),
        isFalse,
      );
    });
  });
}
