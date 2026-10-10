---
name: universal-ble-migrate-2-to-3
description: >-
  Migrate a Flutter app from universal_ble 2.x to 3.0. Use when upgrading
  universal_ble to ^3.0.0 and fixing its breaking changes: the QueueType.auto
  default, the onConnectionChange callback now receiving a BleConnectionUpdate,
  the new connectionUpdateStream, or custom UniversalBlePlatform implementations
  that no longer compile. Also use when a queue no longer serializes commands the
  same way, an onConnectionChange handler fails to compile, or a custom platform
  mock is missing parameters after the upgrade.
---

# Migrating universal_ble 2.x → 3.0

3.0 is a small, focused release. There are three breaking changes; everything
else in 3.0 is additive.

## Breaking changes at a glance

| # | Change | Affects |
| --- | --- | --- |
| 1 | `QueueType.auto` added and now the default (was `QueueType.global`) | Command execution order; exhaustive `switch` over `QueueType` |
| 2 | `onConnectionChange` now receives a single `BleConnectionUpdate` | Every app using the callback |
| 3 | `UniversalBlePlatform` interface signatures changed | Custom platform implementations / mocks (`UniversalBle.setInstance`) |

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

## 2. `onConnectionChange` now receives a `BleConnectionUpdate`

The callback signature changed from three positional arguments to one object that
also carries the native error details.

```dart
// Before (2.x)
UniversalBle.onConnectionChange = (String deviceId, bool isConnected, String? error) {
  debugPrint('$deviceId connected=$isConnected error=$error');
};

// After (3.0)
UniversalBle.onConnectionChange = (BleConnectionUpdate update) {
  debugPrint('${update.deviceId} connected=${update.isConnected} '
      'error=${update.error} code=${update.errorCode}');
};
```

`BleConnectionUpdate` fields:

- `deviceId`, `isConnected` — same meaning as before.
- `error` — human-readable text, `null` when the change was app-initiated.
- `errorCode` — unified `UniversalBleErrorCode` (e.g. `deviceDisconnected`,
  `connectionTimeout`, `connectionFailed`); `null` where the platform reports no code.
- `nativeErrorCode` — raw platform value (`CBError.Code` on Apple, GATT status on
  Android); use `errorCode` for branching, keep this for diagnostics.

There is also a new per-device stream that emits the same objects:

```dart
UniversalBle.connectionUpdateStream(deviceId).listen((update) { /* ... */ });
// or, from a BleDevice:
bleDevice.connectionUpdateStream.listen((update) { /* ... */ });
```

**`connectionStream` is unchanged** — it still emits `bool`. If you only need
connect/disconnect, keep using it; migrate to `connectionUpdateStream` only when
you need the error code or reason. Prefer `errorCode` over `error` for logic,
since the text is platform-dependent and localized on Apple.

## 3. Custom `UniversalBlePlatform` implementations

Only relevant if you extend `UniversalBlePlatform` (e.g. a mock via
`UniversalBle.setInstance`). Three signatures changed:

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

**`bleConnectionUpdateStreamController` now carries `BleConnectionUpdate`** instead
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
`void Function(BleConnectionUpdate)`. Update any mock that implements it.

## Additive changes you can adopt (optional)

- `UniversalBle.discoverServices(..., platformConfig: DiscoverServicesPlatformConfig(android: AndroidDiscoverServicesOptions(clearGattCache: true)))`
  — drop Android's GATT cache before discovery when the peripheral's layout
  changed and it does not send a Service Changed indication. New types
  `DiscoverServicesPlatformConfig` and `AndroidDiscoverServicesOptions` are exported.
- `connectionUpdateStream` / `BleDevice.connectionUpdateStream` (above).
- `isSubscribed` and `getSubscribedCharacteristics` (added in 2.3) to inspect
  notification/indication state without tracking it yourself.

## Migration checklist

- [ ] Upgraded `universal_ble` to `^3.0.0`.
- [ ] Confirmed no code depended on global cross-device queue serialization; set
      `QueueType.global` explicitly if it did.
- [ ] Fixed exhaustive `switch` statements over `QueueType` to include `auto`.
- [ ] Rewrote every `onConnectionChange` handler to take a `BleConnectionUpdate`.
- [ ] Adopted `errorCode` (not `error`) for connection-failure branching.
- [ ] Updated any `UniversalBlePlatform` override/mock for the new signatures.
- [ ] `flutter analyze` and tests pass.

Related skills: `universal-ble-setup` for a fresh integration, and
`universal-ble-migrate-from-flutter-blue-plus` when coming from
`flutter_blue_plus`.
