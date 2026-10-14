---
name: universal-ble-migrate-2-to-3
description: >-
  Migrate a Flutter app from universal_ble 2.x to 3.0. Use when upgrading
  universal_ble to ^3.0.0 and fixing its breaking changes: the QueueType.auto
  default, device IDs now emitted in lower-case, the onConnectionChange callback
  now receiving a BleConnectionChange, the onValueChange callback now receiving a
  BleCharacteristicValue, the new connectionChangeStream, the
  BleConnectionParametersUpdated rename, the iOS 18+ unpair behavior with
  AccessorySetupKit, or custom UniversalBlePlatform implementations that no
  longer compile. Also use when a queue no longer serializes commands the same
  way, an onConnectionChange or onValueChange handler fails to compile, stored
  device IDs no longer compare equal, a custom platform mock is missing
  parameters after the upgrade, or unpair behaves differently on iOS.
---

# Migrating universal_ble 2.x → 3.0

3.0 is a focused release. There are six breaking changes to the public API,
plus signature changes to `UniversalBlePlatform` for custom implementations;
everything else in 3.0 is additive.

## Breaking changes at a glance

| # | Change | Affects |
| --- | --- | --- |
| 1 | `QueueType.auto` added and now the default (was `QueueType.global`) | Command execution order; exhaustive `switch` over `QueueType` |
| 2 | Device IDs are now emitted in lower-case on every platform | Code that stored or compared an emitted ID by exact case; peripheral mode; custom platforms |
| 3 | `onConnectionChange` now receives a single `BleConnectionChange` | Every app using the callback |
| 4 | `onValueChange` now receives a single `BleCharacteristicValue` | Every app using the callback |
| 5 | `BleConnectionParametersUpdated` renamed to `BleConnectionParametersChange` | Code that references the type by name |
| 6 | On iOS 18+, `unpair` removes an AccessorySetupKit accessory instead of throwing | Apps that call `unpair` on iOS |
| 7 | `UniversalBlePlatform` interface signatures changed | Custom platform implementations / mocks (`UniversalBle.setInstance`) |

Work top to bottom and re-run `flutter analyze` after each step.

## 1. `QueueType.auto` is now the default

In 2.x every command went through one global queue (`QueueType.global`): each
command waited for the previous one across all devices. In 3.0 the default is
`QueueType.auto`, which picks per platform:

- **Android, Web, Linux** → per-device queue (these BLE stacks reject or misbehave
  on overlapping operations).
- **iOS, macOS, Windows** → commands run in parallel (they pipeline natively).

For most apps this is a pure throughput win and needs no code change. Two cases
need attention:

**You relied on global cross-device serialization.** Opt back in explicitly:

```dart
UniversalBle.queueType = QueueType.global;
UniversalBlePeripheral.queueType = QueueType.global; // if you use peripheral mode
```

**You `switch` exhaustively over `QueueType`.** The new `auto` value makes such a
switch fail to compile. Add the case (or a default):

```dart
switch (queueType) {
  case QueueType.none:
  case QueueType.perDevice:
  case QueueType.global:
  case QueueType.auto: // new in 3.0
    break;
}
```

The four values are `none`, `perDevice`, `global`, and `auto`. See
[Command Queue](https://github.com/Navideck/universal_ble/blob/main/README.md#command-queue)
for how `queueId` interacts with each mode.

## 2. Device IDs are now emitted in lower-case

In 2.x, device IDs were emitted in whatever case the platform reported: Android
upper-cased MACs, Windows/WinRT lower-cased them. (2.1.1 made *inputs*
case-insensitive, but the case that came back out was still platform-specific.)
In 3.0 every emitted ID is canonicalised to lower-case on the native platforms,
so an id compares with plain string equality regardless of where it came from.

This affects scan results and the connection/value/pairing/connection-parameter
callbacks and streams — including peripheral mode. It is a breaking change only
for code that compared or keyed an emitted ID by exact case.

```dart
// Before (2.x): the emitted id kept the platform's native case
UniversalBle.onScanResult = (device) {
  // Android: "AA:BB:CC:DD:EE:FF"; Windows: "aa:bb:cc:dd:ee:ff"
  print(device.deviceId);
};

// After (3.0): lower-case on every native platform
UniversalBle.onScanResult = (device) {
  print(device.deviceId); // "aa:bb:cc:dd:ee:ff"
};
```

**Fix stored or compared IDs.** An ID you saved in 2.x (for example an Android
upper-case MAC) no longer matches the emitted one by `==`. Normalise with
`UniversalBle.canonicalDeviceId`, which returns the comparable form for the
current platform — lower-case on native platforms, **verbatim on Web**:

```dart
final stored = 'AA:BB:CC:DD:EE:FF';               // saved under 2.x
final key = UniversalBle.canonicalDeviceId(stored); // lower-case on native, verbatim on Web
if (device.deviceId == key) { /* ... */ }
```

Prefer `canonicalDeviceId` over a blanket `.toLowerCase()`: Web Bluetooth IDs are
opaque, case-sensitive browser tokens, and lower-casing one breaks the lookup.
Web IDs are emitted and matched exactly as the browser provides them.

**Inputs are unaffected.** Every `UniversalBle` / `UniversalBlePeripheral`
method that takes a `deviceId` still accepts upper, lower, or mixed case; only
the emitted form is now guaranteed lower-case. Peripheral mode follows the same
rule: central IDs in `UniversalBlePeripheral` streams, read/write request
handlers, and `getSubscribedClients` are lower-case, while IDs passed to
`updateCharacteristicValue` / `getMaximumNotifyLength` are accepted in any case.

**Custom platform implementations** must report the canonical (lower-case) form
too. The event-stream filters match the canonical id directly, so a platform that
pushes a non-canonical id straight onto the exported stream controllers — instead
of calling the `update*` handlers, which canonicalise — will no longer match a
query made with a different casing. Canonicalise at the boundary if you bypass
the `update*` helpers.

## 3. `onConnectionChange` now receives a `BleConnectionChange`

The callback signature changed from three positional arguments to one object that
also carries the native error details.

```dart
// Before (2.x)
UniversalBle.onConnectionChange = (String deviceId, bool isConnected, String? error) {
  debugPrint('$deviceId connected=$isConnected error=$error');
};

// After (3.0)
UniversalBle.onConnectionChange = (BleConnectionChange change) {
  debugPrint('${change.deviceId} connected=${change.isConnected} '
      'error=${change.error} code=${change.errorCode}');
};
```

`BleConnectionChange` fields:

- `deviceId`, `isConnected` — same meaning as before.
- `error` — human-readable text, `null` when the change was app-initiated.
- `errorCode` — unified `UniversalBleErrorCode` (e.g. `deviceDisconnected`,
  `connectionTimeout`, `connectionFailed`); `null` where the platform reports no code.
- `nativeErrorCode` — raw platform value (`CBError.Code` on Apple, GATT status on
  Android); use `errorCode` for branching, keep this for diagnostics.

There is also a new per-device stream that emits the same objects:

```dart
UniversalBle.connectionChangeStream(deviceId).listen((change) { /* ... */ });
// or, from a BleDevice:
bleDevice.connectionChangeStream.listen((change) { /* ... */ });
```

**`connectionStream` is unchanged** — it still emits `bool`. If you only need
connect/disconnect, keep using it; migrate to `connectionChangeStream` only when
you need the error code or reason. Prefer `errorCode` over `error` for logic,
since the text is platform-dependent and localized on Apple.

## 4. `onValueChange` now receives a `BleCharacteristicValue`

The other global callback was aligned the same way: four positional arguments
became one model.

```dart
// Before (2.x)
UniversalBle.onValueChange = (
  String deviceId,
  String characteristicId,
  Uint8List value,
  int? timestamp,
) {
  debugPrint('$deviceId $characteristicId $value $timestamp');
};

// After (3.0)
UniversalBle.onValueChange = (BleCharacteristicValue change) {
  debugPrint('${change.deviceId} ${change.characteristicId} '
      '${change.value} t=${change.timestamp}');
};
```

`BleCharacteristicValue` fields:

- `deviceId`, `characteristicId` — same meaning as before; the characteristic id
  is normalized to lowercase 128-bit.
- `value` — the characteristic bytes (`Uint8List`).
- `timestamp` — milliseconds since the Unix epoch where the platform provides
  one, otherwise `null`. This is the only place the timestamp is surfaced:
  `characteristicValueStream` still emits raw `Uint8List` without it.

The high-level `characteristic.onValueReceived` stream (`Stream<Uint8List>`) and
`UniversalBle.characteristicValueStream(...)` are unchanged — only the
`onValueChange` callback payload changed.

## 5. `BleConnectionParametersUpdated` renamed

The connection-parameters model was renamed to match the `…Change` naming of the
other event payloads:

```dart
// Before (2.x)
BleConnectionParametersUpdated
// After (3.0)
BleConnectionParametersChange
```

The `onConnectionParametersChange` callback and every field on the model are
unchanged; only the type name moved. Rename any explicit references (variables,
`List<…>`, type annotations) and re-run the analyzer.

## 6. `unpair` removes an AccessorySetupKit accessory on iOS 18+

On iOS, `unpair` previously threw `notSupported`. On iOS 18+ it now removes an
accessory that was authorized through AccessorySetupKit, so a call that used to
throw now performs a real unpair:

```dart
// iOS 18+: removes an accessory authorized through AccessorySetupKit.
await UniversalBle.unpair(device.deviceId);
```

Accessories are authorized through the new native picker, `requestDevice` (Web
Bluetooth chooser on Web, the AccessorySetupKit picker on iOS 18+), which returns
the selected `BleDevice`; connect it with `connect(device.deviceId)`.

Two things to account for when moving off `notSupported`:

- **Devices not managed by AccessorySetupKit** fail with `deviceNotFound`, so an
  `unpair` call that previously raised `notSupported` can now raise a different
  error. Handle it explicitly rather than relying on the old throw.
- Behavior on other platforms and on pre-iOS-18 Apple systems is unchanged.

On iOS, the AccessorySetupKit picker must be presented while the app is in the
foreground, and the accessory's discovery identifiers must be declared in the
app's `Info.plist` (see README → Native device picker). Apps using only this flow
can omit `NSBluetoothAlwaysUsageDescription`.

## 7. Custom `UniversalBlePlatform` implementations

Only relevant if you extend `UniversalBlePlatform` (e.g. a mock via
`UniversalBle.setInstance`). Several signatures changed:

**`discoverServices` gained a named parameter:**

```dart
// Before (2.x)
@override
Future<List<BleService>> discoverServices(String deviceId, bool withDescriptors) async { /* ... */ }

// After (3.0)
@override
Future<List<BleService>> discoverServices(
  String deviceId,
  bool withDescriptors, {
  DiscoverServicesPlatformConfig? platformConfig,
}) async { /* ... */ }
```

**`bleConnectionChangeStreamController` now carries `BleConnectionChange`** instead
of a record, and `updateConnection` gained optional `errorCode` / `nativeErrorCode`:

```dart
platform.updateConnection(
  deviceId,
  false,
  'link lost',                          // error (optional)
  UniversalBleErrorCode.deviceDisconnected, // errorCode (optional, new)
  0x13,                                 // nativeErrorCode (optional, new)
);
```

**`onConnectionChange`** (the field you call from `updateConnection`) is now typed
`void Function(BleConnectionChange)`, **`onValueChange`** is typed
`void Function(BleCharacteristicValue)`, and **`onConnectionParametersChange`**
now receives a `BleConnectionParametersChange`. Update any mock that implements
them. Remember to emit device IDs in the canonical lower-case form (see section 2),
including IDs pushed directly onto exported stream controllers.

## Additive changes you can adopt (optional)

- `UniversalBle.canonicalDeviceId(deviceId)` — the comparable form of an ID for
  the current platform (lower-case on native, verbatim on Web); useful when
  keying a map or comparing an ID that came from your own storage.
- `requestDevice` — unified native device picker: the browser's Bluetooth chooser
  on Web and the AccessorySetupKit picker on iOS 18+ (configured via
  `PickerPlatformConfig.apple` / `AppleAccessorySetupOptions`), returning the
  selected `BleDevice`.
- `UniversalBle.discoverServices(..., platformConfig: DiscoverServicesPlatformConfig(android: AndroidDiscoverServicesOptions(clearGattCache: true)))`
  — drop Android's GATT cache before discovery when the peripheral's layout
  changed and it does not send a Service Changed indication. New types
  `DiscoverServicesPlatformConfig` and `AndroidDiscoverServicesOptions` are exported.
- `connectionChangeStream` / `BleDevice.connectionChangeStream` (above).
- `isSubscribed` and `getSubscribedCharacteristics` (added in 2.3) to inspect
  notification/indication state without tracking it yourself.

## Migration checklist

- [ ] Upgraded `universal_ble` to `^3.0.0`.
- [ ] Confirmed no code depended on global cross-device queue serialization; set
      `QueueType.global` explicitly if it did.
- [ ] Fixed exhaustive `switch` statements over `QueueType` to include `auto`.
- [ ] Reviewed code that stored or compared emitted device IDs by exact case, and
      normalised it with `UniversalBle.canonicalDeviceId` (Web IDs stay verbatim —
      do not blanket lower-case).
- [ ] Rewrote every `onConnectionChange` handler to take a `BleConnectionChange`,
      and every `onValueChange` handler to take a `BleCharacteristicValue`.
- [ ] Renamed `BleConnectionParametersUpdated` references to
      `BleConnectionParametersChange`.
- [ ] Confirmed `unpair` usage on iOS 18+ no longer expects `notSupported`, and
      handles `deviceNotFound` for devices outside AccessorySetupKit.
- [ ] Adopted `errorCode` (not `error`) for connection-failure branching.
- [ ] Updated any `UniversalBlePlatform` override/mock for the new signatures and
      canonical device-ID emission.
- [ ] `flutter analyze` and tests pass.

Related skills: `universal-ble-setup` for a fresh integration, and
`universal-ble-migrate-from-flutter-blue-plus` when coming from
`flutter_blue_plus`.
