import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';

import 'universal_ble_test_mock.dart';

class _MockPlatform extends UniversalBlePlatformMock {}

void main() {
  const deviceId = 'AA:BB:CC:DD:EE:FF';

  test('connectionUpdateStream carries message, unified code and native code',
      () async {
    final platform = _MockPlatform();
    final event = platform.connectionUpdateStream(deviceId).first;
    platform.updateConnection(deviceId, false, 'Connection Timeout',
        UniversalBleErrorCode.connectionTimeout, 8);
    final update = await event;
    expect(update.deviceId, deviceId);
    expect(update.isConnected, isFalse);
    expect(update.error, 'Connection Timeout');
    expect(update.errorCode, UniversalBleErrorCode.connectionTimeout);
    expect(update.nativeErrorCode, 8);
  });

  test('connectionUpdateStream has null error fields for app-requested changes',
      () async {
    final platform = _MockPlatform();
    final event = platform.connectionUpdateStream(deviceId).first;
    platform.updateConnection(deviceId, false);
    final update = await event;
    expect(update.error, isNull);
    expect(update.errorCode, isNull);
    expect(update.nativeErrorCode, isNull);
  });

  test('connectionStream still emits only the bool', () async {
    final platform = _MockPlatform();
    final events = platform.connectionStream(deviceId).take(2).toList();
    platform.updateConnection(deviceId, true);
    platform.updateConnection(
        deviceId,
        false,
        'The connection has timed out unexpectedly.',
        UniversalBleErrorCode.connectionTimeout,
        6);
    expect(await events, [true, false]);
  });

  test('onConnectionChange keeps its three-argument signature', () async {
    final platform = _MockPlatform();
    final received = <(String, bool, String?)>[];
    platform.onConnectionChange =
        (id, connected, error) => received.add((id, connected, error));
    platform.updateConnection(deviceId, false, 'Unknown Error 257',
        UniversalBleErrorCode.deviceDisconnected, 257);
    expect(received, [(deviceId, false, 'Unknown Error 257')]);
  });

  test('onConnectionUpdate receives the same update as the stream', () async {
    final platform = _MockPlatform();
    final received = <BleConnectionUpdate>[];
    platform.onConnectionUpdate = received.add;
    platform.updateConnection(deviceId, false, 'Connection Timeout',
        UniversalBleErrorCode.connectionTimeout, 8);
    expect(received.single.errorCode, UniversalBleErrorCode.connectionTimeout);
    expect(received.single.nativeErrorCode, 8);
    expect(received.single.error, 'Connection Timeout');
  });

  test(
      'connectionUpdateStream matches a device id reported in a different case',
      () async {
    final platform = _MockPlatform();
    final event = platform.connectionUpdateStream(deviceId).first;
    platform.updateConnection(deviceId.toLowerCase(), false, 'x',
        UniversalBleErrorCode.connectionTimeout, 147);
    expect((await event).nativeErrorCode, 147);
  });
}
