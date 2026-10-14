## 3.0.1
* Bump `flutter_web_bluetooth` to `^1.2.0`.
* Web: use the dependency's advertisement abort controller and `startupTimeout` instead of the hand-rolled abort/timeout workaround. `unwatchAdvertisements` now also aborts a pending advertisement startup.

## 3.0.0
* **Breaking:** Add `QueueType.auto` which auto-selects the best queueing strategy per platform: Android, Web, and Linux use a per-device queue (their BLE stacks reject or misbehave on overlapping operations), while all other platforms run commands in parallel. It is now the default for both `UniversalBle` and `UniversalBlePeripheral`, replacing the previous `QueueType.global` default. Any exhaustive `switch` over `QueueType` must handle the new `auto` value.
* **Breaking:** Device IDs are now emitted in lower-case on every platform (scan results, connection/value/pairing/connection-parameter callbacks and streams). Previously each platform reported its native case — Android upper-cased MACs, Windows/WinRT lower-cased them. IDs are now canonicalised to lower-case throughout the Dart layer; the native side converts back to the case it requires at its boundary (Android's `getRemoteDevice` needs upper-case). Callers that stored or compared an emitted ID by exact case (e.g. an Android upper-case MAC) must now lower-case it, or compare case-insensitively. Web is exempt: Web Bluetooth IDs are opaque, case-sensitive browser tokens rather than addresses, so they are emitted and matched verbatim. Follow-up to the case-insensitive matching in 2.1.1. Custom `UniversalBlePlatform` implementations must report the canonical form too: the event-stream filters now match the canonical id directly, so a platform that pushes a non-canonical id straight onto the exported stream controllers (instead of calling the `update*` handlers, which canonicalise) will no longer match a query made with a different casing. The same applies to peripheral mode: central device IDs in `UniversalBlePeripheral` streams, read/write request handlers, and `getSubscribedClients` results are emitted in lower-case, and IDs passed to `updateCharacteristicValue` / `getMaximumNotifyLength` are accepted in any case.
* **Breaking:** `onConnectionChange` now receives a single `BleConnectionChange` (`deviceId`, `isConnected`, `error`) instead of three positional arguments. It also carries a unified `errorCode` (`UniversalBleErrorCode.deviceDisconnected`, `connectionTimeout`, `connectionFailed`, ...) and the raw `nativeErrorCode` (`CBError.Code` on Apple, GATT status on Android); a connection attempt that never succeeds is `connectionFailed` on both. Add `connectionChangeStream` and `BleDevice.connectionChangeStream` emitting the same updates per device; `connectionStream` is unchanged. `UniversalBlePlatform.bleConnectionChangeStreamController` (internal) now carries `BleConnectionChange` instead of a record.
* **Breaking:** `onValueChange` now receives a single `BleCharacteristicValue` (`deviceId`, `characteristicId`, `value`, `timestamp`) instead of four positional arguments.
* **Breaking:** Rename `BleConnectionParametersUpdated` to `BleConnectionParametersChange`, aligning the payload with the `…Change` event naming. The `onConnectionParametersChange` callback and the model's fields are unchanged.
* **Breaking:** On iOS 18+ `unpair` now removes an accessory authorized through AccessorySetupKit (it previously threw `notSupported` on iOS). Devices not managed by AccessorySetupKit fail with `deviceNotFound`.
* iOS/macOS/Web: `onPairingStateChange` / `pairingStateStream` now fire. These platforms have no native bond API, so `pair()` drives them from its encrypted-characteristic probe: `true` when the probe succeeds, a failure event (`false`) when it throws. Without a `pairingCommand` the probe reads every readable characteristic and now fails if none can be read, rather than resolving successfully. The 0.12.0 changelog claimed this support, but the callback was never actually wired on those platforms until now.
* `requestMtu` now discovers the device's services on demand on iOS/macOS and Linux, instead of returning a misleading MTU (Apple reported the default ATT MTU, 23, as if it were the negotiated value) or failing with an unclear `operationNotSupported` (Linux). It is a no-op when the services were already discovered, so calling `discoverServices` first still works and is not required, and concurrent calls (including one racing a `discoverServices`) share a single discovery. `timeout` bounds each step, so a call that must discover first can take up to roughly twice `timeout`. Android and Windows read the MTU off the connection itself and are unchanged. Add `BleCapabilities.mtuRequiresServiceDiscovery`.
* Add `requestDevice`, a single entry point for the platform's native device picker: the browser's Bluetooth chooser on Web and the iOS 18+ AccessorySetupKit picker on Apple (configured via `PickerPlatformConfig.apple`), returning the selected `BleDevice`. Connect it with the existing `connect(device.deviceId)`. `AppleAccessorySetupOptions` holds a list of `AppleAccessoryPickerItem`s, so the picker can offer several accessories. Platforms without a native picker throw `notSupported`.
* Windows: enable extended BLE advertisement scanning (`AllowExtendedAdvertisements`), with graceful fallback on unsupported OS versions or adapters.
* Add `skipDuplicates` to `startScan` to report each device only once per scan session — later sightings, including ones whose advertisement payload changed, are suppressed until the scan is restarted. Native filtering is applied where available (iOS/macOS, Android `ScanSettings`, Linux BlueZ `DuplicateData`) and the Dart layer de-duplicates on every platform so the behavior is consistent everywhere. Defaults to `false` (unchanged).
* Add `connectable` property to `BleDevice`.
* Add `connectableOnly` to `ScanFilter` to filter for connectable devices during scanning.
* Windows: Expose non-connectable devices during scanning to match other platforms.
* Windows: deliver scan responses as scan results. A peripheral that publishes its 128-bit service UUID in the scan response (it does not fit in the advertisement next to the name) was invisible to `startScan`: Windows reports that packet with `IsConnectable == false` and it was dropped before reaching the caller.
* Enhance `Uint8List` and `Future<Uint8List>` extensions with comprehensive BLE data type conversions (`int8`, `uint8`, `int16`, `uint16`, `int32`, `uint32`, `float32`, `float64`, `toUtf8`, `toHexString`), byte offset support, and direct `byteData` view accessor.
* Add `UniversalBle.canonicalDeviceId(deviceId)`, which returns a device ID in the comparable form for the current platform (lower-case on native platforms, verbatim on Web) — for keying a map or comparing IDs yourself.
* Add `subscribedCentralsStream` and `subscribedCentrals` getter to `UniversalBlePeripheral` to track and expose active central devices (`BleCentral`) subscribed to characteristics in peripheral mode.
* Add `platformConfig` to `discoverServices()`; `AndroidDiscoverServicesOptions(clearGattCache: true)` clears Android's GATT cache (`BluetoothGatt.refresh()`) before discovery. Ignored on other platforms.
* Add `universal_ble` package skills installable with `dart run skills@ get`: `universal-ble-setup` (add BLE to an app from scratch), `universal-ble-migrate-2-to-3` (upgrade from 2.x), and `universal-ble-migrate-from-flutter-blue-plus` (migrate from `flutter_blue_plus`).
* Android/iOS/macOS/Windows: keep the GATT client cache per plugin instance (one per FlutterEngine). It was process-wide, so a `connect()` from one engine could short-circuit on a client created by a destroyed engine — returning a connection that reported as connected but whose service discovery came back empty. Each engine now sees only its own clients, and `closeGattOnDetach` releases only the clients the detaching engine created instead of every client in the process.
* Android: Register MTU waiters before the native request, serialize completions onto the main looper, and fail rejected requests immediately.
* Android: Reuse an MTU already negotiated on the current GATT connection; isolate reconnects from late callbacks.
* Android: report every failed bond — including a declined system-initiated bond that ends in `BOND_NONE` — not only the first per process. A failed pairing attempt is an event rather than a state, so `onPairingStateChange` no longer de-duplicates it against the cached pairing state (#325).
* iOS/macOS: Handle write-without-response transmit buffer backpressure
* iOS/macOS: complete concurrent reads, descriptor operations, notification changes, and RSSI reads one callback at a time.
* Windows: dispose disconnected WinRT GATT objects on a background MTA thread to avoid blocking the UI during teardown.
* Windows: retry transiently unreachable GATT service discovery during connection.
* Windows: fix crashes when closing the app while Bluetooth initialization is still pending.
* Extend Windows HIL/FIT coverage for indications, long values, resource pressure, and deterministic timing sweeps using fixture v2.
* Web: await advertisement cleanup before connecting, bound connection setup by its timeout, and prevent cancelled setup or stale GATT discovery from affecting a later connection.
* Preserve typed BLE error codes when wrapping an existing BLE exception.

## 2.3.0
* Add `isSubscribed` and `getSubscribedCharacteristics` to check characteristic notification/indication subscription status in Central mode.
* Apple: Accurately report manufacturer-data advertising capabilities.
* Windows: support connectionless manufacturer-data advertising without a GATT service, including state/error reporting and cleanup on stop/disposal.
* Android: add `closeGattOnDetach` connection option to release GATT clients when the app is killed
* readRssi commands are not queued anymore
* Android: close the GATT client once the disconnect completes instead of right after `disconnect()`, and report the real disconnect status
* Android: Fix peripheral `getReadinessState()` to check permissions and adapter power before advertising support, and throttle `startAdvertising` Bluetooth enable prompts to at most one dialog.
* iOS/macOS: complete only the oldest matching pending write on didWriteValueFor

## 2.2.0
* Expose microsecond scan timestamps captured before Flutter event dispatch
* Lower minimum Dart SDK to 3.3 (Flutter 3.19+) to restore compatibility with older stable Flutter releases
* Add `BleCommandQueue` support to `UniversalBlePeripheral` (`queueType`, `timeout`, `clearQueue`, and `onQueueUpdate`)
* Add Descriptor Read and Write APIs
* iOS/macOS: Handle CoreBluetooth peripheral transmit queue exhaustion and error handling in `updateCharacteristicValue`
* Windows: Harden BLE connection lifetime and asynchronous callbacks
* Windows: Harden GATT operation lifetimes, Service Changed handling, and notification subscriptions
* Android: instantly close the GATT client on disconnect
* Android: complete only the oldest matching pending write on onCharacteristicWrite
* iOS/macOS: Handle service discovery failure and timeout to prevent poisoning subsequent `discoverServices` calls

## 2.1.1
* Handle device IDs case-insensitively
* Fix `BleCharacteristic` equality and `hashCode` to compare `properties` by value
* Android: Fix BluetoothDevice null-safety compile error under Kotlin 2.x
* Android: Make Android write-completion delivery thread-safe

## 2.1.0
* Add optional `queueId` parameter to all APIs
* iOS/macOS: add opt-in `AppleConnectionOptions` to `connect` (via `ConnectionPlatformConfig`) — map to `CBConnectPeripheralOptionNotifyOnConnectionKey`, `NotifyOnDisconnectionKey` and `NotifyOnNotificationKey`, so a suspended app is relaunched into the background to handle connection events (e.g. auto-reconnect while the phone is locked)
* Android: add `legacy` to `AndroidOptions` — set `legacy: true` to scan legacy BLE 4.x advertisements (e.g. ESP32) on API 26+; default (`null`/`false`) keeps extended-advertisement scanning unchanged from prior releases
* Android: add `addServicesInScanResponse` to `PeripheralAndroidOptions` - set `addServicesInScanResponse: true` to Put advertised service UUIDs in the scan response instead of the primary advertisement
* Android: merge manufacturer data with duplicate company id in scan results

## 2.0.4
* iOS: make Bluetooth state restoration optional by enabling it only when the `bluetooth-central` background mode is declared
* iOS: when state restoration is enabled, init `CBCentralManager` at launch only if Bluetooth permission is granted

## 2.0.3
* iOS/macOS: defer `CBPeripheralManager` creation until peripheral APIs are used, fixing Bluetooth permission prompt on app launch
* iOS: add CoreBluetooth state preservation/restoration so the app can be relaunched in the background by a connected peripheral and resume the live connection. Requires the `bluetooth-central` background mode in `Info.plist` (see README → Permissions → iOS / macOS).
* Android: Fix missing scan name after reconnection
* Windows: Fix null pointer crash when BLE device is unpaired during active scan
* Windows: Refactor property value lookups to use a safe lookup function
* Fix Dart primary constructor compatibility

## 2.0.2
* iOS/macOS: retain peripheral from retrievePeripherals to fix API MISUSE on connect
* Android: migrate to built-in Kotlin (removes Kotlin Gradle Plugin usage)
* Use conditional imports for the Linux backend so the package is compatible with the WASM runtime on pub.dev

## 2.0.1
* Add `onConnectionParametersChange` to notify when Android link-layer connection parameters change (API 26+)
* Android peripheral: eager Kotlin initialization, thread-safe GATT connection cache, and pairing only via `pair()` or when encryption requires it
* Android: expose `callbackType`, `matchMode`, and `numOfMatches` on `AndroidOptions` so callers can configure `ScanSettings` to defeat aggressive chip-side advert de-duplication on Pixel devices. `callbackType` accepts a `List<AndroidScanCallbackType>` (OR-folded on the native side) and includes a new `allMatchesAutoBatch` value (API 34+).

## 2.0.0
* Add peripheral mode on Android, iOS, macOS, and Windows
* Add `requestConnectionPriority` to allow tuning BLE connection intervals on Android
* Add SPM support on Apple

## 1.2.0
* Add `autoConnect` parameter to `connect()` method for automatic reconnection support on Android and iOS/macOS
* Add `serviceData` in `BleDevice`
* Add `AndroidScanMode` and `reportDelayMillis` to `AndroidOptions` for scanning
* Add support for BLE scanning from background services (ForegroundTask) on Android. `PermissionHandler` is now activity-aware and succeeds silently if permissions are already granted when no activity is available
* Add serviceData tracking in Linux advertisements
* Always use custom scan filter on Windows
* Fix Windows crash by handling WinRT exceptions in BLE callback paths

## 1.1.0
* Add readRssi method

## 1.0.1
* Enforce C++20 standard for Windows builds

## 1.0.0
* BREAKING CHANGE: `OnValueChange` callback also includes timestamp
* BREAKING CHANGE: Bump minimum IOS version to 13.1
* BREAKING CHANGE: Bump minimum MacOS version to 10.15
* Unified error codes for all platforms
* Add `isScanning` api
* Add `hasPermissions` api
* Add `requestPermissions` api and auto ask permission on `startScan`
* Add `withDescriptors` parameter in `discoverServices` API
* Add `timestamp` in `BleDevice`
* Add `setLogLevel` api for configuring logs
* `disconnect` now waits for disconnection confirmation before returning
* Improve Windows disconnection event handling and cleanup
* Fix Windows 11 crash on cancelling pairing

## 0.21.1
* Fix device name resolution on Windows
* Add `exclusionFilters` to filter out devices from scan results

## 0.21.0
* BREAKING CHANGE: `connectionTimeout` argument from `connect`, `isPaired` and `pair` API renamed to `timeout`
* Add `timeout` argument to all APIs
* Add `clearQueue()` API

## 0.20.2
* Fix `BleCharacteristic.onValueReceived`

## 0.20.1
* Fix `writeWithoutResponse()` which was not properly waiting for completion on Android and Apple

## 0.20.0
* BREAKING CHANGE: `bleDevice.isPaired` is now `bleDevice.paired`
* Add new high level API. Services are auto-discovered. the BleDevice class offers convenient member methods and properties.
* Deprecate `readValue` in favor of `read`
* Deprecate `writeValue` in favor of `write`
* Deprecate `setNotifiable` in favor of `subscribeNotifications`, `subscribeIndications`, `unsubscribe`
* Fix `getBluetoothAvailabilityState` reporting wrong Bluetooth status on browsers where Web Bluetooth can globally be disabled
* `startScan` on web now throws a `WebBluetoothGloballyDisabled` exception if scanning cannot proceed due to Web Bluetooth being globally disabled
* EXAMPLE APP: Migrate to the new high level API

## 0.19.0
* Get and prefer advertised name of scanned devices on Apple
* Cache and return advertised name for system devices on Apple
* Improve Android runtime permissions docs
* Add app showcase in Readme
* EXAMPLE APP: Don't disconnect on leaving the details page
* EXAMPLE APP: Fix Android builds
* EXAMPLE APP: Fix service filter warning on macOS
* EXAMPLE APP: Add types to callbacks

## 0.18.0
* Add Streams: `scanStream`, `availabilityStream`, `connectionStream`, `characteristicValueStream`, `pairingStateStream`
* Fix `connect` api bug to detect proper connection state
* Fix `getSystemDevices()` on Linux
* Improve docs for isPaired

## 0.17.0
* Fix Windows crash when calling pair APIs with an unknown deviceId
* Fix Windows crash when calling startScan again after some time
* Fix Windows warning `Unable to establish connection on channel` when hot restarting
* Refactor native Windows code
* Improve Android permission documentation

## 0.16.0
* BREAKING CHANGE: `payload` is now `payloadPrefix`
* BREAKING CHANGE: `mask` is now `payloadMask`
* Bump bluez to 0.8.3
* Do not normalize UUIDs on native side
* Reverse _permissionStatus return values in example app
* Improve readme
* Improve ManufacturerDataFilter

## 0.15.0
* `getSystemDevices(withServices:)` now sets several generic services by default as filter
* `getConnectionState` on Android will now return `BleConnectionState.disconnected` if device is connected to the system but not to the app
* Improve callback error handling

## 0.14.0
* BREAKING CHANGE: `bleDevice.name` now filters out non-printable characters
* Add `bleDevice.rawName`
* Add `disableBluetooth` API
* Bump flutter_web_bluetooth to 1.0.0
* Fix Apple CBCentralManager lazy initialization on `startScan`
* Fix Android error `scan too frequently` and auto retry scan once sufficient time has passed
* Fix duplicate `onValueChanged` events on Android 11 or earlier
* Fix Windows `withServices` filter
* Fix Windows Bluetooth availability state in release builds
* Throw error on Apple if Bluetooth permission is denied on `startScan`
* Do not throw `Characteristic already notifying` error. Subscribing to characteristic notifications multiple times is now handled safely

## 0.13.0
* BREAKING CHANGE: `scanFilter` filters are now in OR relation 
* BREAKING CHANGE: `manufacturerDataHead` is removed from `BleDevice`
* BREAKING CHANGE: `WebConfig` is now `WebOptions`
* BREAKING CHANGE: `ManufacturerDataFilter.data` is now `ManufacturerDataFilter.payload`
* BREAKING CHANGE: `connect()` does not return a boolean anymore. It will throw error on connection failure
* BREAKING CHANGE: `pair()` does not return a boolean anymore. It will throw error on connection failure
* BREAKING CHANGE: `onConnectionChange` returns error as well
* BREAKING CHANGE: rename in-app pairing capabilities
* Deprecation: `manufacturerData` is deprecated in BleDevice and will be removed in the future
* Add `manufacturerDataList` as `List<ManufacturerData>` in `BleDevice`
* Use `ManufacturerData` object instead of `Uint8List` for manufacturerData
* Add `connectionStream` API to get connection updates as stream
* Auto convert all services passed to `getSystemDevices()`
* Improve `scanFilter` handling
* Return false for receivesAdvertisements on Linux/Web
* Add 1s delay in discoverServices on Linux

## 0.12.0
* BREAKING CHANGE: `unPair` is now `unpair`
* BREAKING CHANGE: `onPairingStateChange` does not return error anymore
* Add `pair()`, `isPaired` and `onPairingStateChange` support for Apple and web
* `connect()` and `pair()` now return a bool result
* Add `PlatformConfig` property in `StartScan`
* Add `WebConfig` property in `PlatformConfig`
* Fix notifications for characteristics without cccd on Android
* Promote Linux to stable

## 0.11.1
* Trim spaces in UUIDs
* Receive advertisement events on web
* Improve cleanup after disconnection on web

## 0.11.0
* Unify UUID format across all platforms, 128-bit lowercase
* Add BleUuidParser utility methods for UUID parsing

## 0.10.1
* Improve Android error handling
* Improve cleanup after disconnection on Apple and Android
* Improve code level documentation
* Support pairing on Apple
* Fix Android disconnection events sometimes missed

## 0.10.0
* BREAKING CHANGE: `ScanResult` is now `BleDevice`
* BREAKING CHANGE: `getConnectedDevices` is now `getSystemDevices`
* BREAKING CHANGE: `isPaired` is now nullable
* BREAKING CHANGE: `onValueChanged` is now `onValueChange`
* BREAKING CHANGE: `onConnectionChanged` is now `onConnectionChange`
* Add `connectionState` property to BleDevice
* Add `isSystemDevice` property to BleDevice
* Add `.perDevice` queue
* Support "ProvidePin" pairing on Windows 10/11
* Get RRSI updates on Apple platforms
* Improve enum parsing performance
* Improve code level documentation

## 0.9.11
* Add device name prefix filtering

## 0.9.10
* Fix Windows scan filter
* Remove scan result caching on Windows
* Improve service discovery on Linux
* Use asynchronous callbacks for SetNotifiable
* Remove dependency on `convert`
* Remove dependency on `collection`
* Update Android example app Gradle

## 0.9.9
* Improve service discovery on Apple
* Improve reconnection on Apple
* Persist long scan result name on Windows
* Fix Android serviceUuids in scanResults
* Example app improvements

## 0.9.8
* Improve manufacturer data discovery on Windows
* Example app improvements

## 0.9.7
* Fix characteristic keying on linux allowing receiving data from multiple BLE devices at the same time

## 0.9.6
* Fix a Windows issue where characteristics of certain services would not be discovered
* Improve readme

## 0.9.5
* Windows support has graduated from beta to stable
* Support filtering by manufacturer data
* Unify web's optionalServices API with filtering API
* Implement requestMtu in Linux 
* Fix wrong manufacturer data in Windows release builds
* Improve logging

## 0.9.4
* Fix Windows crash when no Bluetooth adapter is present

## 0.9.3
* Add scan filter (withServices:) in `startScan()`
* Add service UUIDs from advertisements in `BleScanResult`
* Fix Windows release build compilation

## 0.9.2
* Add command queue
* Improve error handling on Android, iOS, macOS, Windows, Linux and web

## 0.9.1
* Improve logging

## 0.9.0
* Improve windows device name discovery
* Improve linux implementation
* Improve titles in example app

## 0.8.4
* Add `WebRequestOptionsBuilder.defaultServices` for convenience when setting `optionalServices` when scanning on web
* Add "try online" URL in readme
* Improve readme
* Improve example app

## 0.8.3
* Rename onPairStateChange *> onPairingStateChange
* Improve readme

## 0.8.2
* Improve readme

## 0.8.1
* Update supported platforms

## 0.8.0
* Initial release
