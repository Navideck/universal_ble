---
name: universal-ble-migrate-from-flutter-blue-plus
description: >-
  Migrate a Flutter app from flutter_blue_plus (FlutterBluePlus) to universal_ble.
  Use when the user wants to replace flutter_blue_plus, port BLE scanning,
  connecting, service discovery, read/write or subscription code, or map
  FlutterBluePlus APIs (BluetoothDevice, Guid, ScanResult, BluetoothCharacteristic,
  BluetoothDescriptor) to universal_ble equivalents.
---

# Migrating from flutter_blue_plus to universal_ble

This skill guides a mechanical, central-role migration from `flutter_blue_plus`
(FlutterBluePlus, "FBP") to `universal_ble` (UniversalBle, "UB"). Both are
Flutter BLE central-role plugins; most concepts map 1:1, but the object model
and a handful of APIs differ.

## Migration workflow

Work top to bottom, keeping the project compiling after each step:

1. Swap the dependency and imports.
2. Port adapter/availability state handling.
3. Port scanning.
4. Port connecting and service discovery.
5. Port read/write and descriptor access.
6. Port notifications/indications.
7. Replace FBP error handling with UB's typed exceptions.
8. Update platform setup (Windows especially).
9. Run `flutter analyze` and fix remaining references to `flutter_blue_plus`.

Search the codebase for `FlutterBluePlus`, `BluetoothDevice`, `BluetoothCharacteristic`,
`BluetoothDescriptor`, `ScanResult`, `Guid`, and `import 'package:flutter_blue_plus`.

## 1. Dependency and imports

Remove `flutter_blue_plus` (and `flutter_blue_plus_winrt` if present) and add
`universal_ble`:

```yaml
dependencies:
  universal_ble: ^3.0.0
```

Replace imports:

```dart
// Before
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// After
import 'package:universal_ble/universal_ble.dart';
```

Windows previously required the separate `flutter_blue_plus_winrt` package; UB
supports Android, iOS, macOS, Windows, Linux, and Web from the single package.

## 2. Mental model

| Concept | flutter_blue_plus | universal_ble |
| --- | --- | --- |
| Entry point | `FlutterBluePlus` (static) | `UniversalBle` (static) |
| Device handle | `BluetoothDevice` object | `BleDevice` (high level) or a `String deviceId` (low level) |
| Identifiers | `Guid` objects (`.str`) | Plain `String` UUIDs, any format/case |
| Results | `ScanResult` wrappers | `BleDevice` directly |
| Device operations | Methods on `BluetoothDevice` | Extension methods on `BleDevice` and/or `UniversalBle` statics |

Key differences to internalize:

- **UUIDs are plain strings.** No `Guid` wrapper. Pass `"180D"`, `"180d"`, or the
  full 128-bit form interchangeably; UB normalizes everything to lowercase
  128-bit (e.g. `0000180d-0000-1000-8000-00805f9b34fb`). Use `BleUuidParser.string()`,
  `BleUuidParser.number()`, or `BleUuidParser.compare()` if you need explicit conversion.
- **Two styles.** Prefer the high-level `BleDevice` / extension API (closest to FBP).
  The low-level `UniversalBle.read(deviceId, service, characteristic, ...)` statics are
  for `deviceId`-only workflows. Do not mix object methods with a device you never
  obtained as a `BleDevice`.
- **Streams never close and never emit errors.** Cancel subscriptions yourself.

## 3. Symbol mapping

### Adapter / availability

| flutter_blue_plus | universal_ble |
| --- | --- |
| `FlutterBluePlus.adapterState` (Stream) | `UniversalBle.availabilityStream` (Stream) |
| `FlutterBluePlus.adapterStateNow` | `await UniversalBle.getBluetoothAvailabilityState()` |
| `BluetoothAdapterState.on` | `AvailabilityState.poweredOn` |
| `BluetoothAdapterState.off` | `AvailabilityState.poweredOff` |
| `BluetoothAdapterState.unauthorized` | `AvailabilityState.unauthorized` |
| `BluetoothAdapterState.unavailable` | `AvailabilityState.unsupported` |
| `BluetoothAdapterState.unknown` | `AvailabilityState.unknown` |
| `FlutterBluePlus.turnOn()` / `turnOff()` | `UniversalBle.enableBluetooth()` / `disableBluetooth()` (Android/Windows/Linux; returns `bool`) |
| `FlutterBluePlus.isSupported` | No direct API. Treat `AvailabilityState.unsupported` as unsupported |
| `FlutterBluePlus.setLogLevel(LogLevel.x)` | `UniversalBle.setLogLevel(BleLogLevel.x)` |
| `FlutterBluePlus.setOperationQueueMode(...)` | `UniversalBle.queueType = QueueType.auto|global|perDevice|none` |
| `FlutterBluePlus.setOptions(restoreState: true)` | No direct API. iOS state restoration follows the `bluetooth-central` background mode automatically |
| `FlutterBluePlus.setLogLevel` logs stream | No equivalent; use the platform logger |

FBP's initial adapter state is often `unknown` on iOS; UB reports `unknown` too,
so keep any "wait for poweredOn" logic.

### Scanning

| flutter_blue_plus | universal_ble |
| --- | --- |
| `FlutterBluePlus.startScan(withServices: [Guid], withNames:, withRemoteIds:, timeout:, androidUsesFineLocation:)` | `UniversalBle.startScan(scanFilter: ScanFilter(withServices: [...], withNamePrefix: [...]), platformConfig: ...)` |
| `FlutterBluePlus.stopScan()` | `UniversalBle.stopScan()` |
| `FlutterBluePlus.onScanResults` / `scanResults` (Stream<`List<ScanResult>`>) | `UniversalBle.scanStream` (Stream<`BleDevice>`, one device per event) |
| `FlutterBluePlus.lastScanResults` | No equivalent; keep your own cache |
| `FlutterBluePlus.isScanning` / `isScanningNow` | `UniversalBle.isScanning()` |
| `FlutterBluePlus.cancelWhenScanComplete(sub)` | Manually `sub.cancel()` |
| `ScanResult.device` | the `BleDevice` event itself |
| `ScanResult.rssi` | `bleDevice.rssi` |
| `ScanResult.advertisementData.advName` | `bleDevice.name` |
| `ScanResult.advertisementData.serviceUuids` | `bleDevice.services` |
| `ScanResult.advertisementData.manufacturerData` | `bleDevice.manufacturerDataList` (`ManufacturerData`) |
| `ScanResult.advertisementData.serviceData` | `bleDevice.serviceData` |
| `Guid("180D")` in filters | `"180D"` |

Notable differences:

- **No `timeout:` parameter.** Implement the FBP timeout yourself:

  ```dart
  UniversalBle.startScan(scanFilter: ScanFilter(withServices: ['180D']));
  Timer(const Duration(seconds: 15), () => UniversalBle.stopScan());
  ```

- **No list batching.** `scanStream` emits one `BleDevice` per result, not a list.
  There is no "clears between scans" distinction; maintain your own list if needed.
- **No `withRemoteIds`.** Filter scan results in Dart, or use `ScanFilter.exclusionFilters`.
- **Android fine location:** pass `platformConfig: PlatformConfig(android: AndroidOptions(requestLocationPermission: true))` instead of `androidUsesFineLocation:`.

### Devices

| flutter_blue_plus | universal_ble |
| --- | --- |
| `BluetoothDevice.fromId(id)` | `BleDevice(deviceId: id, name: null)` or call `UniversalBle.*` statics with `id` |
| `device.remoteId.str` | `bleDevice.deviceId` |
| `device.platformName` | `bleDevice.name` (sanitized) or `bleDevice.rawName` (raw) |
| `device.advName` | `bleDevice.name` |
| `device.connect(mtu:, autoConnect:)` | `bleDevice.connect(autoConnect: ...)`; call `requestMtu()` separately |
| `device.disconnect()` | `bleDevice.disconnect()` |
| `device.isConnected` (sync) | `await bleDevice.isConnected` (async) |
| `device.isDisconnected` | `!await bleDevice.isConnected` |
| `device.connectionState` (Stream enum) | `bleDevice.connectionStream` (Stream<`bool`>) |
| `device.connectionState` snapshot | `await bleDevice.connectionState` returns `BleConnectionState` |
| `device.disconnectReason` | `BleConnectionUpdate.errorCode` / `.error` from `bleDevice.connectionUpdateStream` |
| `device.discoverServices()` | `await bleDevice.discoverServices()` |
| `device.servicesList` | No equivalent; the list returned by `discoverServices()` is cached — use `getService()`/`getCharacteristic()` |
| `device.onServicesReset` | No equivalent |
| `device.mtu` / `mtuNow` | No stream; `await bleDevice.requestMtu(n)` returns the negotiated value |
| `device.readRssi()` | `await bleDevice.readRssi()` |
| `device.requestMtu(n)` | `await bleDevice.requestMtu(n)` |
| `device.requestConnectionPriority(ConnectionPriority.high)` | `UniversalBle.requestConnectionPriority(deviceId, BleConnectionPriority.highPerformance)` |
| `device.createBond()` / `removeBond()` / `bondState` | `bleDevice.pair()` / `unpair()` / `pairingStateStream` |
| `device.clearGattCache()` | `discoverServices(platformConfig: DiscoverServicesPlatformConfig(android: AndroidDiscoverServicesOptions(clearGattCache: true)))` |
| `device.cancelWhenDisconnected(sub)` | Manually `sub.cancel()` when the connection stream goes false |
| `FlutterBluePlus.connectedDevices` | No equivalent; track the devices your app connected to |
| `FlutterBluePlus.systemDevices(withServices)` | `UniversalBle.getSystemDevices(withServices: [...])` |

`getSystemDevices` on Apple requires `withServices`; without it UB defaults to
generic 18XX services. You must still `connect()` to system devices before use.

### Characteristics and descriptors

| flutter_blue_plus | universal_ble |
| --- | --- |
| `characteristic.uuid.str` | `characteristic.uuid` |
| `characteristic.properties.read` | `characteristic.properties.contains(CharacteristicProperty.read)` |
| `characteristic.read()` | `await characteristic.read()` |
| `characteristic.write(v)` | `await characteristic.write(v)` (with response by default) |
| `characteristic.write(v, withoutResponse: true)` | `await characteristic.write(v, withResponse: false)` |
| `characteristic.setNotifyValue(true)` | `await characteristic.notifications.subscribe()` |
| `characteristic.setNotifyValue(false)` | `await characteristic.unsubscribe()` |
| `characteristic.isNotifying` | `characteristic.isSubscribed` |
| `characteristic.onValueReceived` (Stream<`List<int>`>) | `characteristic.onValueReceived` (Stream<`Uint8List`>) |
| `characteristic.lastValue` / `lastValueStream` | No equivalent; use `onValueReceived` (it fires on `read()` too) |
| `characteristic.descriptors` | `characteristic.descriptors` |
| `descriptor.read()` / `descriptor.write()` | `characteristic.descriptor(uuid).read()` / `.write(Uint8List)` |

> **Boolean inversion:** FBP uses `withoutResponse:`; UB uses `withResponse:`.
> FBP's `write(data)` (no flag) means *with* response; UB's `write(data)` also
> defaults to `withResponse: true`, so a direct call ports unchanged.

For **indications**, use `characteristic.indications.subscribe()` instead of
`notifications.subscribe()`.

### Events API

FBP's global `FlutterBluePlus.events.*` streams map to UB streams/handlers:

| flutter_blue_plus | universal_ble |
| --- | --- |
| `events.onConnectionStateChanged` | `UniversalBle.onConnectionChange = (BleConnectionUpdate update) {}` or `UniversalBle.connectionUpdateStream(deviceId)` |
| `events.onMtuChanged` | No equivalent stream |
| `events.onReadRssi` | `UniversalBle.readRssi(deviceId)` |
| `events.onServicesReset` | No equivalent |
| `events.onDiscoveredServices` | No equivalent |
| `events.onCharacteristicReceived` | `UniversalBle.onValueChange = (deviceId, characteristicId, value, timestamp) {}` |
| `events.onCharacteristicWritten` | No equivalent |
| `events.onDescriptorRead` / `onDescriptorWritten` | No equivalent |
| `events.onBondStateChanged` | `UniversalBle.onPairingStateChange = (deviceId, isPaired) {}` |
| `events.onNameChanged` | No equivalent |

Prefer the per-device/stream form (`scanStream`, `connectionStream`,
`characteristicValueStream`, `stream.listen`) over the global `onX` handlers when
you already hold the relevant object.

## 4. Before / after examples

### Adapter state

```dart
// Before (flutter_blue_plus)
FlutterBluePlus.adapterState.listen((state) {
  if (state == BluetoothAdapterState.on) startScanning();
});

// After (universal_ble)
UniversalBle.availabilityStream.listen((state) {
  if (state == AvailabilityState.poweredOn) startScanning();
});
```

### Filtered scan

```dart
// Before
FlutterBluePlus.onScanResults.listen((results) {
  for (final r in results) {
    print('${r.device.remoteId} ${r.advertisementData.advName}');
  }
});
await FlutterBluePlus.startScan(
  withServices: [Guid('180D')],
  withNames: ['Bluno'],
  timeout: const Duration(seconds: 15),
);

// After
UniversalBle.scanStream.listen((BleDevice d) {
  print('${d.deviceId} ${d.name}');
});
await UniversalBle.startScan(
  scanFilter: ScanFilter(withServices: ['180D'], withNamePrefix: ['Bluno']),
);
Timer(const Duration(seconds: 15), () => UniversalBle.stopScan());
```

### Connect and discover services

```dart
// Before
final device = BluetoothDevice.fromId(remoteId);
await device.connect();
final services = await device.discoverServices();
for (final s in services) {
  for (final c in s.characteristics) {
    print('${s.uuid.str} ${c.uuid.str}');
  }
}

// After
final device = BleDevice(deviceId: remoteId, name: null);
await device.connect();
final services = await device.discoverServices();
for (final s in services) {
  for (final c in s.characteristics) {
    print('${s.uuid} ${c.uuid}');
  }
}
```

### Read, write, subscribe

```dart
// Before
final characteristic = service.characteristics.firstWhere(
  (c) => c.uuid == Guid('2a37'),
);
final value = await characteristic.read();
await characteristic.write([0x01]);
await characteristic.setNotifyValue(true);
characteristic.onValueReceived.listen((v) => print(v));

// After
final characteristic = service.getCharacteristic('2a37');
final value = await characteristic.read();
await characteristic.write([0x01]);
await characteristic.notifications.subscribe();
characteristic.onValueReceived.listen((v) => print(v));
```

### Error handling

```dart
// Before
try {
  await device.connect();
} on FlutterBluePlusException catch (e) {
  print(e.description);
}

// After
try {
  await device.connect();
} on ConnectionException catch (e) {
  switch (e.code) {
    case UniversalBleErrorCode.connectionTimeout:
      break;
    case UniversalBleErrorCode.connectionFailed:
      break;
    case UniversalBleErrorCode.deviceDisconnected:
      break;
    default:
      break;
  }
} on UniversalBleException catch (e) {
  print('${e.code}: ${e.message}');
}
```

## 5. Behavioral gotchas

- **Typed errors.** UB throws `UniversalBleException` (and subclasses
  `ConnectionException`, `PairingException`, `WebBluetoothGloballyDisabled`) with a
  `UniversalBleErrorCode` enum. Replace any FBP string/code parsing with `e.code`.
- **`write` default is with response.** To match `withoutResponse: true`, pass
  `withResponse: false`.
- **`name` is sanitized.** `BleDevice.name` strips non-printable characters; use
  `rawName` when the exact advertised bytes matter.
- **`Uint8List`, not `List<int>`.** UB read/notify streams yield `Uint8List`; the
  `write` extension accepts `List<int>` and converts.
- **Permissions.** UB requests permissions automatically when you call `startScan()`.
  Call `UniversalBle.requestPermissions()` explicitly before other operations
  (`connect`, `read`, `write`) if you need them confirmed up front. On Web,
  Windows, and Linux this always succeeds.
- **Auto-discovery.** UB auto-discovers services on first `getService()`/
  `getCharacteristic()` if the cache is empty, so an explicit `discoverServices()`
  is optional but recommended.
- **Connection stream semantics.** `connectionStream` emits `bool` (not an enum).
  Use `await device.connectionState` when you need `connecting`/`disconnecting`.
  `connectionUpdateStream` / `onConnectionChange` carry a `BleConnectionUpdate`
  with `errorCode` and `nativeErrorCode` for unrequested disconnects.
- **Call `disconnect()` to stop auto-reconnect.** With `autoConnect: true`, UB
  reconnects while available; an explicit `disconnect()` clears it.
- **Cross-platform UUID shape.** iOS/macOS use a per-app random UUID for
  `deviceId`, Android uses the MAC address. This matches FBP; don't persist one
  platform's ID for use on another.

## 6. Platform setup deltas

- **Android:** permissions are the same set FBP documents;
  `BLUETOOTH_ADVERTISE` is only needed for peripheral mode (out of scope here).
  FBP's Proguard rule for `com.lib.flutter_blue_plus.*` is no longer needed.
  For legacy BLE 4.x peripherals (e.g. ESP32) that FBP found, pass
  `platformConfig: PlatformConfig(android: AndroidOptions(legacy: true))`.
- **iOS / macOS:** same `NSBluetoothAlwaysUsageDescription` key; UB also documents
  `NSBluetoothPeripheralUsageDescription`. macOS needs the
  `com.apple.security.device.bluetooth` entitlement in both entitlements files.
- **Windows:** no extra package. Declare the `bluetooth` and `radios` app
  capabilities when publishing.
- **Linux:** declare the `bluez` plug when packaging as a snap.
- **Web:** the scan filter's `withServices` acts as `optional_services`; list every
  service you will access after connecting. To access services without filtering,
  use `platformConfig: PlatformConfig(web: WebOptions(optionalServices: [...]))`.

## 7. Post-migration checklist

- [ ] `flutter_blue_plus` (and `_winrt`) removed from `pubspec.yaml`.
- [ ] No remaining imports of `package:flutter_blue_plus/...`.
- [ ] All `Guid(...)` uses replaced with plain UUID strings.
- [ ] Scan `startScan` timeouts reimplemented with a `Timer`/`stopScan`.
- [ ] `scanStream` consumers handle per-device events, not lists.
- [ ] `write(..., withoutResponse: true)` converted to `withResponse: false`.
- [ ] Notification code uses `notifications.subscribe()` / `unsubscribe()`.
- [ ] FBP exception handling replaced with `UniversalBleException`/`e.code`.
- [ ] `connectionState` enum listeners migrated to `connectionStream` (`bool`) or the async getter.
- [ ] Platform manifests/entitlements reviewed for the UB requirements above.
- [ ] `flutter analyze` passes with no BLE-related warnings.
