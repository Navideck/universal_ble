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

  // Device ids are canonicalised to lower-case on the way OUT too: every callback/stream now emits the
  // lower-case form regardless of the case the platform reported. (Breaking, for the next major — the native
  // side converts back to upper-case at its boundary; see `_nativeId` in the pigeon channel / Linux instance.)

  test('updateConnection emits a lower-case id even when the platform reports upper-case', () {
    final platform = _MockPlatform();
    String? emitted;
    platform.onConnectionChange = (id, isConnected, error) => emitted = id;
    platform.updateConnection(upper, true);
    expect(emitted, lower);
  });

  test('updateCharacteristicValue emits a lower-case id', () {
    final platform = _MockPlatform();
    String? emitted;
    platform.onValueChange =
        (id, characteristicId, value, timestamp) => emitted = id;
    platform.updateCharacteristicValue(
        upper, charId, Uint8List.fromList([1]), null);
    expect(emitted, lower);
  });

  test('updatePairingState emits a lower-case id', () {
    final platform = _MockPlatform();
    String? emitted;
    platform.onPairingStateChange = (id, isPaired) => emitted = id;
    platform.updatePairingState(upper, true);
    expect(emitted, lower);
  });

  test('updateConnectionParameters emits a lower-case id', () {
    final platform = _MockPlatform();
    String? emitted;
    platform.onConnectionParametersChange = (u) => emitted = u.deviceId;
    platform.updateConnectionParameters(BleConnectionParametersUpdated(
        deviceId: upper,
        interval: 12,
        latency: 0,
        supervisionTimeout: 500,
        status: 0));
    expect(emitted, lower);
  });

  test('updateScanResult emits a lower-case id', () {
    final platform = _MockPlatform();
    String? emitted;
    platform.onScanResultUpdate = (d) => emitted = d.deviceId;
    platform.updateScanResult(BleDevice(deviceId: upper, name: null));
    expect(emitted, lower);
  });
}
