import 'package:bluez/bluez.dart';

class Uuid {
  /// Parse a String to valid UUID and convert a 16 bit UUID to 128 bit UUID
  /// Throws `FormatException` if the UUID is invalid
  static String parse(String uuid) {
    if (uuid.length < 4) throw const FormatException("Invalid UUID");
    if (uuid.length <= 8) {
      uuid = "${uuid.padLeft(8, '0')}-0000-1000-8000-00805f9b34fb";
    } else if (!uuid.contains("-")) {
      if (uuid.length != 32) throw const FormatException("Invalid UUID");
      uuid = "${uuid.substring(0, 8)}-${uuid.substring(8, 12)}"
          "-${uuid.substring(12, 16)}-${uuid.substring(16, 20)}-${uuid.substring(20, 32)}";
    }
    return BlueZUUID.fromString(uuid).toString();
  }

  /// Parse 16/32 bit uuid like `0x1800` to 128 bit uuid like `00001800-0000-1000-8000-00805f9b34fb`
  static String extend(int short) {
    BlueZUUID blueZUUID = BlueZUUID.short(short);
    return blueZUUID.toString();
  }

  /// Compare two UUIDs to automatically convert both to 128 bit UUIDs
  /// Throws `FormatException` if the UUID is invalid
  static bool equals(String uuid1, String uuid2) {
    return parse(uuid1) == parse(uuid2);
  }
}

/// Parse a list of strings to a list of UUIDs
extension StringListToUUID on List<String> {
  List<String> toValidUUIDList() => map(Uuid.parse).toList();
}
