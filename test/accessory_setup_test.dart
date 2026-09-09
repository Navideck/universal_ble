import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';

import 'universal_ble_test_mock.dart';

class _AccessorySetupPlatform extends UniversalBlePlatformMock {
  AppleAccessorySetupOptions? receivedOptions;
  String? connectedDeviceId;

  @override
  Future<String> setupAccessory(AppleAccessorySetupOptions options) async {
    receivedOptions = options;
    return 'selected-device';
  }

  @override
  Future<void> connect(
    String deviceId, {
    bool autoConnect = false,
    Duration? connectionTimeout,
    ConnectionPlatformConfig? platformConfig,
  }) async {
    connectedDeviceId = deviceId;
    updateConnection(deviceId, true);
  }
}

void main() {
  test('connectAccessory connects the device selected by the picker', () async {
    final platform = _AccessorySetupPlatform();
    final options = AppleAccessorySetupOptions(
      displayName: 'My device',
      imageAsset: 'my_device',
      serviceUuid: '180D',
    );
    UniversalBle.setInstance(platform);

    final deviceId = await UniversalBle.connectAccessory(options);

    expect(deviceId, 'selected-device');
    expect(platform.connectedDeviceId, deviceId);
    expect(platform.receivedOptions, same(options));
  });
}
