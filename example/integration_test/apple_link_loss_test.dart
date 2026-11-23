// Manual Apple HIL probe: a real peripheral-side link loss.
//
// Connects to a nearby device, discovers its GATT database, then waits for the
// peripheral to drop the link on its own. On the drop it immediately issues the
// requests PR #396 guards, and reports the error code of each. This is the
// check the PR left open: a request submitted while the link is down must not
// reach CoreBluetooth.
//
//   cd example
//   flutter test integration_test/apple_link_loss_test.dart -d macos \
//     --dart-define=APPLE_BLE_TEST_DEVICE='FS-7A25F8' \
//     --dart-define=APPLE_BLE_AUTOCONNECT=true
//
// You have to trigger the drop yourself (power the peripheral off, walk it out
// of range); a device that only drops when it is idle rarely does so while a
// central is connected. Without a drop the test reports NO_LINK_LOSS and stops.
// `APPLE_BLE_LINK_LOSS_WAIT` sets the wait in seconds (default 180).
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:universal_ble/universal_ble.dart';

const String targetName = String.fromEnvironment(
  'APPLE_BLE_TEST_DEVICE',
  defaultValue: 'FS-7A25F8',
);
const int waitSeconds = int.fromEnvironment(
  'APPLE_BLE_LINK_LOSS_WAIT',
  defaultValue: 180,
);
const bool autoConnect = bool.fromEnvironment('APPLE_BLE_AUTOCONNECT');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Apple GATT requests after a real link loss', (tester) async {
    final scanned = <String, BleDevice>{};
    final seenNames = <String>{};
    UniversalBle.onScanResult = (device) {
      scanned[device.deviceId] = device;
      final name = device.name ?? '';
      if (name.isNotEmpty && seenNames.add(name)) {
        // ignore: avoid_print
        print('SEEN $name ${device.services.length} services');
      }
      if (device.name == targetName) {
        UniversalBle.stopScan().ignore();
      }
    };
    await UniversalBle.startScan();
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    BleDevice? target;
    while (DateTime.now().isBefore(deadline)) {
      for (final d in scanned.values) {
        if (d.name == targetName) target = d;
      }
      if (target != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    UniversalBle.onScanResult = null;
    await UniversalBle.stopScan();
    expect(target, isNotNull, reason: '$targetName was not advertising');
    final deviceId = target!.deviceId;
    // ignore: avoid_print
    print('FOUND $deviceId');

    await UniversalBle.connect(deviceId, autoConnect: autoConnect);
    // ignore: avoid_print
    print('MODE autoConnect=$autoConnect');
    final dropped = Completer<BleConnectionChange>();
    final connectedAt = DateTime.now();
    final subscription = UniversalBle.connectionChangeStream(deviceId).listen(
      (change) {
        // ignore: avoid_print
        print(
          'EVENT t=${DateTime.now().difference(connectedAt).inMilliseconds}ms '
          'connected=${change.isConnected} code=${change.errorCode}',
        );
        if (!change.isConnected && !dropped.isCompleted) {
          dropped.complete(change);
        }
      },
    );
    final services = await UniversalBle.discoverServices(
      deviceId,
      withDescriptors: true,
      timeout: const Duration(seconds: 60),
    );
    final readPair = _findReadable(services);
    final notifyPair = _findNotifiableWithCccd(services);
    expect(readPair, isNotNull);
    expect(notifyPair, isNotNull);
    // ignore: avoid_print
    print(
      'CONNECTED read=${readPair!.characteristic} '
      'notify=${notifyPair!.characteristic}',
    );

    // Wait for the peripheral to leave on its own. Do not poll it: the point is
    // an idle link that the device tears down.
    final drop = await Future.any<BleConnectionChange?>([
      dropped.future,
      Future<BleConnectionChange?>.delayed(
        Duration(seconds: waitSeconds),
        () => null,
      ),
    ]);
    if (drop == null) {
      // ignore: avoid_print
      print('NO_LINK_LOSS within ${waitSeconds}s; device kept the link');
      await UniversalBle.disconnect(deviceId);
      await subscription.cancel();
      return;
    }
    // ignore: avoid_print
    print(
      'LINK_LOSS error=${drop.error} code=${drop.errorCode} '
      'native=${drop.nativeErrorCode}',
    );

    // Fire the guarded requests immediately, while the drop is fresh: this is
    // the window in which a periodic timer would submit them.
    final results = <String>[];
    Future<void> probe(String label, Future<Object?> Function() action) async {
      try {
        final value = await action();
        results.add('$label=SUCCESS(${value is List ? value.length : value})');
      } on UniversalBleException catch (e) {
        results.add('$label=${e.code}');
      } on TimeoutException catch (_) {
        results.add('$label=TIMEOUT');
      }
    }

    await Future.wait([
      probe(
        'read',
        () => UniversalBle.read(
          deviceId,
          readPair.service,
          readPair.characteristic,
        ),
      ),
      probe(
        'readDescriptor',
        () => UniversalBle.readDescriptor(
          deviceId,
          notifyPair.service,
          notifyPair.characteristic,
          notifyPair.cccd,
        ),
      ),
      probe(
        'writeDescriptor',
        () => UniversalBle.writeDescriptor(
          deviceId,
          notifyPair.service,
          notifyPair.characteristic,
          notifyPair.cccd,
          Uint8List.fromList([0x00, 0x00]),
        ),
      ),
      probe(
        'subscribe',
        () => UniversalBle.subscribeNotifications(
          deviceId,
          notifyPair.service,
          notifyPair.characteristic,
        ),
      ),
    ]);
    // ignore: avoid_print
    print('AFTER_LINK_LOSS ${results.join(" ")}');

    // The steady state a second later, once CoreBluetooth has had time to drop
    // the object's attribute tree.
    await Future<void>.delayed(const Duration(seconds: 1));
    await probe(
      'readLater',
      () => UniversalBle.read(
        deviceId,
        readPair.service,
        readPair.characteristic,
      ),
    );
    // ignore: avoid_print
    print('LATER ${results.last}');

    await UniversalBle.disconnect(deviceId);
    await subscription.cancel();
  }, timeout: const Timeout(Duration(minutes: 12)));
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
        if (d.uuid.toUpperCase().startsWith('00002902')) {
          return (service: s.uuid, characteristic: c.uuid, cccd: d.uuid);
        }
      }
    }
  }
  return null;
}
