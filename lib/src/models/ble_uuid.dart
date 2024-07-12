class BleUuid {
  /// Parse a String to valid UUID and convert a 16 bit UUID to 128 bit UUID
  /// Throws `FormatException` if the UUID is invalid
  static String parse(String uuid) {
    if (uuid.length < 4) {
      throw const FormatException('Invalid UUID');
    }

    if (uuid.length <= 8) {
      uuid = "${uuid.padLeft(8, '0')}-0000-1000-8000-00805f9b34fb";
    }

    if (!uuid.contains("-")) {
      if (uuid.length != 32) throw const FormatException("Invalid UUID");

      uuid = "${uuid.substring(0, 8)}-${uuid.substring(8, 12)}"
          "-${uuid.substring(12, 16)}-${uuid.substring(16, 20)}-${uuid.substring(20, 32)}";
    }

    var groups = uuid.split('-');

    if (groups.length != 5 ||
        groups[0].length != 8 ||
        groups[1].length != 4 ||
        groups[2].length != 4 ||
        groups[3].length != 4 ||
        groups[4].length != 12) {
      throw const FormatException('Invalid UUID');
    }

    try {
      int.parse(groups[0], radix: 16);
      int.parse(groups[1], radix: 16);
      int.parse(groups[2], radix: 16);
      int.parse(groups[3], radix: 16);
      int.parse(groups[4], radix: 16);
    } catch (e) {
      throw const FormatException('Invalid UUID');
    }

    return uuid.toLowerCase();
  }

  /// Parse 16/32 bit UUID like `0x1800` to 128 bit UUID like `00001800-0000-1000-8000-00805f9b34fb`
  static String extend(int short) =>
      parse(short.toRadixString(16).padLeft(4, '0'));

  /// Compare two UUIDs to automatically convert both to 128 bit UUIDs
  /// Throws `FormatException` if the UUID is invalid
  static bool equals(String uuid1, String uuid2) =>
      parse(uuid1) == parse(uuid2);
}

/// Parse a list of strings to a list of UUIDs
extension StringListToUUID on List<String> {
  List<String> toValidUUIDList() => map(BleUuid.parse).toList();
}
