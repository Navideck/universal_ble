import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/src/universal_ble_pigeon/universal_ble_pigeon_channel.dart';
import 'package:universal_ble/universal_ble.dart';

import 'universal_ble_test_mock.dart';

/*
 * The GATT database may expose the same characteristic UUID in several
 * services (for example one Battery Service per battery), and each instance
 * notifies on its own attribute handle. A value is therefore identified by its
 * device, service and characteristic, not by device and characteristic alone
 * (#391).
 */
class _MockPlatform extends UniversalBlePlatformMock {}

void main() {
  // The Pigeon-boundary test builds UniversalBlePigeonChannel, whose
  // constructor registers the callback channel.
  TestWidgetsFlutterBinding.ensureInitialized();

  const deviceId = 'AA:BB:CC:DD:EE:FF';
  const charId = '7cdef16c-8a17-4465-90a9-6c901764b0b2';
  const serviceA = 'e7613013-2607-4819-9883-a9fbcf683bdd';
  const serviceB = 'eb3eeb51-a2ba-4d73-b251-60e355c5dbb7';

  late _MockPlatform platform;

  setUp(() {
    platform = _MockPlatform();
    UniversalBle.setInstance(platform);
  });

  BleCharacteristic characteristic(String serviceId) =>
      BleCharacteristic.withMetaData(
        deviceId: deviceId,
        serviceId: serviceId,
        uuid: charId,
        properties: CharacteristicProperty.values,
        descriptors: [],
      );

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  void emit(Uint8List value, {String? serviceId}) =>
      platform.updateCharacteristicValue(deviceId, charId, value, 1,
          serviceId: serviceId);

  test('a characteristic only receives the values of its own service',
      () async {
    final a = characteristic(serviceA);
    final b = characteristic(serviceB);
    final fromA = <Uint8List>[];
    final fromB = <Uint8List>[];
    final subscriptionA = a.onValueReceived.listen(fromA.add);
    final subscriptionB = b.onValueReceived.listen(fromB.add);
    addTearDown(() {
      subscriptionA.cancel();
      subscriptionB.cancel();
    });

    emit(Uint8List.fromList([11]), serviceId: serviceA);
    emit(Uint8List.fromList([22]), serviceId: serviceB);
    await settle();

    expect(fromA, [
      [11],
    ]);
    expect(fromB, [
      [22],
    ]);
  });

  test('the per-characteristic streams stay separated when interleaved',
      () async {
    final a = characteristic(serviceA);
    final b = characteristic(serviceB);
    final fromA = <Uint8List>[];
    final fromB = <Uint8List>[];
    final subscriptionA = a.onValueReceived.listen(fromA.add);
    final subscriptionB = b.onValueReceived.listen(fromB.add);
    addTearDown(() {
      subscriptionA.cancel();
      subscriptionB.cancel();
    });

    for (var i = 0; i < 5; i++) {
      emit(Uint8List.fromList([1, i]), serviceId: serviceA);
      emit(Uint8List.fromList([2, i]), serviceId: serviceB);
    }
    await settle();

    expect(fromA, [
      [1, 0],
      [1, 1],
      [1, 2],
      [1, 3],
      [1, 4],
    ]);
    expect(fromB, [
      [2, 0],
      [2, 1],
      [2, 2],
      [2, 3],
      [2, 4],
    ]);
  });

  test('characteristicValueStream keeps reporting every service by default',
      () async {
    final received = <Uint8List>[];
    final subscription =
        UniversalBle.characteristicValueStream(deviceId, charId)
            .listen(received.add);
    addTearDown(subscription.cancel);

    emit(Uint8List.fromList([11]), serviceId: serviceA);
    emit(Uint8List.fromList([22]), serviceId: serviceB);
    await settle();

    expect(received, [
      [11],
      [22],
    ]);
  });

  test('characteristicValueStream filters on the service when one is given',
      () async {
    final received = <Uint8List>[];
    final subscription = UniversalBle.characteristicValueStream(
      deviceId,
      charId,
      serviceId: serviceB,
    ).listen(received.add);
    addTearDown(subscription.cancel);

    emit(Uint8List.fromList([11]), serviceId: serviceA);
    emit(Uint8List.fromList([22]), serviceId: serviceB);
    await settle();

    expect(received, [
      [22],
    ]);
  });

  test('service ids match across UUID width and case', () async {
    final received = <Uint8List>[];
    final subscription = UniversalBle.characteristicValueStream(
      deviceId,
      charId,
      // Upper-case short form of 0000180d-0000-1000-8000-00805f9b34fb.
      serviceId: '180D',
    ).listen(received.add);
    addTearDown(subscription.cancel);

    emit(Uint8List.fromList([11]),
        serviceId: '0000180D-0000-1000-8000-00805F9B34FB');
    await settle();

    expect(received, [
      [11],
    ]);
  });

  test(
      'a value whose platform reports no service still reaches a filtered '
      'stream', () async {
    // A platform implementation that does not report the owning service cannot
    // be assumed to report another service's value, so it keeps working as
    // before instead of silently losing every value.
    final received = <Uint8List>[];
    final subscription = UniversalBle.characteristicValueStream(
      deviceId,
      charId,
      serviceId: serviceA,
    ).listen(received.add);
    addTearDown(subscription.cancel);

    emit(Uint8List.fromList([11]));
    await settle();

    expect(received, [
      [11],
    ]);
  });

  test('onValueChange carries the normalized service id', () async {
    final received = <BleCharacteristicValue>[];
    platform.onValueChange = received.add;

    emit(Uint8List.fromList([11]), serviceId: '180D');

    final update = received.single;
    expect(update.deviceId, deviceId.toLowerCase());
    expect(update.characteristicId, charId);
    expect(update.serviceId, '0000180d-0000-1000-8000-00805f9b34fb');
  });

  test('onValueChange reports a null service id when the platform has none',
      () async {
    final received = <BleCharacteristicValue>[];
    platform.onValueChange = received.add;

    emit(Uint8List.fromList([11]));

    expect(received.single.serviceId, isNull);
  });

  test('an unusable service id does not drop the value', () async {
    final received = <BleCharacteristicValue>[];
    platform.onValueChange = received.add;

    emit(Uint8List.fromList([11]), serviceId: 'not-a-uuid');

    expect(received.single.value, [11]);
    expect(received.single.serviceId, isNull);
  });

  test('the Pigeon callback forwards the owning service', () async {
    // The tests above push through updateCharacteristicValue, the platform-side
    // entry point. This one starts at the callback the native side invokes, so
    // dropping the service on the way in fails here rather than only in the
    // native tests.
    final pigeonChannel = UniversalBlePigeonChannel.instance;
    UniversalBle.setInstance(pigeonChannel);
    final received = <BleCharacteristicValue>[];
    pigeonChannel.onValueChange = received.add;
    addTearDown(() => pigeonChannel.onValueChange = null);

    await pigeonChannel.onValueChanged(
      deviceId,
      charId,
      serviceA,
      Uint8List.fromList([11]),
      1,
    );

    final update = received.single;
    expect(update.deviceId, deviceId.toLowerCase());
    expect(update.characteristicId, charId);
    expect(update.serviceId, serviceA);
    expect(update.value, [11]);
  });
}
