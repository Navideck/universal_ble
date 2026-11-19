import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/src/utils/cache_handler.dart';
import 'package:universal_ble/universal_ble.dart';

import 'universal_ble_test_mock.dart';

/*
 * A GATT database may expose the same characteristic UUID in several services
 * (one Battery Service per battery), and each instance has its own CCC
 * descriptor. Subscription state therefore has to follow the instance: keyed by
 * the characteristic UUID alone, unsubscribing service A reported service B as
 * unsubscribed while the peripheral was still notifying for it.
 */
class _MockPlatform extends UniversalBlePlatformMock {
  @override
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) async {}
}

void main() {
  const deviceId = 'AA:BB:CC:DD:EE:FF';
  const charId = '7cdef16c-8a17-4465-90a9-6c901764b0b2';
  const otherCharId = '5d5f5a4f-0b2b-4e0e-9a4e-4a0f6f2b1c33';
  const serviceA = 'e7613013-2607-4819-9883-a9fbcf683bdd';
  const serviceB = 'eb3eeb51-a2ba-4d73-b251-60e355c5dbb7';

  late _MockPlatform platform;

  setUp(() {
    platform = _MockPlatform();
    UniversalBle.setInstance(platform);
    CacheHandler.instance.resetDeviceCache(
      UniversalBle.canonicalDeviceId(deviceId),
    );
  });

  BleCharacteristic characteristic(String serviceId) =>
      BleCharacteristic.withMetaData(
        deviceId: deviceId,
        serviceId: serviceId,
        uuid: charId,
        properties: CharacteristicProperty.values,
        descriptors: [],
      );

  test('subscribing one service does not report the other as subscribed',
      () async {
    await UniversalBle.subscribeNotifications(deviceId, serviceA, charId);

    expect(
      UniversalBle.isSubscribed(deviceId, charId, serviceId: serviceA),
      isTrue,
    );
    expect(
      UniversalBle.isSubscribed(deviceId, charId, serviceId: serviceB),
      isFalse,
    );
    // A caller that only knows the UUID keeps the historical answer.
    expect(UniversalBle.isSubscribed(deviceId, charId), isTrue);
  });

  test('unsubscribing one service keeps the other subscribed', () async {
    await UniversalBle.subscribeNotifications(deviceId, serviceA, charId);
    await UniversalBle.subscribeIndications(deviceId, serviceB, charId);

    await UniversalBle.unsubscribe(deviceId, serviceA, charId);

    expect(
      UniversalBle.isSubscribed(deviceId, charId, serviceId: serviceA),
      isFalse,
    );
    expect(
      UniversalBle.isSubscribed(deviceId, charId, serviceId: serviceB),
      isTrue,
    );
    expect(UniversalBle.isSubscribed(deviceId, charId), isTrue);
    // Still subscribed somewhere, and reported once rather than per service.
    expect(UniversalBle.getSubscribedCharacteristics(deviceId), [charId]);
  });

  test('the per-characteristic flag follows its own service', () async {
    final fromA = characteristic(serviceA);
    final fromB = characteristic(serviceB);

    await fromA.notifications.subscribe();
    expect(fromA.isSubscribed, isTrue);
    expect(fromB.isSubscribed, isFalse);

    await fromB.notifications.subscribe();
    await fromA.notifications.unsubscribe();

    expect(fromA.isSubscribed, isFalse);
    expect(fromB.isSubscribed, isTrue);
  });

  test('getSubscribedCharacteristics filters by service', () async {
    await UniversalBle.subscribeNotifications(deviceId, serviceA, charId);
    await UniversalBle.subscribeNotifications(deviceId, serviceB, otherCharId);

    expect(
      UniversalBle.getSubscribedCharacteristics(deviceId, serviceId: serviceA),
      [charId],
    );
    expect(
      UniversalBle.getSubscribedCharacteristics(deviceId, serviceId: serviceB),
      [otherCharId],
    );
    expect(
      UniversalBle.getSubscribedCharacteristics(deviceId),
      containsAll([charId, otherCharId]),
    );
  });

  test('service and characteristic ids match across UUID width and case',
      () async {
    // Upper-case short form of 0000180d-… and 00002a37-….
    await UniversalBle.subscribeNotifications(deviceId, '180D', '2A37');

    expect(
      UniversalBle.isSubscribed(
        deviceId,
        '00002a37-0000-1000-8000-00805f9b34fb',
        serviceId: '0000180d-0000-1000-8000-00805f9b34fb',
      ),
      isTrue,
    );
    expect(
      UniversalBle.isSubscribed(deviceId, '2a37', serviceId: '180d'),
      isTrue,
    );
    expect(
      UniversalBle.getSubscribedCharacteristics(deviceId, serviceId: '180D'),
      ['00002a37-0000-1000-8000-00805f9b34fb'],
    );
  });

  test('unsubscribing a service that was never subscribed changes nothing',
      () async {
    await UniversalBle.subscribeNotifications(deviceId, serviceA, charId);

    await UniversalBle.unsubscribe(deviceId, serviceB, charId);

    expect(
      UniversalBle.isSubscribed(deviceId, charId, serviceId: serviceA),
      isTrue,
    );
    expect(
      UniversalBle.isSubscribed(deviceId, charId, serviceId: serviceB),
      isFalse,
    );
  });

  test('disconnecting clears every service', () async {
    await UniversalBle.subscribeNotifications(deviceId, serviceA, charId);
    await UniversalBle.subscribeNotifications(deviceId, serviceB, charId);

    platform.updateConnection(deviceId, false);

    expect(UniversalBle.getSubscribedCharacteristics(deviceId), isEmpty);
    expect(
      UniversalBle.isSubscribed(deviceId, charId, serviceId: serviceA),
      isFalse,
    );
    expect(
      UniversalBle.isSubscribed(deviceId, charId, serviceId: serviceB),
      isFalse,
    );
  });

  test('an unusable service id answers false instead of throwing', () {
    expect(
      UniversalBle.isSubscribed(deviceId, charId, serviceId: 'not-a-uuid'),
      isFalse,
    );
    expect(
      UniversalBle.getSubscribedCharacteristics(deviceId, serviceId: 'nope'),
      isEmpty,
    );
  });
}
