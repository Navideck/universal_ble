import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';

void main() {
  group("UUID", () {
    test("Invalid UUID", () {
      expect(
        () => BleUuid.parse('0x0180a'),
        throwsFormatException,
      );
      expect(
        () => BleUuid.parse('0000-180a-0000-1000-8000-0080-5f9b-34fb'),
        throwsFormatException,
      );
    });

    test("Valid UUID", () {
      // Parse 128-bit lowercase uuid
      expect(
        BleUuid.parse('0000180a-0000-1000-8000-00805f9b34fb'),
        equals("0000180a-0000-1000-8000-00805f9b34fb"),
      );
      // Parse 128-bit uppercase uuid
      expect(
        BleUuid.parse('0000180A-0000-1000-8000-00805F9B34FB'),
        equals("0000180a-0000-1000-8000-00805f9b34fb"),
      );
      // Parse 16-bit uuid string to 128-bit uuid string
      expect(
        BleUuid.parse("180a"),
        equals("0000180a-0000-1000-8000-00805f9b34fb"),
      );
      // Parse 16-bit uuid to 128-bit
      expect(
        BleUuid.extend(0x180A),
        equals("0000180a-0000-1000-8000-00805f9b34fb"),
      );
      // 32-bit UUID
      expect(
        BleUuid.parse("0000180a"),
        equals("0000180a-0000-1000-8000-00805f9b34fb"),
      );
      // UUID without dashes
      expect(
        BleUuid.parse('0000180a00001000800000805f9b34fb'),
        equals("0000180a-0000-1000-8000-00805f9b34fb"),
      );
    });

    test("Compare UUID", () {
      // Compare UUID strings, case and format insensitive
      expect(
        BleUuid.equals('0000180a-0000-1000-8000-00805f9b34fb', '180a'),
        isTrue,
      );
      expect(
        BleUuid.equals('180A', '180a'),
        isTrue,
      );
      expect(
        BleUuid.equals('0000180A00001000800000805F9B34FB', '180a'),
        isTrue,
      );
      expect(
        BleUuid.equals('0000180A', '0000180a-0000-1000-8000-00805f9b34fb'),
        isTrue,
      );
    });
  });
}
