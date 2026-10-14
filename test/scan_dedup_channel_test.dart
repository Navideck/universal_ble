// Guards that `UniversalBle.startScan`'s `skipDuplicates` always reaches the
// native scan config, even when the caller does not pass a `platformConfig`.
// Building the config with `platformConfig?.toUniversalScanConfig(...)` skipped
// it whenever `platformConfig` was null, silently disabling the iOS/macOS native
// lever for the documented `UniversalBle.startScan(skipDuplicates: true)` usage.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/src/universal_ble.g.dart';
import 'package:universal_ble/src/universal_ble_pigeon/universal_ble_pigeon_channel.dart';
import 'package:universal_ble/universal_ble.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = BasicMessageChannel<Object?>(
    'dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.startScan',
    UniversalBlePlatformChannel.pigeonChannelCodec,
  );

  UniversalScanConfig? capturedConfig;

  setUp(() {
    capturedConfig = null;
    // Windows does not request permissions in `_ensureInitialized`, and runs the
    // command immediately, keeping the test focused on the scan config.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    UniversalBle.setInstance(UniversalBlePigeonChannel.instance);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(channel, (message) async {
      final args = message! as List<Object?>;
      capturedConfig = args[1] as UniversalScanConfig?;
      return <Object?>[null];
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(channel, null);
  });

  test('skipDuplicates is forwarded without a platformConfig', () async {
    await UniversalBle.startScan(skipDuplicates: true);

    expect(capturedConfig, isNotNull);
    expect(capturedConfig!.skipDuplicates, isTrue);
  });

  test('skipDuplicates defaults to false without a platformConfig', () async {
    await UniversalBle.startScan();

    expect(capturedConfig, isNotNull);
    expect(capturedConfig!.skipDuplicates, isFalse);
  });

  test('skipDuplicates survives an unrelated platformConfig', () async {
    await UniversalBle.startScan(
      platformConfig: PlatformConfig(),
      skipDuplicates: true,
    );

    expect(capturedConfig, isNotNull);
    expect(capturedConfig!.android, isNull);
    expect(capturedConfig!.skipDuplicates, isTrue);
  });
}
