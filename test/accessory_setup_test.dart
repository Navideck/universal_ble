import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';

import 'universal_ble_test_mock.dart';

class _DevicePickerPlatform extends UniversalBlePlatformMock {
  PlatformConfig? receivedConfig;
  ScanFilter? receivedFilter;

  @override
  Future<BleDevice> requestDevice({
    ScanFilter? scanFilter,
    PlatformConfig? platformConfig,
  }) async {
    receivedFilter = scanFilter;
    receivedConfig = platformConfig;
    return BleDevice(deviceId: 'picked-device', name: 'Picked device');
  }
}

void main() {
  test('requestDevice returns the device selected by the native picker',
      () async {
    final platform = _DevicePickerPlatform();
    final options = AppleAccessorySetupOptions(
      displayName: 'My device',
      imageAsset: 'my_device',
      serviceUuid: '180D',
    );
    UniversalBle.setInstance(platform);

    final device = await UniversalBle.requestDevice(
      scanFilter: ScanFilter(withServices: ['180D']),
      platformConfig: PlatformConfig(apple: options),
    );

    expect(device.deviceId, 'picked-device');
    expect(device.name, 'Picked device');
    expect(platform.receivedConfig?.apple, same(options));
    expect(platform.receivedFilter?.withServices, ['180D']);
  });

  test('requestDevice without platformConfig forwards null', () async {
    final platform = _DevicePickerPlatform();
    UniversalBle.setInstance(platform);

    await UniversalBle.requestDevice();

    expect(platform.receivedConfig, isNull);
    expect(platform.receivedFilter, isNull);
  });
}
