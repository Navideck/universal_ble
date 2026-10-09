---
name: universal-ble-setup
description: >-
  Use when adding universal_ble to a Flutter app for the first time — BLE
  scanning, connecting, service discovery, read/write, notifications and
  indications, or peripheral advertising — or when configuring platform
  permissions on Android, iOS, macOS, Windows, Linux, or Web, including the
  Android manifest permissions, the Apple Info.plist keys and macOS Bluetooth
  entitlement, and Web optional services. Also use when a scan returns nothing,
  connect times out, a read/write fails, notifications never fire, or the
  availability state is unsupported or unauthorized.
---

# Adding universal_ble to a Flutter app

`universal_ble` is a single Flutter plugin for BLE central (and peripheral) on
Android, iOS, macOS, Windows, Linux, and Web. This skill gets a first
integration working and points to the README for detail. The README anchors
below link to
[`README.md`](https://github.com/Navideck/universal_ble/blob/main/README.md).

## Rules

1. Depend on `universal_ble` only. One package covers every platform — Windows
   support is built in (no `flutter_blue_plus_winrt`-style add-on).
2. Read the README [Platform-specific setup](https://github.com/Navideck/universal_ble/blob/main/README.md#platform-specific-setup)
   before the first build; missing manifest/plist/entitlement entries make BLE
   silently fail or the app get killed.
3. Check availability before scanning: wait for `AvailabilityState.poweredOn`
   via `getBluetoothAvailabilityState()` or `availabilityStream`
   ([Bluetooth Availability](https://github.com/Navideck/universal_ble/blob/main/README.md#bluetooth-availability)).
4. Register `onScanResult` or listen to `scanStream` **before** calling
   `startScan()`; results are per-device `BleDevice` events, not batches.
5. `startScan()` has no `timeout:` parameter. Stop it yourself with a `Timer` or
   `stopScan()`, and stop scanning before connecting.
6. Call `discoverServices()` after every (re)connection. `getService()` and
   `getCharacteristic()` auto-discover when the cache is empty, but an explicit
   call is recommended.
7. Subscribe before listening: `await characteristic.notifications.subscribe()`
   (or `indications.subscribe()`), then read `characteristic.onValueReceived`.
8. `write()` defaults to **with response**. Pass `withResponse: false` for a
   write-without-response.
9. Permissions are requested automatically on `startScan()`. Call
   `requestPermissions()` explicitly before `connect()`/`read()`/`write()` if
   you need them confirmed first.
10. `connect(autoConnect: true)` reconnects while the device is available; call
    `disconnect()` to stop it.
11. UUIDs are format-agnostic: pass `"180f"`, `"180F"`, or the full 128-bit form.
    Results always come back lowercase 128-bit.
12. Peripheral APIs require `getCapabilities().supportsPeripheralMode`. Linux
    and Web do not support peripheral mode.

## Setup (central role)

```yaml
# pubspec.yaml
dependencies:
  universal_ble: ^3.0.0
```

```dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

Future<void> startBle() async {
  // 1. Wait until Bluetooth is on. See #bluetooth-availability.
  if (await UniversalBle.getBluetoothAvailabilityState() !=
      AvailabilityState.poweredOn) {
    return;
  }

  // 2. Listen for results, then scan. See #scanning and #scan-filter.
  UniversalBle.scanStream.listen((BleDevice device) {
    debugPrint('${device.deviceId} ${device.name} rssi=${device.rssi}');
  });
  await UniversalBle.startScan(
    scanFilter: ScanFilter(withServices: ['180f']),
  );
  Timer(const Duration(seconds: 15), () => UniversalBle.stopScan());

  // 3. Connect and discover. See #connecting and #discovering-services.
  final device = BleDevice(deviceId: 'DEVICE_ID', name: null);
  await device.connect();
  final services = await device.discoverServices();

  // 4. Read or subscribe. See #reading--writing-data and #subscriptions.
  final characteristic = services
      .firstWhere((s) => BleUuidParser.compareStrings(s.uuid, '180f'))
      .getCharacteristic('2a19');
  final value = await characteristic.read();
  await characteristic.notifications.subscribe();
  characteristic.onValueReceived.listen((v) => debugPrint('$value $v'));
}
```

Other topics the README covers in depth: [scan filters](https://github.com/Navideck/universal_ble/blob/main/README.md#scan-filter),
[system devices](https://github.com/Navideck/universal_ble/blob/main/README.md#system-devices),
[auto-connect and background events](https://github.com/Navideck/universal_ble/blob/main/README.md#auto-connect),
[pairing](https://github.com/Navideck/universal_ble/blob/main/README.md#pairing),
[MTU](https://github.com/Navideck/universal_ble/blob/main/README.md#requesting-mtu),
[RSSI](https://github.com/Navideck/universal_ble/blob/main/README.md#reading-rssi),
[command queue](https://github.com/Navideck/universal_ble/blob/main/README.md#command-queue),
[timeout](https://github.com/Navideck/universal_ble/blob/main/README.md#timeout),
[error handling](https://github.com/Navideck/universal_ble/blob/main/README.md#error-handling),
and [logging](https://github.com/Navideck/universal_ble/blob/main/README.md#logging).

Prefer the object API (`bleDevice`, `characteristic`) above. The
[Low-Level API](https://github.com/Navideck/universal_ble/blob/main/README.low_level.md)
is a `deviceId`-based alternative for stateless or service-style code.

## Peripheral role (pointer)

Check capabilities before using `UniversalBlePeripheral`:

```dart
final caps = await UniversalBlePeripheral.getCapabilities();
if (!caps.supportsPeripheralMode) return;
```

Full service management, advertising, request handlers, and event streams are in
[Peripheral Mode](https://github.com/Navideck/universal_ble/blob/main/README.md#peripheral-mode).

## Traps

**Scan returns nothing**
- Check `AvailabilityState.poweredOn` and that permissions were granted.
- Stop any prior scan before starting a new one.
- Android: for legacy BLE 4.x peripherals (e.g. ESP32) pass
  `platformConfig: PlatformConfig(android: AndroidOptions(legacy: true))`
  ([Android scan options](https://github.com/Navideck/universal_ble/blob/main/README.md#android-scan-options)).
- Web: you must list the services you will use in the scan filter
  ([Web](https://github.com/Navideck/universal_ble/blob/main/README.md#web)).

**`AvailabilityState.unsupported` on macOS**
- Symptom: availability reports unsupported even with Bluetooth on.
- Fix: add the `com.apple.security.device.bluetooth` entitlement to both
  `DebugProfile.entitlements` and `Release.entitlements`
  ([macOS entitlements](https://github.com/Navideck/universal_ble/blob/main/README.md#macos-entitlements)).

**`MissingPluginException` right after adding the package**
- Hot reload/restart is not enough. Fully stop and re-run the app; try
  `flutter clean` if it persists.

**`connect()` throws or times out**
- Ensure Bluetooth is on, permissions are granted, and scanning is stopped.
- Catch `ConnectionException` and inspect `e.code`
  (`UniversalBleErrorCode.connectionTimeout`, `connectionFailed`,
  `deviceDisconnected`, …)
  ([Error Handling](https://github.com/Navideck/universal_ble/blob/main/README.md#error-handling)).

**`serviceNotFound` / `characteristicNotFound`**
- Call `discoverServices()` after connecting; UUIDs are format-agnostic.
- Android keeps a GATT cache across connections; if the peripheral's layout
  changed, pass
  `platformConfig: DiscoverServicesPlatformConfig(android: AndroidDiscoverServicesOptions(clearGattCache: true))`.

**Notifications never fire**
- Subscribe first (`notifications.subscribe()` or `indications.subscribe()`),
  then listen to `onValueReceived`.
- Verify the characteristic advertises `notify`/`indicate` in
  `characteristic.properties`.

**Stale state after a hot restart**
- Native connections and scans can outlive Dart state in debug hot restart. Use
  the `resetBleState()` helper
  ([Resetting State on Hot Restart](https://github.com/Navideck/universal_ble/blob/main/README.md#resetting-state-on-hot-restart)).

**`write` appears to hang or behaves unexpectedly**
- `write()` is with-response by default. Use `withResponse: false` for
  write-without-response.

**Peripheral APIs throw / do nothing**
- Guard with `caps.supportsPeripheralMode`; Linux and Web return unsupported.

## Where to go next

| Task | README |
| --- | --- |
| Scan filters (services, manufacturer data, name prefix, exclusions) | [Scan Filter](https://github.com/Navideck/universal_ble/blob/main/README.md#scan-filter) |
| Devices already connected by the OS / other apps | [System Devices](https://github.com/Navideck/universal_ble/blob/main/README.md#system-devices) |
| Auto-connect and background connection events | [Auto-connect](https://github.com/Navideck/universal_ble/blob/main/README.md#auto-connect) |
| MTU, connection priority, RSSI | [Requesting MTU](https://github.com/Navideck/universal_ble/blob/main/README.md#requesting-mtu) · [Reading RSSI](https://github.com/Navideck/universal_ble/blob/main/README.md#reading-rssi) |
| Pairing / bonding | [Pairing](https://github.com/Navideck/universal_ble/blob/main/README.md#pairing) |
| Descriptors | [Reading & Writing data](https://github.com/Navideck/universal_ble/blob/main/README.md#reading--writing-data) |
| Subscription status | [Check Subscription Status](https://github.com/Navideck/universal_ble/blob/main/README.md#check-subscription-status) |
| Queueing and global timeout | [Command Queue](https://github.com/Navideck/universal_ble/blob/main/README.md#command-queue) · [Timeout](https://github.com/Navideck/universal_ble/blob/main/README.md#timeout) |
| Typed errors | [Error Handling](https://github.com/Navideck/universal_ble/blob/main/README.md#error-handling) |
| Debug logging | [Logging](https://github.com/Navideck/universal_ble/blob/main/README.md#logging) |
| Mock / custom platform implementation | [Customizing Platform Implementation](https://github.com/Navideck/universal_ble/blob/main/README.md#customizing-platform-implementation-of-universal-ble) |
| Peripheral server | [Peripheral Mode](https://github.com/Navideck/universal_ble/blob/main/README.md#peripheral-mode) |
| Coming from flutter_blue_plus | use the `universal-ble-migrate-from-flutter-blue-plus` skill |

When in doubt, follow the README — it is the source of truth for this package.
