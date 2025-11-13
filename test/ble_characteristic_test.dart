import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';
import 'universal_ble_test_mock.dart';

String serviceId = "180a";
String characteristicId = "202a";
String mockDeviceId = "mock_id";
BleCharacteristic mockBleCharacteristic = BleCharacteristic.withMetaData(
  deviceId: mockDeviceId,
  serviceId: serviceId,
  uuid: characteristicId,
  properties: CharacteristicProperty.values,
);
BleService mockBleService = BleService(serviceId, [mockBleCharacteristic]);

void main() {
  late UniversalBlePlatform platform;
  setUp(() {
    platform = _UniversalBleMock();
    UniversalBle.setInstance(platform);
  });

  group('BleCharacteristic Tests', () {
    test("DiscoverServices test", () async {
      debugPrint("Discovering services");
      List<BleService> services =
          await UniversalBle.discoverServices(mockDeviceId);
      expect(services.length, 1);

      BleService service = services.first;
      expect(BleUuidParser.compareStrings(service.uuid, serviceId), true);
      expect(service.characteristics.length, 1);

      BleCharacteristic characteristic = service.characteristics.first;
      expect(
        BleUuidParser.compareStrings(characteristic.uuid, characteristicId),
        true,
      );
      expect(characteristic.metaData?.deviceId, mockDeviceId);
      expect(
        BleUuidParser.compareStrings(
          characteristic.metaData!.serviceId,
          serviceId,
        ),
        true,
      );
    });

    test("Subscription Test", () async {
      BleCharacteristic characteristic = mockBleCharacteristic;

      debugPrint("Subscribing to char");
      await characteristic.notifications.subscribe();

      bool gotEvent = false;
      var subscription = characteristic.notifications.listen((data) {
        debugPrint("Received CharValue: $data");
        gotEvent = true;
      });

      await Future.delayed(Duration(seconds: 1));
      await characteristic.notifications.unsubscribe();
      debugPrint("Unsubscribed from char");

      subscription.cancel();
      expect(gotEvent, true);
    });
  });

  test("Write/Read Value Test", () async {
    BleCharacteristic characteristic = mockBleCharacteristic;
    Uint8List charValue = Uint8List.fromList([0x01, 0x02]);
    await characteristic.write(charValue);
    debugPrint("Write Succeed");

    var readResult = await characteristic.read();
    debugPrint("Read Succeed");
    expect(readResult, charValue);
  });
}

class _UniversalBleMock extends UniversalBlePlatformMock {
  Timer? notifierTimer;
  Uint8List? charValue;

  @override
  Future<List<BleService>> discoverServices(String deviceId) async {
    return <BleService>[mockBleService];
  }

  @override
  Future<void> setNotifiable(String deviceId, String service,
      String characteristic, BleInputProperty bleInputProperty) async {
    if (bleInputProperty == BleInputProperty.disabled) {
      notifierTimer?.cancel();
      notifierTimer = null;
      return;
    }

    notifierTimer ??= Timer.periodic(Duration(milliseconds: 500), (timer) {
      updateCharacteristicValue(
        deviceId,
        characteristic,
        Uint8List.fromList([1, 2, 3]),
      );
    });
  }

  @override
  Future<void> writeValue(
      String deviceId,
      String service,
      String characteristic,
      Uint8List value,
      BleOutputProperty bleOutputProperty) async {
    charValue = value;
  }

  @override
  Future<Uint8List> readValue(
      String deviceId, String service, String characteristic,
      {Duration? timeout}) async {
    return charValue ?? Uint8List(0);
  }

  @override
  Future<void> requestPermissions({bool withAndroidFineLocation = false}) {
    throw UnimplementedError();
  }
}
