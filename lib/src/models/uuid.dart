import 'package:bluez/bluez.dart';

class UUID {
  late String value;

  UUID(String uuid) {
    // To validate the short UUID
    if (uuid.length <= 4) {
      try {
        int shortValue = int.parse(uuid, radix: 16);
        value = BlueZUUID.short(shortValue).toString();
        return;
      } catch (_) {}
    }
    // To validate the UUID
    BlueZUUID.fromString(uuid);
    value = uuid;
  }

  factory UUID.fromShort(int short) {
    BlueZUUID blueZUUID = BlueZUUID.short(short);
    return UUID(blueZUUID.toString());
  }

  @override
  String toString() {
    return value;
  }
}

/// Parse a list of strings to a list of UUIDs
extension StringListToUUID on List<String> {
  List<String> toValidUUIDList() => map((e) => UUID(e).value).toList();
}
