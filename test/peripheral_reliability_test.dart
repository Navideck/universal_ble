import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/src/universal_ble.g.dart';
import 'package:universal_ble/src/universal_ble_pigeon/universal_ble_peripheral_pigeon.dart';
import 'package:universal_ble/universal_ble.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const prefix = 'dev.flutter.pigeon.universal_ble.';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  void mock(String method, Future<Object?> Function(Object?) handler) {
    messenger.setMockDecodedMessageHandler<Object?>(
        BasicMessageChannel<Object?>(
            '$prefix$method', UniversalBlePeripheralChannel.pigeonChannelCodec),
        handler);
  }

  tearDown(() {
    UniversalBlePeripheralPigeon.instance.dispose();
    debugDefaultTargetPlatformOverride = null;
    for (final method in [
      'UniversalBlePeripheralChannel.clearPendingNotifications',
      'UniversalBlePeripheralChannel.addService',
      'UniversalBleDarwinPeripheralChannel.configureRestoration'
    ]) {
      messenger.setMockDecodedMessageHandler<Object?>(
          BasicMessageChannel<Object?>('$prefix$method',
              UniversalBlePeripheralChannel.pigeonChannelCodec),
          null);
    }
  });

  final model = BlePeripheralCharacteristic(
      uuid: '2a4d',
      properties: [
        CharacteristicProperty.read,
        CharacteristicProperty.notify
      ],
      permissions: [PeripheralAttributePermission.readEncryptionRequired],
      instanceId: 'consumerInput',
      requireEncryptedNotifications: true);

  test('encrypted notifications survive JSON', () {
    final restored = BlePeripheralCharacteristic.fromJson(model.toJson());
    expect(restored.requireEncryptedNotifications, isTrue);
    expect(restored.instanceId, 'consumerInput');
    expect(
        BlePeripheralCharacteristic.fromJson({'uuid': '2a4d'})
            .requireEncryptedNotifications,
        isFalse);
  });

  // Native channel enums use Int64 accessors unavailable in JavaScript.
  test('encrypted notifications survive the native Pigeon codec', () {
    final native = model.toPeripheralCharacteristic();
    final codec = UniversalBlePeripheralChannel.pigeonChannelCodec;
    final decoded = codec.decodeMessage(codec.encodeMessage(native))
        as PeripheralCharacteristic;
    expect(decoded.requireEncryptedNotifications, isTrue);
    expect(decoded.instanceId, 'consumerInput');
  }, skip: kIsWeb);

  test('clearing notifications accepts any MAC/Apple UUID casing', () async {
    final received = <String?>[];
    mock('UniversalBlePeripheralChannel.clearPendingNotifications',
        (message) async {
      received.add((message as List)[0] as String?);
      return <Object?>[null];
    });
    for (final id in [
      'aa:bb:cc:dd:ee:ff',
      'Aa:Bb:Cc:Dd:Ee:Ff',
      'abcdef01-2345-6789-abcd-ef0123456789',
      'ABCDEF01-2345-6789-ABCD-EF0123456789'
    ]) {
      await UniversalBlePeripheralPigeon.instance.clearPendingNotifications(id);
    }
    await UniversalBlePeripheralPigeon.instance.clearPendingNotifications(null);
    expect(received, [
      'AA:BB:CC:DD:EE:FF',
      'AA:BB:CC:DD:EE:FF',
      'ABCDEF01-2345-6789-ABCD-EF0123456789',
      'ABCDEF01-2345-6789-ABCD-EF0123456789',
      null
    ]);
  });

  test('Apple restoration uses a separate optional channel', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    String? identifier;
    mock('UniversalBleDarwinPeripheralChannel.configureRestoration',
        (message) async {
      identifier = (message as List)[0] as String;
      return <Object?>[null];
    });
    await UniversalBlePeripheralPigeon.instance
        .configureRestoration('test.peripheral');
    if (kIsWeb) {
      // Apple platform overrides must not enable native restoration on Web.
      await UniversalBlePeripheralPigeon.instance.configureRestoration(' ');
      expect(identifier, isNull);
      return;
    }
    expect(identifier, 'test.peripheral');
    await expectLater(
        UniversalBlePeripheralPigeon.instance.configureRestoration(' '),
        throwsArgumentError);
  });

  test('failed service registration surfaces error and allows retry', () async {
    final platform = UniversalBlePeripheralPigeon.instance;
    var attempts = 0;
    mock('UniversalBlePeripheralChannel.addService', (message) async {
      final service = (message as List)[0] as PeripheralService;
      scheduleMicrotask(() => platform.onServiceAdded(
          service.uuid, ++attempts == 1 ? 'denied' : null));
      return <Object?>[null];
    });
    final service =
        PeripheralService(uuid: '1812', primary: true, characteristics: []);
    await expectLater(
        platform.addService(service), throwsA(isA<PlatformException>()));
    await platform.addService(service);
    expect(attempts, 2);
  });
}
