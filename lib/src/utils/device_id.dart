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

  /// A case-insensitive Bluetooth address (a MAC, or a UUID on Apple).
  factory DeviceId.address(String id) =>
      DeviceId._(id.toLowerCase(), id.toUpperCase());

  /// An opaque, case-sensitive token — a Web Bluetooth id.
  factory DeviceId.opaque(String id) => DeviceId._(id, id);

  /// [DeviceId.address] when [isAddress], else [DeviceId.opaque]. Platforms report their kind via
  /// `UniversalBlePlatform.hasAddressDeviceIds`.
  factory DeviceId.of(String id, {required bool isAddress}) =>
      isAddress ? DeviceId.address(id) : DeviceId.opaque(id);

  @override
  String toString() => canonical;

  @override
  bool operator ==(Object other) =>
      other is DeviceId &&
      other.canonical == canonical &&
      other.native == native;

  @override
  int get hashCode => Object.hash(canonical, native);
}
