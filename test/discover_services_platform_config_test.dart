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
}
