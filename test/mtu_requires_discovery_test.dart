// `requestMtu` discovers the device's services on demand on the platforms where
// the MTU is only meaningful once they are known. It runs before the MTU command
// is queued, so it must not deadlock the per-device queue. Web has no MTU API, so
// these tests are VM-only.
@TestOn('vm')
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/src/utils/cache_handler.dart';
import 'package:universal_ble/universal_ble.dart';

import 'universal_ble_test_mock.dart';

class _MtuPlatformMock extends UniversalBlePlatformMock {
  final List<String> mtuRequests = [];
  final List<String> discoverRequests = [];
  bool failDiscovery = false;

  @override
  Future<List<BleService>> discoverServices(
    String deviceId,
    bool withDescriptors, {
    DiscoverServicesPlatformConfig? platformConfig,
  }) async {
    discoverRequests.add(deviceId);
    if (failDiscovery) {
      throw UniversalBleException(
        code: UniversalBleErrorCode.failed,
        message: 'discovery failed',
      );
    }
    return const [];
  }

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) async {
    mtuRequests.add(deviceId);
    return 247;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const deviceId = 'AA:BB:CC:DD:EE:01';
  final canonicalId = deviceId.toLowerCase();

  late _MtuPlatformMock platform;

  setUp(() {
    platform = _MtuPlatformMock();
    UniversalBle.setInstance(platform);
    CacheHandler.instance.resetDeviceCache(canonicalId);
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    CacheHandler.instance.resetDeviceCache(canonicalId);
  });

  group('discoverServices on demand', () {
    for (final targetPlatform in [
      TargetPlatform.iOS,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    ]) {
      test('on $targetPlatform before discovery', () async {
        debugDefaultTargetPlatformOverride = targetPlatform;

        expect(await UniversalBle.requestMtu(deviceId, 247), 247);
        expect(platform.discoverRequests, [deviceId]);
        expect(platform.mtuRequests, [deviceId]);
      });
    }
  });

  group('does not discover', () {
    for (final targetPlatform in [
      TargetPlatform.android,
      TargetPlatform.windows,
    ]) {
      test('on $targetPlatform', () async {
        debugDefaultTargetPlatformOverride = targetPlatform;

        expect(await UniversalBle.requestMtu(deviceId, 247), 247);
        expect(platform.discoverRequests, isEmpty);
        expect(platform.mtuRequests, [deviceId]);
      });
    }
  });

  test('skips discovery when discoverServices already ran', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    await UniversalBle.discoverServices(deviceId);

    expect(await UniversalBle.requestMtu(deviceId, 247), 247);
    expect(platform.discoverRequests, [deviceId]); // only the explicit call
  });

  test('a failed on-demand discovery still attempts the MTU', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    platform.failDiscovery = true;

    expect(await UniversalBle.requestMtu(deviceId, 247), 247);
    expect(platform.discoverRequests, [deviceId]);
    expect(platform.mtuRequests, [deviceId]);
  });

  test('matches discovery and request across device id casing', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    await UniversalBle.discoverServices(deviceId.toUpperCase());

    expect(await UniversalBle.requestMtu(deviceId.toLowerCase(), 247), 247);
    expect(platform.discoverRequests, [deviceId.toUpperCase()]);
  });

  test('a disconnect clears the discovery state', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    expect(await UniversalBle.requestMtu(deviceId, 247), 247);
    expect(platform.discoverRequests.length, 1);

    // A disconnect clears the per-device cache (see
    // `UniversalBlePlatform.updateConnection`).
    CacheHandler.instance.resetDeviceCache(canonicalId);

    expect(await UniversalBle.requestMtu(deviceId, 247), 247);
    expect(platform.discoverRequests.length, 2);
  });
}
