import 'dart:convert';
import 'dart:typed_data';

/// Extensions on [Future<Uint8List>] to conveniently parse read results into numbers, strings, etc.
extension FutureUint8ListExtension on Future<Uint8List> {
  /// Converts the Future [Uint8List] to a signed 8-bit integer.
  Future<int> toInt8({int offset = 0}) =>
      then((data) => data.toInt8(offset: offset));

  /// Converts the Future [Uint8List] to an unsigned 8-bit integer.
  Future<int> toUint8({int offset = 0}) =>
      then((data) => data.toUint8(offset: offset));

  /// Converts the Future [Uint8List] to a signed 16-bit integer,
  /// assuming little-endian encoding by default.
  Future<int> toInt16({int offset = 0, Endian endian = Endian.little}) =>
      then((data) => data.toInt16(offset: offset, endian: endian));

  /// Converts the Future [Uint8List] to an unsigned 16-bit integer,
  /// assuming little-endian encoding by default.
  Future<int> toUint16({int offset = 0, Endian endian = Endian.little}) =>
      then((data) => data.toUint16(offset: offset, endian: endian));

  /// Converts the Future [Uint8List] to a signed 32-bit integer,
  /// assuming little-endian encoding by default.
  Future<int> toInt32({int offset = 0, Endian endian = Endian.little}) =>
      then((data) => data.toInt32(offset: offset, endian: endian));

  /// Converts the Future [Uint8List] to an unsigned 32-bit integer,
  /// assuming little-endian encoding by default.
  Future<int> toUint32({int offset = 0, Endian endian = Endian.little}) =>
      then((data) => data.toUint32(offset: offset, endian: endian));

  /// Converts the Future [Uint8List] to a 32-bit float,
  /// assuming little-endian encoding by default.
  Future<double> toFloat32({int offset = 0, Endian endian = Endian.little}) =>
      then((data) => data.toFloat32(offset: offset, endian: endian));

  /// Converts the Future [Uint8List] to a 64-bit float,
  /// assuming little-endian encoding by default.
  Future<double> toFloat64({int offset = 0, Endian endian = Endian.little}) =>
      then((data) => data.toFloat64(offset: offset, endian: endian));

  /// Decodes the Future [Uint8List] as a UTF-8 string.
  Future<String> toUtf8({bool allowMalformed = true}) =>
      then((data) => data.toUtf8(allowMalformed: allowMalformed));

  /// Converts the Future [Uint8List] to a hexadecimal string representation.
  Future<String> toHexString({String separator = '', bool upperCase = false}) =>
      then((data) =>
          data.toHexString(separator: separator, upperCase: upperCase));
}

/// Extensions on [Uint8List] for common BLE byte payload operations.
extension Uint8ListExtension on Uint8List {
  /// Returns a [ByteData] view of this [Uint8List].
  ByteData get byteData => ByteData.sublistView(this);

  /// Converts the byte at [offset] to a signed 8-bit integer.
  int toInt8({int offset = 0}) => byteData.getInt8(offset);

  /// Converts the byte at [offset] to an unsigned 8-bit integer.
  int toUint8({int offset = 0}) => byteData.getUint8(offset);

  /// Converts 2 bytes starting at [offset] to a signed 16-bit integer,
  /// assuming little-endian encoding by default.
  int toInt16({int offset = 0, Endian endian = Endian.little}) =>
      byteData.getInt16(offset, endian);

  /// Converts 2 bytes starting at [offset] to an unsigned 16-bit integer,
  /// assuming little-endian encoding by default.
  int toUint16({int offset = 0, Endian endian = Endian.little}) =>
      byteData.getUint16(offset, endian);

  /// Converts 4 bytes starting at [offset] to a signed 32-bit integer,
  /// assuming little-endian encoding by default.
  int toInt32({int offset = 0, Endian endian = Endian.little}) =>
      byteData.getInt32(offset, endian);

  /// Converts 4 bytes starting at [offset] to an unsigned 32-bit integer,
  /// assuming little-endian encoding by default.
  int toUint32({int offset = 0, Endian endian = Endian.little}) =>
      byteData.getUint32(offset, endian);

  /// Converts 4 bytes starting at [offset] to a 32-bit float,
  /// assuming little-endian encoding by default.
  double toFloat32({int offset = 0, Endian endian = Endian.little}) =>
      byteData.getFloat32(offset, endian);

  /// Converts 8 bytes starting at [offset] to a 64-bit float,
  /// assuming little-endian encoding by default.
  double toFloat64({int offset = 0, Endian endian = Endian.little}) =>
      byteData.getFloat64(offset, endian);

  /// Decodes this [Uint8List] as a UTF-8 string.
  ///
  /// [allowMalformed] defaults to `true`, so malformed byte sequences (for
  /// example a truncated string field) are replaced with the Unicode
  /// replacement character (U+FFFD) instead of throwing. Set it to `false` to
  /// throw on malformed input.
  String toUtf8({bool allowMalformed = true}) =>
      utf8.decode(this, allowMalformed: allowMalformed);

  /// Converts this [Uint8List] to a hexadecimal string representation.
  ///
  /// Example:
  /// ```dart
  /// Uint8List.fromList([0x01, 0x0A, 0xFF]).toHexString(); // "010aff"
  /// Uint8List.fromList([0x01, 0x0A, 0xFF]).toHexString(separator: ':'); // "01:0a:ff"
  /// Uint8List.fromList([0x01, 0x0A, 0xFF]).toHexString(separator: ' ', upperCase: true); // "01 0A FF"
  /// ```
  String toHexString({String separator = '', bool upperCase = false}) {
    if (isEmpty) return '';
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      if (i > 0 && separator.isNotEmpty) {
        buffer.write(separator);
      }
      final hex = this[i].toRadixString(16).padLeft(2, '0');
      buffer.write(upperCase ? hex.toUpperCase() : hex);
    }
    return buffer.toString();
  }
}
