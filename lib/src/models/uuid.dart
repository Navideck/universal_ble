import 'package:bluez/bluez.dart';

class Uuid {
  /// Parse a String to valid UUID and convert a 16 bit UUID to 128 bit UUID
  /// Throws `FormatException` if the UUID is invalid
  static String parse(String uuid) {
    if (uuid.length <= 4) {
      try {
        return BlueZUUID.short(
          int.parse(uuid, radix: 16),
        ).toString();
      } catch (_) {}
    }
    return BlueZUUID.fromString(uuid).toString();
  }

  /// Parse 16 bit uuid like `0x1800` to 128 bit uuid like `00001800-0000-1000-8000-00805f9b34fb`
  static String parseShort(int short) {
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
