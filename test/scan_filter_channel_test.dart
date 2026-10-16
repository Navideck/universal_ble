// Guards that `ScanFilter.withServiceData` reaches the platform scan filter in the
// canonical 128-bit lowercase form the native filters compare against, whatever
// casing or short form the caller used (#57).
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

  UniversalScanFilter? capturedFilter;

  setUp(() {
    capturedFilter = null;
    // Windows does not request permissions in `_ensureInitialized`, and runs the
    // command immediately, keeping the test focused on the scan filter.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    UniversalBle.setInstance(UniversalBlePigeonChannel.instance);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(channel, (message) async {
      final args = message! as List<Object?>;
      capturedFilter = args[0] as UniversalScanFilter?;
      return <Object?>[null];
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(channel, null);
  });

  test('withServiceData is forwarded in full 128-bit lowercase form', () async {
    await UniversalBle.startScan(
      scanFilter: ScanFilter(withServiceData: ['181A']),
    );

    expect(capturedFilter, isNotNull);
    expect(capturedFilter!.withServiceData, [
      '0000181a-0000-1000-8000-00805f9b34fb',
    ]);
  });

  test('withServiceData stays empty when the caller does not set it', () async {
    await UniversalBle.startScan(
      scanFilter: ScanFilter(withServices: ['180d']),
    );

    expect(capturedFilter, isNotNull);
    expect(capturedFilter!.withServiceData, isEmpty);
    expect(capturedFilter!.withServices, [
      '0000180d-0000-1000-8000-00805f9b34fb',
    ]);
  });
}
