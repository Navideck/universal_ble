import 'package:bluez/bluez.dart';

class UUID {
  late String value;
  late BlueZUUID _blueZUUID;

  UUID(String uuid) {
    if (uuid.length < 8) {
      try {
        int shortValue = int.parse(uuid, radix: 16);
        _blueZUUID = BlueZUUID.short(shortValue);
      } catch (e) {
        _blueZUUID = BlueZUUID.fromString(uuid);
      }
    } else {
      _blueZUUID = BlueZUUID.fromString(uuid);
    }
    value = _blueZUUID.toString();
  }

  factory UUID.fromShort(int short) {
    BlueZUUID blueZUUID = BlueZUUID.short(short);
    return UUID(blueZUUID.toString());
  }

  bool get isShort => _blueZUUID.isShort;

  @override
  String toString() {
    return value;
  }
}

/// Parse a list of strings to a list of UUIDs
extension StringListToUUID on List<String> {
  List<String> toValidUUIDList() => map((e) => UUID(e).value).toList();
}
