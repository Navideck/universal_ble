import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/src/utils/cache_handler.dart';
import 'package:universal_ble/universal_ble.dart';

import 'universal_ble_test_mock.dart';

/// A BLE device id is a case-insensitive identifier, but platforms report it in different cases (Android
/// upper-cases MACs, Windows/WinRT lower-cases them). These tests guard that universal_ble treats the two
/// cases as ONE device — both the event-stream matching AND the per-device state keyed internally (pairing
/// dedup, connection-parameters dedup, the service cache) — so a caller holding the id in a different case
/// than the platform reports doesn't miss events, doesn't hang connect(), and doesn't split across entries.
class _MockPlatform extends UniversalBlePlatformMock {
  @override
  Future<int> readRssi(String deviceId) => throw UnimplementedError();

  @override
  Future<void> connect(
    String deviceId, {
    bool autoConnect = false,
    Duration? connectionTimeout,
    ConnectionPlatformConfig? platformConfig,
  }) async {
    // Report the connection back with a DIFFERENT case than the caller passed — the original hang scenario.
    updateConnection(deviceId.toLowerCase(), true);
  }
}

void main() {
  const upper = 'AA:BB:CC:DD:EE:FF';
  const lower = 'aa:bb:cc:dd:ee:ff';
  const charId = '0000fff1-0000-1000-8000-00805f9b34fb';

  test('connectionStream matches a device id reported in a different case', () async {
    final platform = _MockPlatform();
    final event = platform.connectionStream(upper).first;
    platform.updateConnection(lower, true);
    expect(await event, isTrue);
  });

  test('characteristicValueStream matches a device id reported in a different case', () async {
    final platform = _MockPlatform();
    final event = platform.characteristicValueStream(upper, charId).first;
    platform.updateCharacteristicValue(
        lower, charId, Uint8List.fromList([1, 2, 3]), null);
    expect(await event, Uint8List.fromList([1, 2, 3]));
  });

  test(
    'characteristic values exclude unrelated platform-message buffer bytes',
    () async {
      final platform = _MockPlatform();
      final backingBuffer = Uint8List.fromList([
        100,
        58,
        51,
        97,
        1,
        2,
        3,
        4,
        5,
      ]);
      final decodedView = Uint8List.sublistView(backingBuffer, 4, 8);
      final streamValue = platform
          .characteristicValueStream(upper, charId)
          .first;
      Uint8List? callbackValue;
      platform.onValueChange = (_, _, value, _) => callbackValue = value;

      platform.updateCharacteristicValue(lower, charId, decodedView, null);

      final received = await streamValue;
      expect(received, [1, 2, 3, 4]);
      expect(received.offsetInBytes, 0);
      expect(received.buffer.lengthInBytes, received.lengthInBytes);
      expect(callbackValue, same(received));
      expect(received.buffer.asByteData().getUint8(0), 1);
    },
  );

  test(
    'standalone characteristic values are forwarded without copying',
    () async {
      final platform = _MockPlatform();
      final original = Uint8List.fromList([1, 2, 3]);
      final streamValue = platform
          .characteristicValueStream(upper, charId)
          .first;

      platform.updateCharacteristicValue(lower, charId, original, null);

      expect(await streamValue, same(original));
    },
  );

  test('pairingStateStream matches a device id reported in a different case', () async {
    final platform = _MockPlatform();
    final event = platform.pairingStateStream(upper).first;
    platform.updatePairingState(lower, true);
    expect(await event, isTrue);
  });

  test('connect() completes when the platform reports the id in a different case', () async {
    UniversalBle.setInstance(_MockPlatform());
    // Must not throw / time out: connect(upper) awaits a lower-case connection update (the original hang).
    await UniversalBle.connect(upper, timeout: const Duration(seconds: 2));
  });

  test('pairing-state dedup treats the two cases as one device', () async {
    final platform = _MockPlatform();
    final events = <bool>[];
    final sub = platform.pairingStateStream(upper).listen(events.add);
    platform.updatePairingState(lower, true); // first -> emits
    platform.updatePairingState(upper, true); // same device+value, other case -> deduped, no second emit
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await sub.cancel();
    expect(events, [true]);
  });

  test('connection-parameters dedup treats the two cases as one device', () async {
    final platform = _MockPlatform();
    final events = <String>[];
    platform.onConnectionParametersChange = (u) => events.add(u.deviceId);
    BleConnectionParametersUpdated params(String id) =>
        BleConnectionParametersUpdated(
            deviceId: id, interval: 12, latency: 0, supervisionTimeout: 500, status: 0);
    platform.updateConnectionParameters(params(lower)); // first -> fires
    platform.updateConnectionParameters(params(upper)); // identical params, other case -> deduped
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(events, [lower]);
  });

  test('service cache is keyed case-insensitively (save one case, get/clear another)', () {
    final cache = CacheHandler.instance;
    cache.resetDeviceCache(upper); // clean slate
    cache.saveServices(upper, const []); // non-null -> cached
    expect(cache.getServices(lower), isNotNull); // found via the other case
    cache.resetDeviceCache(lower); // cleared via the other case
    expect(cache.getServices(upper), isNull);
  });
}
