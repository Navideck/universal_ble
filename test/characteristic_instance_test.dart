import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';

class _FakePeripheralPlatform extends UniversalBlePeripheralUnsupported {
  String? lastCharacteristicId;
  String? lastInstanceId;
  Uint8List? lastValue;
  String? lastSubscribedCharacteristicId;
  String? lastSubscribedInstanceId;

  @override
  void dispose() {}

  @override
  Future<void> updateCharacteristicValue({
    required String characteristicId,
    String? instanceId,
    required Uint8List value,
    String? deviceId,
  }) async {
    lastCharacteristicId = characteristicId;
    lastInstanceId = instanceId;
    lastValue = value;
  }

  @override
  Future<List<String>> getSubscribedClients(
    String characteristicId, {
    String? instanceId,
  }) async {
    lastSubscribedCharacteristicId = characteristicId;
    lastSubscribedInstanceId = instanceId;
    return const ['aa:bb:cc:dd:ee:ff'];
  }

  void emitSubscription({
    required String characteristicId,
    String? instanceId,
    required bool isSubscribed,
  }) {
    updateCharacteristicSubscription(
      BlePeripheralCharacteristicSubscriptionChanged(
        deviceId: 'AA:BB:CC:DD:EE:FF',
        characteristicId: characteristicId,
        instanceId: instanceId,
        isSubscribed: isSubscribed,
        name: null,
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const reportUuid = '00002a4d-0000-1000-8000-00805f9b34fb';

  test('updateCharacteristicValue forwards the characteristic instance id',
      () async {
    final platform = _FakePeripheralPlatform();
    UniversalBlePeripheral.setInstance(platform);

    await UniversalBlePeripheral.updateCharacteristicValue(
      characteristicId: reportUuid,
      instanceId: 'consumerInput',
      value: Uint8List.fromList([0xE9, 0x00]),
      deviceId: 'AA:BB:CC:DD:EE:FF',
    );

    expect(platform.lastCharacteristicId, reportUuid);
    expect(platform.lastInstanceId, 'consumerInput');
    expect(platform.lastValue, [0xE9, 0x00]);
  });

  test('getSubscribedClients forwards the characteristic instance id',
      () async {
    final platform = _FakePeripheralPlatform();
    UniversalBlePeripheral.setInstance(platform);

    final clients = await UniversalBlePeripheral.getSubscribedClients(
      reportUuid,
      instanceId: 'consumerInput',
    );

    expect(platform.lastSubscribedCharacteristicId, reportUuid);
    expect(platform.lastSubscribedInstanceId, 'consumerInput');
    expect(clients, ['aa:bb:cc:dd:ee:ff']);
  });

  test('subscription events keep the instance identity', () async {
    final platform = _FakePeripheralPlatform();
    UniversalBlePeripheral.setInstance(platform);

    final event = platform.characteristicSubscriptionStream.first;
    platform.emitSubscription(
      characteristicId: reportUuid,
      instanceId: 'consumerInput',
      isSubscribed: true,
    );

    final received = await event;
    expect(received.characteristicId, reportUuid);
    expect(received.instanceId, 'consumerInput');
    expect(received.isSubscribed, isTrue);
    expect(received.deviceId, 'aa:bb:cc:dd:ee:ff');
  });

  test('UUID-only callers keep an empty instance id', () async {
    final platform = _FakePeripheralPlatform();
    UniversalBlePeripheral.setInstance(platform);

    await UniversalBlePeripheral.updateCharacteristicValue(
      characteristicId: reportUuid,
      value: Uint8List.fromList([1]),
    );

    expect(platform.lastInstanceId, isNull);
  });
}
