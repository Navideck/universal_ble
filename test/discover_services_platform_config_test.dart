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

void main() {
  const deviceId = 'AA:BB:CC:DD:EE:FF';

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
}
