// Manual Apple HIL check for the #394 disconnect guard (PR #396).
//
// Runs the real plugin on macOS against a real peripheral. It is not part of
// CI: it needs a radio and a nearby connectable device whose GATT database has
// a readable, a notifiable and a descriptor-bearing characteristic.
//
//   cd example
//   flutter test integration_test/apple_gatt_disconnect_test.dart -d macos \
//     --dart-define=APPLE_BLE_TEST_DEVICE='FS-7A25F8'
//
// The device used here (FS-7A25F8) exposes:
//   180A 2A51 [read]
//   FFF0 FFF1 [notify] with 2902, FFF2 [writeNoResp]
//
// It checks two windows, both of which a link loss produces:
//
//   RACE_DISCONNECT     The requests are issued while the peripheral is
//                       .disconnecting and still holds its attribute tree.
//                       #396's state guard settles all four with
//                       deviceDisconnected.
//   AFTER_DISCONNECT    The disconnect has completed. CoreBluetooth has
//                       discarded CBPeripheral.services, but the state check
//                       runs before the lookup, so all four are refused with
//                       deviceDisconnected instead of characteristicNotFound.
//
// Observed on macOS 26.6.2 and iPadOS 26.6.1, 2026-11-23.
//
// On iPadOS 26.6.1 the Bluetooth permission prompt did not appear while the
// example declared NSAccessorySetupKitSupports (used by the ASK picker), and
// CBManagerState stayed poweredOff, so the scan was a no-op. Removing those
// keys surfaced the prompt; the test waits for poweredOn so it works either
// way once Bluetooth has been granted.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:universal_ble/universal_ble.dart';

const String targetName = String.fromEnvironment(
  'APPLE_BLE_TEST_DEVICE',
  defaultValue: 'FS-7A25F8',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Apple GATT requests: connected works, disconnected is refused', (
    tester,
  ) async {
    final scanned = <String, BleDevice>{};
    UniversalBle.onScanResult = (device) {
      scanned[device.deviceId] = device;
      if (device.name == targetName) {
        UniversalBle.stopScan().ignore();
      }
    };

    // On a fresh install iOS shows the Bluetooth permission prompt on first
    // use and reports CBManagerState.poweredOff until it is answered. Wait for
    // poweredOn before scanning, otherwise the scan is a no-op.
    var availability = await UniversalBle.getBluetoothAvailabilityState();
    // ignore: avoid_print
    print('WAITING_FOR_POWER $availability');
    final powerDeadline = DateTime.now().add(const Duration(seconds: 90));
    var lastSeen = availability;
    while (availability != AvailabilityState.poweredOn &&
        DateTime.now().isBefore(powerDeadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      availability = await UniversalBle.getBluetoothAvailabilityState();
      if (availability != lastSeen) {
        // ignore: avoid_print
        print('WAITING_FOR_POWER $availability');
        lastSeen = availability;
      }
    }
    // ignore: avoid_print
    print('AVAILABILITY $availability');
    expect(
      availability,
      AvailabilityState.poweredOn,
      reason: 'accept the Bluetooth prompt on the device',
    );
    await UniversalBle.startScan();
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    BleDevice? target;
    while (DateTime.now().isBefore(deadline)) {
      for (final d in scanned.values) {
        if (d.name == targetName) target = d;
      }
      if (target != null) break;
      await tester.pump(const Duration(milliseconds: 250));
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    UniversalBle.onScanResult = null;
    await UniversalBle.stopScan();
    expect(target, isNotNull, reason: '$targetName was not advertising');
    final deviceId = target!.deviceId;
    // ignore: avoid_print
    print('DEVICE $deviceId ${target.name}');

    await UniversalBle.connect(deviceId);
    // ignore: avoid_print
    print('CONNECTED ${await UniversalBle.getConnectionState(deviceId)}');

    final services = await UniversalBle.discoverServices(
      deviceId,
      withDescriptors: true,
      timeout: const Duration(seconds: 60),
    );
    for (final s in services) {
      for (final c in s.characteristics) {
        // ignore: avoid_print
        print(
          'GATT ${s.uuid} ${c.uuid} ${c.properties.map((p) => p.name).join(",")} '
          'descriptors=${c.descriptors.map((d) => d.uuid).join(",")}',
        );
      }
    }

    final readPair = _findReadable(services);
    final notifyPair0 = _findNotifiableWithCccd(services);
    expect(readPair, isNotNull, reason: 'no readable characteristic');
    expect(notifyPair0, isNotNull, reason: 'no notifiable characteristic');

    final (:service, :characteristic) = readPair!;
    final readService = service;
    final readCharacteristic = characteristic;
    final notifyPair = notifyPair0!;
    final notifyService = notifyPair.service;
    final notifyCharacteristic = notifyPair.characteristic;
    final cccd = notifyPair.cccd;

    // --- Connected: every request the guard now covers must succeed. ---
    final value = await UniversalBle.read(
      deviceId,
      readService,
      readCharacteristic,
    );
    // ignore: avoid_print
    print('READ_OK $readCharacteristic ${value.length} bytes');

    final descriptorValue = await UniversalBle.readDescriptor(
      deviceId,
      notifyService,
      notifyCharacteristic,
      cccd,
    );
    // ignore: avoid_print
    print('DESCRIPTOR_READ_OK $cccd $descriptorValue');

    await UniversalBle.writeDescriptor(
      deviceId,
      notifyService,
      notifyCharacteristic,
      cccd,
      Uint8List.fromList([0x01, 0x00]),
    );
    // ignore: avoid_print
    print('DESCRIPTOR_WRITE_OK $cccd enable');

    await UniversalBle.subscribeNotifications(
      deviceId,
      notifyService,
      notifyCharacteristic,
    );
    // ignore: avoid_print
    print('SUBSCRIBE_OK $notifyCharacteristic');

    await UniversalBle.unsubscribe(
      deviceId,
      notifyService,
      notifyCharacteristic,
    );
    // ignore: avoid_print
    print('UNSUBSCRIBE_OK $notifyCharacteristic');

    // --- Race the same requests against disconnect(): the peripheral is in
    // .disconnecting and still holds its attribute tree, the window #396's
    // state guard exists for. ---
    final disconnectFuture = UniversalBle.disconnect(deviceId);
    final raced = <String>[];
    Future<void> race(String label, Future<Object?> Function() action) async {
      try {
        await action();
        raced.add('$label=SUCCESS');
      } on UniversalBleException catch (e) {
        raced.add('$label=${e.code}');
      } on TimeoutException catch (_) {
        raced.add('$label=TIMEOUT');
      }
    }

    await Future.wait([
      race(
        'read',
        () => UniversalBle.read(deviceId, readService, readCharacteristic),
      ),
      race(
        'readDescriptor',
        () => UniversalBle.readDescriptor(
          deviceId,
          notifyService,
          notifyCharacteristic,
          cccd,
        ),
      ),
      race(
        'writeDescriptor',
        () => UniversalBle.writeDescriptor(
          deviceId,
          notifyService,
          notifyCharacteristic,
          cccd,
          Uint8List.fromList([0x00, 0x00]),
        ),
      ),
      race(
        'subscribe',
        () => UniversalBle.subscribeNotifications(
          deviceId,
          notifyService,
          notifyCharacteristic,
        ),
      ),
    ]);
    await disconnectFuture;
    // ignore: avoid_print
    print('RACE_DISCONNECT ${raced.join(" ")}');

    for (var i = 0; i < 40; i++) {
      final state = await UniversalBle.getConnectionState(deviceId);
      if (state == BleConnectionState.disconnected) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    // ignore: avoid_print
    print('DISCONNECTED ${await UniversalBle.getConnectionState(deviceId)}');

    // --- Disconnected: the plugin must refuse these itself, not hand them to
    // CoreBluetooth and wait for the timeout. The state check runs before the
    // lookup, so they report deviceDisconnected even though CoreBluetooth has
    // already discarded the attribute tree. ---
    final afterDrop = <String>[];
    Future<void> refused(String label, Future<Object?> Function() action) async {
      try {
        await action();
        // ignore: avoid_print
        print('$label: NO ERROR (unexpected)');
        fail('$label on a disconnected peripheral completed instead of failing');
      } on UniversalBleException catch (e) {
        // ignore: avoid_print
        print('$label: ${e.code} "${e.message}"');
        expect(
          e.code,
          UniversalBleErrorCode.deviceDisconnected,
          reason: '$label must report deviceDisconnected, got ${e.code}',
        );
        expect(e.message, contains('Disconnected'));
        afterDrop.add('$label=${e.code}');
      } on TimeoutException catch (_) {
        fail('$label reached CoreBluetooth and never completed');
      }
    }

    await refused(
      'read',
      () => UniversalBle.read(deviceId, readService, readCharacteristic),
    );
    await refused(
      'readDescriptor',
      () => UniversalBle.readDescriptor(
        deviceId,
        notifyService,
        notifyCharacteristic,
        cccd,
      ),
    );
    await refused(
      'writeDescriptor',
      () => UniversalBle.writeDescriptor(
        deviceId,
        notifyService,
        notifyCharacteristic,
        cccd,
        Uint8List.fromList([0x00, 0x00]),
      ),
    );
    await refused(
      'subscribeNotifications',
      () => UniversalBle.subscribeNotifications(
        deviceId,
        notifyService,
        notifyCharacteristic,
      ),
    );
    // ignore: avoid_print
    print('AFTER_DISCONNECT ${afterDrop.join(" ")}');
  });
}

({String service, String characteristic})? _findReadable(
  List<BleService> services,
) {
  for (final s in services) {
    for (final c in s.characteristics) {
      if (c.properties.contains(CharacteristicProperty.read)) {
        return (service: s.uuid, characteristic: c.uuid);
      }
    }
  }
  return null;
}

({String service, String characteristic, String cccd})?
_findNotifiableWithCccd(List<BleService> services) {
  for (final s in services) {
    for (final c in s.characteristics) {
      if (!c.properties.contains(CharacteristicProperty.notify)) continue;
      for (final d in c.descriptors) {
        final uuid = d.uuid.toUpperCase();
        if (uuid.endsWith('2902') ||
            uuid.endsWith('2902-0000-1000-8000-00805F9B34FB')) {
          return (service: s.uuid, characteristic: c.uuid, cccd: d.uuid);
        }
      }
    }
  }
  return null;
}
