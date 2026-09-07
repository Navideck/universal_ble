import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:universal_ble_hil/src/hil_peripheral.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('UniversalBle HIL', () {
    late HilPeripheral peripheral;
    var setupSucceeded = false;

    setUp(() async {
      setupSucceeded = false;
      await UniversalBle.requestPermissions();
      peripheral = await HilPeripheral.open();
      setupSucceeded = true;
    });

    tearDown(() async {
      UniversalBle.queueType = QueueType.global;
      UniversalBle.onScanResult = null;
      UniversalBle.onConnectionChange = null;
      UniversalBle.onValueChange = null;
      if (setupSucceeded) {
        setupSucceeded = false;
        await peripheral.close();
      }
    });

    testWidgets('discovers the named peripheral and advertised service', (
      _,
    ) async {
      expect(peripheral.device.name, HilPeripheral.deviceName);
      expect(
        peripheral.device.services,
        anyElement(
          predicate<String>(
            (uuid) => BleUuidParser.compareStrings(uuid, HilUuid.service),
          ),
        ),
      );
      expect(peripheral.device.rssi, isNotNull);
    });

    testWidgets('performs a fresh scan through both result APIs', (_) async {
      await UniversalBle.disconnect(
        peripheral.deviceId,
        timeout: HilPeripheral.operationTimeout,
      );

      final streamResult = Completer<BleDevice>();
      final callbackResult = Completer<BleDevice>();
      final subscription = UniversalBle.scanStream.listen((device) {
        if (device.name == HilPeripheral.deviceName &&
            !streamResult.isCompleted) {
          streamResult.complete(device);
        }
      });
      UniversalBle.onScanResult = (device) {
        if (device.name == HilPeripheral.deviceName &&
            !callbackResult.isCompleted) {
          callbackResult.complete(device);
        }
      };

      try {
        await UniversalBle.startScan(
          scanFilter: ScanFilter(
            withServices: const [HilUuid.service],
            withNamePrefix: const [HilPeripheral.deviceName],
          ),
        );
        await _eventually(UniversalBle.isScanning);

        final results = await Future.wait([
          streamResult.future,
          callbackResult.future,
        ]).timeout(HilPeripheral.scanTimeout);
        for (final device in results) {
          expect(device.name, HilPeripheral.deviceName);
          expect(device.rssi, isNotNull);
          expect(device.services, anyElement(_isHilService));
        }
      } finally {
        await UniversalBle.stopScan();
        await subscription.cancel();
      }
      expect(await UniversalBle.isScanning(), isFalse);
    });

    testWidgets('discovers the complete characteristic contract', (_) async {
      final services = await peripheral.discover();
      final service = services.singleWhere(
        (service) =>
            BleUuidParser.compareStrings(service.uuid, HilUuid.service),
      );

      expect(
        service.characteristics.map((characteristic) => characteristic.uuid),
        unorderedEquals(<String>[
          HilUuid.control,
          HilUuid.state,
          HilUuid.read,
          HilUuid.write,
          HilUuid.writeWithoutResponse,
          HilUuid.writeMirror,
          HilUuid.writeWithoutResponseMirror,
          HilUuid.notify,
          HilUuid.indicate,
          HilUuid.multi,
        ]),
      );
      _expectProperties(service, HilUuid.control, [
        CharacteristicProperty.write,
      ]);
      _expectProperties(service, HilUuid.state, [CharacteristicProperty.read]);
      _expectProperties(service, HilUuid.read, [CharacteristicProperty.read]);
      _expectProperties(service, HilUuid.write, [CharacteristicProperty.write]);
      _expectProperties(service, HilUuid.writeWithoutResponse, [
        CharacteristicProperty.writeWithoutResponse,
      ]);
      _expectProperties(service, HilUuid.writeMirror, [
        CharacteristicProperty.read,
      ]);
      _expectProperties(service, HilUuid.writeWithoutResponseMirror, [
        CharacteristicProperty.read,
      ]);
      _expectProperties(service, HilUuid.notify, [
        CharacteristicProperty.notify,
      ]);
      _expectProperties(service, HilUuid.indicate, [
        CharacteristicProperty.indicate,
      ]);
      _expectProperties(service, HilUuid.multi, [
        CharacteristicProperty.read,
        CharacteristicProperty.write,
        CharacteristicProperty.notify,
      ]);

      final readCharacteristic = _characteristic(service, HilUuid.read);
      expect(
        readCharacteristic.descriptors.map((descriptor) => descriptor.uuid),
        containsAll(<String>[
          BleUuidParser.string('2901'),
          BleUuidParser.string(HilUuid.descriptor),
        ]),
      );
    });

    testWidgets('honors descriptor discovery mode', (_) async {
      final withoutDescriptors = await peripheral.discover(
        withDescriptors: false,
      );
      expect(
        withoutDescriptors
            .expand((service) => service.characteristics)
            .expand((characteristic) => characteristic.descriptors),
        isEmpty,
      );

      final withDescriptors = await peripheral.discover();
      final service = withDescriptors.singleWhere(
        (service) => _isHilService(service.uuid),
      );
      expect(_characteristic(service, HilUuid.read).descriptors, isNotEmpty);
    });

    testWidgets('reads the deterministic default and a configured value', (
      _,
    ) async {
      expect(utf8.decode(await peripheral.read(HilUuid.read)), 'HIL-READ-V1');

      final expected = Uint8List.fromList(
        List<int>.generate(200, (index) => index),
      );
      await peripheral.setReadValue(expected);

      expect(await peripheral.read(HilUuid.read), orderedEquals(expected));
    });

    testWidgets('reads and writes an exact descriptor value', (_) async {
      expect(
        utf8.decode(await peripheral.readDescriptor()),
        'HIL-DESCRIPTOR-V1',
      );

      final expected = Uint8List.fromList([0x00, 0x7f, 0x80, 0xff]);
      await peripheral.writeDescriptor(expected);

      expect(await peripheral.readDescriptor(), orderedEquals(expected));
    });

    testWidgets(
      'writes with response and exposes the exact value and counter',
      (_) async {
        final expected = List<int>.generate(200, (index) => 255 - index);

        await peripheral.write(HilUuid.write, expected);

        expect(
          await peripheral.read(HilUuid.writeMirror),
          orderedEquals(expected),
        );
        expect((await peripheral.readState()).writesWithResponse, 1);
      },
    );

    testWidgets(
      'writes without response and exposes the exact value and counter',
      (_) async {
        final expected = List<int>.generate(120, (index) => index ^ 0x5a);

        await peripheral.write(
          HilUuid.writeWithoutResponse,
          expected,
          withoutResponse: true,
        );
        await _eventually(
          () async => listEquals(
            await peripheral.read(HilUuid.writeWithoutResponseMirror),
            expected,
          ),
        );

        expect((await peripheral.readState()).writesWithoutResponse, 1);
      },
    );

    testWidgets('uses every operation of a multi-property characteristic', (
      _,
    ) async {
      final expected = Uint8List.fromList([0x00, 0x55, 0xaa, 0xff]);
      await peripheral.write(HilUuid.multi, expected);
      expect(await peripheral.read(HilUuid.multi), orderedEquals(expected));

      await peripheral.subscribe(HilUuid.multi);
      expect((await peripheral.readState()).multiNotificationsEnabled, isTrue);
      await peripheral.unsubscribe(HilUuid.multi);
      expect((await peripheral.readState()).multiNotificationsEnabled, isFalse);
    });

    testWidgets('receives an exact notification payload', (_) async {
      final expected = Uint8List.fromList([0, 1, 2, 127, 128, 254, 255]);
      await peripheral.subscribe(HilUuid.notify);
      final received = peripheral.values(HilUuid.notify).first;

      await peripheral.requestNotification(expected);

      expect(
        await received.timeout(HilPeripheral.operationTimeout),
        isA<Uint8List>()
            .having((value) => value, 'bytes', orderedEquals(expected))
            .having((value) => value.offsetInBytes, 'offsetInBytes', 0)
            .having(
              (value) => value.buffer.lengthInBytes,
              'buffer length',
              expected.length,
            ),
      );
      expect((await peripheral.readState()).notificationsEnabled, isTrue);
    });

    testWidgets('delivers values through both stream and callback APIs', (
      _,
    ) async {
      final expected = Uint8List.fromList([0xde, 0xad, 0xbe, 0xef]);
      final callbackValue = Completer<Uint8List>();
      UniversalBle.onValueChange =
          (deviceId, characteristicId, value, timestamp) {
        if (deviceId.toLowerCase() == peripheral.deviceId.toLowerCase() &&
            BleUuidParser.compareStrings(characteristicId, HilUuid.notify) &&
            !callbackValue.isCompleted) {
          callbackValue.complete(value);
        }
      };
      await peripheral.subscribe(HilUuid.notify);
      final streamValue = peripheral.values(HilUuid.notify).first;

      await peripheral.requestNotification(expected);

      expect(
        await streamValue.timeout(HilPeripheral.operationTimeout),
        orderedEquals(expected),
      );
      expect(
        await callbackValue.future.timeout(HilPeripheral.operationTimeout),
        orderedEquals(expected),
      );
    });

    testWidgets('receives an exact indication payload', (_) async {
      final expected = Uint8List.fromList(utf8.encode('indication-payload'));
      await peripheral.subscribe(HilUuid.indicate, indicate: true);
      final received = peripheral.values(HilUuid.indicate).first;

      await peripheral.requestIndication(expected);

      expect(
        await received.timeout(HilPeripheral.operationTimeout),
        orderedEquals(expected),
      );
      expect((await peripheral.readState()).indicationsEnabled, isTrue);
    });

    testWidgets('disables and restores indications cleanly', (_) async {
      await peripheral.subscribe(HilUuid.indicate, indicate: true);
      await peripheral.unsubscribe(HilUuid.indicate);
      expect((await peripheral.readState()).indicationsEnabled, isFalse);
      await expectLater(peripheral.requestIndication([1]), throwsA(anything));

      await peripheral.subscribe(HilUuid.indicate, indicate: true);
      final received = peripheral.values(HilUuid.indicate).first;
      await peripheral.requestIndication([2]);
      expect(await received.timeout(HilPeripheral.operationTimeout), [2]);
    });

    testWidgets('unsubscribes and allows a clean resubscription', (_) async {
      await peripheral.subscribe(HilUuid.notify);
      await peripheral.unsubscribe(HilUuid.notify);
      expect((await peripheral.readState()).notificationsEnabled, isFalse);
      await expectLater(peripheral.requestNotification([1]), throwsA(anything));

      await peripheral.subscribe(HilUuid.notify);
      final received = peripheral.values(HilUuid.notify).first;
      await peripheral.requestNotification([2]);
      expect(await received.timeout(HilPeripheral.operationTimeout), [2]);
    });

    testWidgets('preserves ordered notifications during a burst', (_) async {
      const count = 40;
      await peripheral.subscribe(HilUuid.notify);
      final received = peripheral.values(HilUuid.notify).take(count).toList();

      await peripheral.requestNotificationBurst(
        count: count,
        size: 64,
        interval: const Duration(milliseconds: 30),
      );

      final values = await received.timeout(const Duration(seconds: 15));
      expect(values, hasLength(count));
      for (var index = 0; index < values.length; index++) {
        expect(_uint16(values[index], 0), index);
        expect(values[index], hasLength(64));
        expect(values[index][63], 63);
      }
    });

    testWidgets('reports a peripheral-initiated disconnect', (_) async {
      final disconnected = peripheral.connections.firstWhere(
        (connected) => !connected,
      );

      await peripheral.requestDisconnect(const Duration(milliseconds: 100));

      expect(
        await disconnected.timeout(HilPeripheral.operationTimeout),
        isFalse,
      );
    });

    testWidgets(
      'reports a host disconnect through stream, callback, and state',
      (_) async {
        final streamEvent = peripheral.connections.firstWhere(
          (connected) => !connected,
        );
        final callbackEvent = Completer<bool>();
        UniversalBle.onConnectionChange = (deviceId, connected, error) {
          if (deviceId.toLowerCase() == peripheral.deviceId.toLowerCase() &&
              !connected &&
              !callbackEvent.isCompleted) {
            callbackEvent.complete(connected);
          }
        };

        await UniversalBle.disconnect(
          peripheral.deviceId,
          timeout: HilPeripheral.operationTimeout,
        );

        expect(
          await streamEvent.timeout(HilPeripheral.operationTimeout),
          isFalse,
        );
        expect(
          await callbackEvent.future.timeout(HilPeripheral.operationTimeout),
          isFalse,
        );
        expect(
          await UniversalBle.getConnectionState(peripheral.deviceId),
          BleConnectionState.disconnected,
        );
      },
    );

    testWidgets(
      'reconnects after a peripheral-initiated disconnect',
      (_) async {
        final disconnected = peripheral.connections.firstWhere(
          (connected) => !connected,
        );
        await peripheral.requestDisconnect(const Duration(milliseconds: 200));
        await disconnected.timeout(HilPeripheral.operationTimeout);

        await peripheral.reconnect();

        expect(
          await UniversalBle.getConnectionState(peripheral.deviceId),
          BleConnectionState.connected,
        );
        expect(utf8.decode(await peripheral.read(HilUuid.read)), 'HIL-READ-V1');
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    testWidgets(
      'survives repeated host disconnect and reconnect cycles',
      (_) async {
        const cycles = int.fromEnvironment(
          'HIL_RECONNECT_CYCLES',
          defaultValue: 10,
        );
        for (var cycle = 0; cycle < cycles; cycle++) {
          await UniversalBle.disconnect(
            peripheral.deviceId,
            timeout: HilPeripheral.operationTimeout,
          );
          await peripheral.reconnect();
          expect(
            (await peripheral.readState()).contractRevision,
            HilPeripheral.contractRevision,
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );

    testWidgets('recovers after overlapping notification operations', (
      _,
    ) async {
      UniversalBle.queueType = QueueType.none;
      final results = await Future.wait<Object>([
        peripheral
            .subscribe(HilUuid.notify)
            .then<Object>((_) => true)
            .catchError((_) => false),
        peripheral
            .subscribe(HilUuid.notify)
            .then<Object>((_) => true)
            .catchError((_) => false),
      ]);
      expect(results, contains(true));

      UniversalBle.queueType = QueueType.global;
      try {
        await peripheral.unsubscribe(HilUuid.notify);
      } catch (_) {
        // A successful concurrent subscribe can complete after the other operation fails.
      }
      await peripheral.subscribe(HilUuid.notify);
      final received = peripheral.values(HilUuid.notify).first;
      await peripheral.requestNotification([0xaa]);
      expect(await received.timeout(HilPeripheral.operationTimeout), [0xaa]);
    }, skip: kIsWeb);

    testWidgets('returns a plausible negotiated MTU', (_) async {
      final mtu = await UniversalBle.requestMtu(peripheral.deviceId, 247);
      final state = await peripheral.readState();

      expect(mtu, greaterThanOrEqualTo(23));
      expect(state.mtu, mtu);
    }, skip: kIsWeb);

    testWidgets('reports usable client capabilities without harming GATT', (
      _,
    ) async {
      expect(await UniversalBle.hasPermissions(), isTrue);
      expect(
        await UniversalBle.getBluetoothAvailabilityState(),
        AvailabilityState.poweredOn,
      );
      expect(peripheral.device.receivesAdvertisements, isTrue);

      if (defaultTargetPlatform == TargetPlatform.android) {
        for (final priority in BleConnectionPriority.values) {
          await UniversalBle.requestConnectionPriority(
            peripheral.deviceId,
            priority,
          );
        }
      } else {
        await expectLater(
          UniversalBle.requestConnectionPriority(
            peripheral.deviceId,
            BleConnectionPriority.balanced,
          ),
          throwsA(isA<UniversalBleException>()),
        );
      }
      expect(utf8.decode(await peripheral.read(HilUuid.read)), 'HIL-READ-V1');
    }, skip: kIsWeb);

    testWidgets('remains usable after enumerating connected system devices', (
      _,
    ) async {
      if (defaultTargetPlatform == TargetPlatform.windows) {
        final devices = await UniversalBle.getSystemDevices(
          withServices: const [HilUuid.service],
        );
        expect(
          devices.map((device) => device.deviceId.toLowerCase()),
          contains(peripheral.deviceId.toLowerCase()),
        );
      }

      expect(utf8.decode(await peripheral.read(HilUuid.read)), 'HIL-READ-V1');
      await peripheral.write(HilUuid.write, [0x5a]);
      expect(await peripheral.read(HilUuid.writeMirror), [0x5a]);
    }, skip: kIsWeb);

    testWidgets(
      'keeps ordinary GATT operations usable across service changes',
      (_) async {
        await peripheral.setAuxiliaryService(enabled: true);
        await _eventually(
          () async => (await peripheral.discover()).any(
            (service) => BleUuidParser.compareStrings(
              service.uuid,
              HilUuid.auxiliaryService,
            ),
          ),
        );
        await peripheral.setAuxiliaryService(enabled: false);
        await _eventually(
          () async => !(await peripheral.discover()).any(
            (service) => BleUuidParser.compareStrings(
              service.uuid,
              HilUuid.auxiliaryService,
            ),
          ),
        );

        expect(utf8.decode(await peripheral.read(HilUuid.read)), 'HIL-READ-V1');
        await peripheral.write(HilUuid.write, [0xa5]);
        expect(await peripheral.read(HilUuid.writeMirror), [0xa5]);
      },
    );

    testWidgets(
      'reports that connected RSSI reads are unsupported on Windows',
      (_) async {
        if (defaultTargetPlatform == TargetPlatform.windows) {
          await expectLater(
            UniversalBle.readRssi(peripheral.deviceId),
            throwsA(
              isA<UniversalBleException>().having(
                (error) => error.code,
                'code',
                UniversalBleErrorCode.notImplemented,
              ),
            ),
          );
        } else {
          // Android, macOS, and iOS return a valid RSSI value.
          expect(await UniversalBle.readRssi(peripheral.deviceId), isA<int>());
        }
        expect(
          await UniversalBle.getConnectionState(peripheral.deviceId),
          BleConnectionState.connected,
        );
      },
      skip: kIsWeb,
    );
  });
}

bool _isHilService(String uuid) =>
    BleUuidParser.compareStrings(uuid, HilUuid.service);

BleCharacteristic _characteristic(BleService service, String uuid) =>
    service.characteristics.singleWhere(
      (characteristic) =>
          BleUuidParser.compareStrings(characteristic.uuid, uuid),
    );

void _expectProperties(
  BleService service,
  String uuid,
  List<CharacteristicProperty> expected,
) {
  final characteristic = service.characteristics.singleWhere(
    (characteristic) => BleUuidParser.compareStrings(characteristic.uuid, uuid),
  );
  expect(characteristic.properties, unorderedEquals(expected));
}

Future<void> _eventually(
  Future<bool> Function() predicate, {
  Duration timeout = HilPeripheral.operationTimeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await predicate()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('Condition was not satisfied within $timeout');
}

int _uint16(Uint8List value, int offset) =>
    ByteData.sublistView(value).getUint16(offset, Endian.little);
