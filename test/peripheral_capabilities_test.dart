// These tests exercise the native Pigeon backend; web uses a separate backend.
@TestOn('vm')
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/src/universal_ble.g.dart';
import 'package:universal_ble/src/universal_ble_pigeon/universal_ble_peripheral_pigeon.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = BasicMessageChannel<Object?>(
    'dev.flutter.pigeon.universal_ble.UniversalBlePeripheralChannel.getReadinessState',
    UniversalBlePeripheralChannel.pigeonChannelCodec,
  );
  var readiness = PeripheralReadinessState.ready;
  setUp(() {
    readiness = PeripheralReadinessState.ready;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(
            channel, (_) async => [readiness]);
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(channel, null);
  });
  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.macOS,
    TargetPlatform.windows,
  ]) {
    test('manufacturer capability on $platform', () async {
      debugDefaultTargetPlatformOverride = platform;
      final capabilities =
          await UniversalBlePeripheralPigeon.instance.getCapabilities();
      expect(
          capabilities.supportsManufacturerDataInAdvertisement,
          platform == TargetPlatform.android ||
              platform == TargetPlatform.windows);
      readiness = PeripheralReadinessState.unsupported;
      expect(
          (await UniversalBlePeripheralPigeon.instance.getCapabilities())
              .supportsManufacturerDataInAdvertisement,
          isFalse);
    });
  }
}
