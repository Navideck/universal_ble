import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/src/utils/device_id.dart';

/// [DeviceId] is the one place device-id case conversion lives: the canonical form the Dart layer
/// emits/matches/keys by, and the native form channel calls take.
void main() {
  const upper = 'AA:BB:CC:DD:EE:FF';
  const lower = 'aa:bb:cc:dd:ee:ff';

  group('address ids', () {
    test('canonicalise to lower-case whatever case the platform reports', () {
      expect(DeviceId.address(upper).canonical, lower);
      expect(DeviceId.address(lower).canonical, lower);
    });

    test('convert to upper-case for native calls', () {
      // Android's getRemoteDevice throws on a lower-case MAC.
      expect(DeviceId.address(lower).native, upper);
      expect(DeviceId.address(upper).native, upper);
    });

    test('round-trip through both forms is stable', () {
      final id = DeviceId.address(upper);
      expect(DeviceId.address(id.native).canonical, id.canonical);
      expect(DeviceId.address(id.canonical).native, id.native);
    });

    test('the two cases are the same DeviceId', () {
      expect(DeviceId.address(upper), DeviceId.address(lower));
      expect(DeviceId.address(upper).hashCode, DeviceId.address(lower).hashCode);
    });
  });

  group('opaque ids', () {
    // Chromium reports Base64 of a random value; folding one corrupts it.
    const opaque = 'mHZbW+PZqBpUlZlVQrPzOQ==';

    test('are carried through untouched in both forms', () {
      expect(DeviceId.opaque(opaque).canonical, opaque);
      expect(DeviceId.opaque(opaque).native, opaque);
    });

    test('differing only in case are different devices', () {
      expect(
        DeviceId.opaque(opaque),
        isNot(DeviceId.opaque(opaque.toLowerCase())),
      );
    });
  });

  test('DeviceId.of picks the kind the platform reports', () {
    expect(DeviceId.of(upper, isAddress: true), DeviceId.address(upper));
    expect(DeviceId.of(upper, isAddress: false), DeviceId.opaque(upper));
  });

  test('toString is the canonical form, so ids interpolate consistently', () {
    expect('${DeviceId.address(upper)}', lower);
  });
}
