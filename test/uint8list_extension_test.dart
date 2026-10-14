import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/src/extensions/uint8list_extension.dart';

void main() {
  group('Uint8ListExtension tests', () {
    test('8-bit integer conversions', () {
      final list =
          Uint8List.fromList([0xFE, 0x7F]); // 0xFE = 254 (uint8) or -2 (int8)

      expect(list.toInt8(0), -2);
      expect(list.toUint8(0), 254);

      expect(list.toInt8(1), 127);
      expect(list.toUint8(1), 127);
    });

    test('16-bit integer conversions with endianness and offset', () {
      // 0x1234 in little endian is [0x34, 0x12]
      // 0x1234 in big endian is [0x12, 0x34]
      final list = Uint8List.fromList([0xAA, 0x34, 0x12, 0x12, 0x34]);

      // at offset 1, little endian
      expect(list.toInt16(offset: 1, endian: Endian.little), 0x1234);
      expect(list.toUint16(offset: 1, endian: Endian.little), 0x1234);

      // at offset 3, big endian
      expect(list.toInt16(offset: 3, endian: Endian.big), 0x1234);
      expect(list.toUint16(offset: 3, endian: Endian.big), 0x1234);

      // signed negative test (0xFFFE = -2)
      final negList = Uint8List.fromList([0xFE, 0xFF]);
      expect(negList.toInt16(), -2);
      expect(negList.toUint16(), 65534);
    });

    test('32-bit integer conversions', () {
      final list = Uint8List.fromList([0x78, 0x56, 0x34, 0x12]);
      expect(list.toInt32(), 0x12345678);
      expect(list.toUint32(), 0x12345678);

      final negList = Uint8List.fromList([0xFF, 0xFF, 0xFF, 0xFF]);
      expect(negList.toInt32(), -1);
      expect(negList.toUint32(), 0xFFFFFFFF);
    });

    test('64-bit integer conversions', () {
      final list =
          Uint8List.fromList([0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);
      expect(list.toInt64(), 1);
      expect(list.toUint64(), 1);
    });

    test('float32 and float64 conversions', () {
      final bd = ByteData(8);
      bd.setFloat32(0, 3.140000104904175, Endian.little);
      final list = bd.buffer.asUint8List();
      expect(list.toFloat32(), closeTo(3.14, 0.001));

      bd.setFloat64(0, 123456.789, Endian.little);
      expect(bd.buffer.asUint8List().toFloat64(), closeTo(123456.789, 0.0001));
    });

    test('toUtf8 string conversion', () {
      final list = Uint8List.fromList('Universal BLE'.codeUnits);
      expect(list.toUtf8(), 'Universal BLE');
    });

    test('toHexString conversion', () {
      final list = Uint8List.fromList([0x01, 0x0A, 0xFF]);
      expect(list.toHexString(), '010aff');
      expect(list.toHexString(separator: ':'), '01:0a:ff');
      expect(list.toHexString(separator: ' ', upperCase: true), '01 0A FF');
      expect(Uint8List(0).toHexString(), '');
    });

    test('byteData getter', () {
      final list = Uint8List.fromList([1, 2, 3, 4]);
      expect(list.byteData.lengthInBytes, 4);
    });
  });

  group('FutureUint8ListExtension tests', () {
    test('Future conversions work asynchronously', () async {
      final futureBytes = Future.value(Uint8List.fromList([0x34, 0x12]));
      expect(await futureBytes.toUint16(), 0x1234);

      final futureInt8 = Future.value(Uint8List.fromList([0xFE]));
      expect(await futureInt8.toInt8(), -2);
      expect(await futureInt8.toUint8(), 254);

      final futureStr = Future.value(Uint8List.fromList('BLE'.codeUnits));
      expect(await futureStr.toUtf8(), 'BLE');

      final futureHex = Future.value(Uint8List.fromList([0xAA, 0xBB]));
      expect(await futureHex.toHexString(separator: '-'), 'aa-bb');
    });
  });
}
