import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';

import 'universal_ble_test_mock.dart';

class _CapturingPlatform extends UniversalBlePlatformMock {
  DiscoverServicesPlatformConfig? lastPlatformConfig;
  bool? lastWithDescriptors;

  @override
  Future<List<BleService>> discoverServices(
    String deviceId,
    bool withDescriptors, {
    DiscoverServicesPlatformConfig? platformConfig,
  }) async {
    lastWithDescriptors = withDescriptors;
    lastPlatformConfig = platformConfig;
    return const <BleService>[];
  }
}

/// Answers each discovery after [delay], counting the discoveries it ran.
class _SlowPlatform extends UniversalBlePlatformMock {
  _SlowPlatform(this.delay);

  final Duration delay;
  int discoveries = 0;

  @override
  Future<List<BleService>> discoverServices(
    String deviceId,
    bool withDescriptors, {
    DiscoverServicesPlatformConfig? platformConfig,
  }) async {
    discoveries++;
    await Future<void>.delayed(delay);
    return const <BleService>[];
  }
}

void main() {
  const deviceId = 'AA:BB:CC:DD:EE:FF';

  tearDown(() => UniversalBle.timeout = const Duration(seconds: 10));

  test('discoverServices forwards platformConfig to the platform', () async {
    final platform = _CapturingPlatform();
    UniversalBle.setInstance(platform);
    final config = DiscoverServicesPlatformConfig(
      android: AndroidDiscoverServicesOptions(clearGattCache: true),
    );
    await UniversalBle.discoverServices(deviceId, platformConfig: config);
    expect(platform.lastPlatformConfig, same(config));
    expect(platform.lastPlatformConfig?.android?.clearGattCache, isTrue);
    expect(platform.lastWithDescriptors, isFalse);
  });

  test('discoverServices without platformConfig passes null', () async {
    final platform = _CapturingPlatform();
    UniversalBle.setInstance(platform);
    await UniversalBle.discoverServices(deviceId, withDescriptors: true);
    expect(platform.lastPlatformConfig, isNull);
    expect(platform.lastWithDescriptors, isTrue);
  });

  test(
    'discoverServices passes its timeout to Apple as the native discovery timeout',
    () async {
      final platform = _CapturingPlatform();
      UniversalBle.setInstance(platform);
      await UniversalBle.discoverServices(
        deviceId,
        timeout: const Duration(seconds: 30),
      );
      expect(platform.lastPlatformConfig?.apple?.timeoutMillis, 30000);
      expect(platform.lastPlatformConfig?.android, isNull);
    },
  );

  test('the timeout keeps the Android options it was given', () async {
    final platform = _CapturingPlatform();
    UniversalBle.setInstance(platform);
    await UniversalBle.discoverServices(
      deviceId,
      timeout: const Duration(seconds: 30),
      platformConfig: DiscoverServicesPlatformConfig(
        android: AndroidDiscoverServicesOptions(clearGattCache: true),
      ),
    );
    expect(platform.lastPlatformConfig?.apple?.timeoutMillis, 30000);
    expect(platform.lastPlatformConfig?.android?.clearGattCache, isTrue);
  });

  test('an Apple timeout set by the caller wins over the timeout', () async {
    final platform = _CapturingPlatform();
    UniversalBle.setInstance(platform);
    final config = DiscoverServicesPlatformConfig(
      apple: AppleDiscoverServicesOptions(timeoutMillis: 45000),
    );
    await UniversalBle.discoverServices(
      deviceId,
      timeout: const Duration(seconds: 30),
      platformConfig: config,
    );
    expect(platform.lastPlatformConfig, same(config));
    expect(platform.lastPlatformConfig?.apple?.timeoutMillis, 45000);
  });

  group('an Apple timeout given without a timeout', () {
    // The command queue's default stands in for the 10 s it has in practice.
    setUp(() => UniversalBle.timeout = const Duration(milliseconds: 50));

    test('bounds the whole call', () async {
      UniversalBle.setInstance(_SlowPlatform(const Duration(milliseconds: 150)));
      final services = await UniversalBle.discoverServices(
        deviceId,
        platformConfig: DiscoverServicesPlatformConfig(
          apple: AppleDiscoverServicesOptions(timeoutMillis: 1000),
        ),
      );
      expect(services, isEmpty);
    });

    test('leaves the default when it is not positive', () async {
      UniversalBle.setInstance(_SlowPlatform(const Duration(milliseconds: 150)));
      await expectLater(
        UniversalBle.discoverServices(
          deviceId,
          platformConfig: DiscoverServicesPlatformConfig(
            apple: AppleDiscoverServicesOptions(timeoutMillis: 0),
          ),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });
  });

  test('calls that differ only in their timeout share one discovery', () async {
    final platform = _SlowPlatform(const Duration(milliseconds: 20));
    UniversalBle.setInstance(platform);
    await Future.wait([
      UniversalBle.discoverServices(deviceId),
      UniversalBle.discoverServices(
        deviceId,
        timeout: const Duration(seconds: 30),
      ),
      UniversalBle.discoverServices(
        deviceId,
        platformConfig: DiscoverServicesPlatformConfig(
          apple: AppleDiscoverServicesOptions(timeoutMillis: 45000),
        ),
      ),
    ]);
    expect(platform.discoveries, 1);
  });

  test('calls with other Android options still run their own', () async {
    final platform = _SlowPlatform(const Duration(milliseconds: 20));
    UniversalBle.setInstance(platform);
    await Future.wait([
      UniversalBle.discoverServices(
        deviceId,
        timeout: const Duration(seconds: 30),
      ),
      UniversalBle.discoverServices(
        deviceId,
        platformConfig: DiscoverServicesPlatformConfig(
          android: AndroidDiscoverServicesOptions(clearGattCache: true),
        ),
      ),
    ]);
    expect(platform.discoveries, 2);
  });
}
