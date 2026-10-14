
/// A BLE device id in the two forms universal_ble needs, and the only place the conversion
/// between them lives.
///
/// A device id reaches us from a platform in whatever case that platform happens to report — and
/// two of its consumers want different ones:
///
/// * The Dart layer emits, compares and keys per-device state by the [canonical] form, so a caller
///   holding an id in another case cannot split state or miss events.
/// * Native channels want the [native] form: Android's `BluetoothAdapter.getRemoteDevice`
///   REQUIRES upper case and throws otherwise, Apple's peripheral cache is keyed by the upper-case
///   `uuidString`, and Linux's BlueZ address is upper-case. Windows formats MACs lower-case but
///   parses and compares them case-insensitively, so upper case is safe there too.
///
/// The two forms only differ for an *address* — a MAC on Android/Windows/Linux, a UUID on Apple —
/// which is case-insensitive. Web Bluetooth ids are not addresses but opaque, case-sensitive
/// browser tokens (Chromium emits Base64 of a random value), so [DeviceId.opaque] carries them
/// through untouched: folding one would corrupt the id the caller sees and break the device
/// lookup it is passed back to.
///
/// Internal: the public API takes and returns ids as plain [String]s.
class DeviceId {
  /// The form the Dart layer emits, matches and keys state by.
  final String canonical;

  /// The form native channel calls take.
  final String native;

  const DeviceId._(this.canonical, this.native);

  /// A case-insensitive Bluetooth address (a MAC, or a UUID on Apple) by default.
  factory DeviceId(String id, {bool isAddress = true}) => isAddress
      ? DeviceId._(id.toLowerCase(), id.toUpperCase())
      : DeviceId._(id, id);

  /// A case-insensitive Bluetooth address (a MAC, or a UUID on Apple).
  factory DeviceId.address(String id) => DeviceId(id, isAddress: true);

  /// An opaque, case-sensitive token — a Web Bluetooth id.
  factory DeviceId.opaque(String id) => DeviceId(id, isAddress: false);

  /// [DeviceId.address] when [isAddress], else [DeviceId.opaque]. Platforms report their kind via
  /// `UniversalBlePlatform.hasAddressDeviceIds`.
  factory DeviceId.of(String id, {required bool isAddress}) =>
      DeviceId(id, isAddress: isAddress);

  @override
  String toString() => canonical;

  @override
  bool operator ==(Object other) =>
      other is DeviceId &&
      other.canonical == canonical &&
      other.native == native;

  static final RegExp _macRegex = RegExp(
    r'^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$|^[0-9A-Fa-f]{12}$',
  );
  static final RegExp _uuidRegex = RegExp(
    r'^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$',
  );

  /// Returns true if [id] matches the format of a Bluetooth hardware address
  /// (a MAC address or a 128-bit UUID).
  static bool looksLikeAddress(String id) =>
      _macRegex.hasMatch(id) || _uuidRegex.hasMatch(id);

  @override
  int get hashCode => Object.hash(canonical, native);
}

extension DeviceIdStringExtension on String {
  /// Converts this string into a [DeviceId].
  ///
  /// Defaults to address device id ([isAddress] = true).
  DeviceId toDeviceId({bool isAddress = true}) =>
      DeviceId(this, isAddress: isAddress);
}
