import 'package:flutter_test/flutter_test.dart';

import 'universal_ble_test_mock.dart';

/// Pairing state is de-duplicated against the last value reported (platforms such as Linux report
/// `device.paired` on every D-Bus event, and we don't want identical state updates spamming the callback). A
/// *failed* bond is an event rather than a state — it always reports `isPaired: false` — so it must bypass
/// that de-duplication, otherwise every failure after the first is swallowed (#325). Device ids are matched
/// case-insensitively throughout.
class _MockPlatform extends UniversalBlePlatformMock {}

void main() {
  const upper = 'AA:BB:CC:DD:EE:FF';
  const lower = 'aa:bb:cc:dd:ee:ff';

  test('pairingStateStream matches a device id reported in a different case', () async {
    final platform = _MockPlatform();
    final event = platform.pairingStateStream(upper).first;
    platform.updatePairingState(lower, true);
    expect(await event, isTrue);
  });

  test('dedup treats the two cases as one device', () async {
    final platform = _MockPlatform();
    final events = <bool>[];
    final sub = platform.pairingStateStream(upper).listen(events.add);
    platform.updatePairingState(lower, true); // first -> emits
    platform.updatePairingState(upper, true); // same device+value, other case -> deduped, no second emit
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await sub.cancel();
    expect(events, [true]);
  });

  test('repeated false state without a failure still dedups', () async {
    final platform = _MockPlatform();
    final events = <bool>[];
    final sub = platform.pairingStateStream(upper).listen(events.add);
    platform.updatePairingState(lower, false); // first -> emits
    platform.updatePairingState(lower, false); // steady state, not a failure -> deduped
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await sub.cancel();
    expect(events, [false]);
  });

  test('failures bypass dedup so a second failure still fires', () async {
    final platform = _MockPlatform();
    final events = <bool>[];
    final sub = platform.pairingStateStream(upper).listen(events.add);
    platform.updatePairingState(lower, false); // first report -> emits
    platform.updatePairingFailure(lower); // failure, same value -> must emit
    platform.updatePairingFailure(lower); // second failure -> must still emit (#325)
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await sub.cancel();
    expect(events, [false, false, false]);
  });

  test('a failure refreshes the cached state so a later identical state dedups', () async {
    final platform = _MockPlatform();
    final events = <bool>[];
    platform.onPairingStateChange = (id, isPaired) => events.add(isPaired);
    platform.updatePairingState(lower, true);
    platform.updatePairingFailure(lower); // caches false and emits
    platform.updatePairingState(lower, false); // same as the failure's cached value -> deduped
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(events, [true, false]);
  });
}
