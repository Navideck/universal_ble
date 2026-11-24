## 3.4.1
* Android: a `setNotifiable` call whose CCCD write throws now fails with a classified error instead of being left pending. The old code withdrew the pending result twice — once in the inner handler and again in the outer one — so the second withdrawal found nothing to fail and the Dart call hung until its timeout. The CCCD write is now one helper, and the request is withdrawn once before its single reply.
* Linux: a read, write, descriptor read/write or subscription submitted while the device is disconnected now fails with `deviceDisconnected` instead of `characteristicNotFound` or a generic `readFailed`/`writeFailed`. BlueZ drops the GATT object tree together with the link, so the lookup used to report the characteristic as unknown — as if the device had changed its services — and a request that reached D-Bus failed with `NotConnected` under a generic code (#394).
* Web: the same requests now fail with `deviceDisconnected` instead of surfacing the browser's `NetworkError` as an unclassified error, and an unknown device reports `deviceNotFound` instead of a missing characteristic. The service cache is cleared on disconnection, so the lookup previously failed before the browser could say the link was gone (#394).
* Windows: the same requests now fail with `deviceDisconnected` when the link is down but the connection-status callback has not removed the client yet. The operation used to be submitted anyway and completed with `Unreachable`, which surfaced as `failed` (#394).
* Apple: reads, writes, descriptor reads and writes, and subscriptions now check `CBPeripheral.state` before the characteristic or descriptor lookup, so a request on a disconnected peripheral fails with `deviceDisconnected`. CoreBluetooth discards a peripheral's attribute tree when the link drops, so with the previous lookup-first order the caller got `characteristicNotFound` for a characteristic it had just used. The check now runs first, as it already did on Linux and Web; an unknown characteristic on a connected peripheral still reports `characteristicNotFound` (#394).
* Android and Windows: the link check now runs before the characteristic and descriptor lookup too, so a read, write, descriptor read/write or subscription on a known but disconnected device reports `deviceDisconnected` even when the cached attribute tree no longer holds the characteristic. Previously the lookup won and the answer depended on the platform. Android's submission gate keeps its lock-protected check as the authoritative one for the race described above (#394).
* Apple: MTU requests and RSSI reads now refuse a disconnected peripheral with `deviceDisconnected` instead of reaching CoreBluetooth, matching Android. Service discovery already refused one and now uses the same "Device Disconnected" message, so the set of gated calls is identical on both platforms (#394).
* Android: a read, write, descriptor read/write, notification subscription, MTU request, service discovery or RSSI read submitted to an `autoConnect` client after its link dropped now fails right away with `deviceDisconnected` instead of reaching the stack. The client stays open and keeps its cached services after the link loss, and below API 33 the stack accepts such a request and then drops it without a callback, leaving a pending entry that the first callback of the reconnected link completes — so every later write lagged by one and timed out after 10 s, giving about one write per timeout. The link check shares the lock with the disconnect cleanup, so a request submitted concurrently is either registered in time to be swept or refused; as a backstop, a client whose link comes back fails anything still pending from the previous link before the new link starts accepting requests. `readDescriptorValue`, `readRssi` and `discoverServices` register their pending result before issuing the operation, as `readValue` already did. A subscription to a characteristic without a CCCD is refused the same way. All of this needs the system to report the disconnection, which the plugin cannot infer on its own (#394).

## 3.4.0
* Subscription state is now tracked per characteristic instance instead of per characteristic UUID, so a device that exposes the same UUID in several services no longer reports every instance as subscribed when one is, and unsubscribing one instance no longer clears the state that describes the others. `UniversalBle.isSubscribed` and `UniversalBle.getSubscribedCharacteristics` take an optional `serviceId` to ask about one service; without it they keep the previous answer, which is `true` when any service exposes the characteristic, and `BleCharacteristic.isSubscribed` now uses the characteristic's own service. `getSubscribedCharacteristics` still returns deduplicated UUIDs, now sorted rather than in subscription order (#393).
* Characteristic values now carry the UUID of the service that owns the characteristic, so two characteristics with the same UUID in different services are told apart. The Pigeon `onValueChanged` callback passes the service, `BleCharacteristicValue` gains `serviceId`, `characteristicValueStream` takes an optional `serviceId` filter, and `BleCharacteristic.onValueReceived` uses the characteristic's own service automatically. Android, Apple, Windows, Linux and Web report the owning service. A value whose service a platform does not report — a custom platform implementation, or an unusable service id — still reaches a service-filtered stream, so existing callers and platforms keep their behaviour (#391).
* BREAKING CHANGE: an out-of-tree `UniversalBlePlatform` that overrides `characteristicValueStream` or `updateCharacteristicValue` must add the new optional `serviceId` parameter to its override — the base signatures gained it, and an override cannot omit a named parameter. Callers of the public API are unaffected: the parameter is optional, `BleCharacteristicValue.serviceId` is additive, and `onValueChange` keeps its shape (#391).
* Android: a write or descriptor write that the stack refuses by throwing now fails that call with a classified error and withdraws its pending result, so the next completion is no longer delivered to an orphaned future and every later write stops lagging by one and timing out. The realistic trigger is Android 15+, where `BluetoothGatt.writeCharacteristic(characteristic, value, writeType)` throws `IllegalArgumentException` for an attribute value longer than 512 bytes; a value that long is now rejected before it reaches the stack with `invalidAttributeLength` (#387).
* Android: report an unknown (`null`) connectability state instead of crashing on the first scan result on Android 7.x and older. `ScanResult.isConnectable()` is API 26+, so reading it unguarded on the plugin's `minSdkVersion 21` threw `NoSuchMethodError` for every result on API 21-25 (#383).
* Android peripheral: `removeService` and `clearServices` now drop the cached state that described the services they took off the server — characteristic lookups, instance ids, descriptor and per-client CCCD values, and subscriptions — so a service registered again in the same session notifies through its new characteristics instead of orphaned ones, and `findService` no longer resolves the old registration. Only the removed service's own state is dropped: when another registered service exposes the same characteristic UUID, the UUID keeps resolving to it and its CCCD values and subscriptions are kept, and the caches are cleared even when the server call throws. Characteristic instance ids may also contain any character now that the per-client CCCD cache is no longer keyed by a delimited string (#385).
* Android peripheral: the plugin now listens for `BluetoothAdapter.ACTION_STATE_CHANGED` and drops the GATT server, the advertiser and the state that belongs to that adapter session when Bluetooth turns off, so the next `addService`/`startAdvertising` re-opens them instead of failing with "Service registration rejected". The drop reports what it took away, so an app can resynchronise: every connected central is emitted as disconnected and advertising moves from `STARTING`/`ADVERTISING`/`STOPPING` to `IDLE` with a "Bluetooth turned off" message. A rejected registration is only retried on a freshly opened server when the current one was opened in an earlier adapter session; a server that merely refuses a service it already holds — a hot restart or a duplicated `addService` — is left alone instead of losing every other service, every client and advertising. If the retry itself fails, the original rejection is still the error that is reported (#384).
* Android peripheral: `dispose()` is idempotent and tolerates a receiver that cannot be unregistered, detaching the engine no longer aborts its teardown when the adapter is unavailable, and a failed adapter-name restore is retried on the next `STATE_ON` instead of being forgotten.
* Windows: read `BluetoothLEAdvertisementReceivedEventArgs.IsConnectable` through a queried `IBluetoothLEAdvertisementReceivedEventArgs2` instead of the C++/WinRT `require` projection. When the interface is missing, the unguarded call dereferenced null instead of throwing, so it killed the process with an access violation that the `catch (...)` and Dart code could never see. A failed query now reports an unknown (`null`) connectability state, so `connectableOnly` keeps passing the device, and the fallback is logged once per process (#373).
* Disconnect bypasses blocked GATT command queues and cancels unsent commands for the target device, preserving queued work for other devices. Two consequences are visible to callers: `disconnect`'s `queueId` argument is now ignored (and deprecated with an annotation, scheduled for removal in 4.0.0), so a disconnect no longer waits behind that queue, and the cancelled commands fail with a `UniversalBleException` carrying `UniversalBleErrorCode.operationCancelled` and the canonical device id in `details`, instead of a bare `Exception('Queue Cancelled')`. The command that is already running is not interrupted: it completes normally, and only commands still waiting are cancelled. That typed error now also covers commands cancelled by `clearQueue()`. Because cancellation completes the command's future with an error, a command started without awaiting it now reports an unhandled async error on every `disconnect` that cancels it — await it or attach a `catchError` handler.
* Android: bind pending reads, writes, descriptor operations, RSSI, service discovery and notification subscriptions to their submitting GATT, so a callback or cleanup from a replaced client cannot consume a newer request for the same address. A discovery from a superseded client no longer updates the service cache, and a CCCD callback whose descriptor was rebuilt by a discovery still completes its subscription. Connection state, connection parameters and notifications reported by a client that a newer `connect()` replaced are ignored, as are notifications from the client `disconnect()` is closing until its `STATE_DISCONNECTED` arrives, so a link that is being torn down no longer reports values, or a stale `disconnected` event, as the current connection's (#381).
* Apple: bind pending writes to the submitting peripheral object. A write or `peripheralIsReady` callback, and the cleanup after a disconnection, are matched to a request by object identity, so they cannot consume a replacement peripheral’s request. A pending write is now failed with `deviceDisconnected` when its owner is not the object the plugin routes the device’s callbacks to, or when that owner is not connected; that happens when the device disconnects, when `connect` runs, and when the app writes to it again, and covers a superseded object whose `state` still reads `.connected`. A write submitted through a replaced peripheral therefore fails right away with the message “Peripheral replaced” instead of waiting for the Dart timeout. The unsupported-write rejection keeps the per-case `withResponse`/`withoutResponse` message Android emits (#378).
* iOS: when several FlutterEngines run in one process, only one engine creates its `CBCentralManager` with the central state restoration identifier — the first engine that registers when Bluetooth permission is already granted, or on a fresh install the first engine to use Bluetooth after the grant — rather than whichever engine uses Bluetooth first. Later engines get a manager without one instead of one CoreBluetooth reports as unsupported, and only the owning engine creates its manager at launch. Ownership ends when the owning engine is deallocated, but an engine that has already created its manager never regains restoration, so only an engine that registers later can pick the identifier up. A denied claim is logged at info level when the losing engine creates its manager without restoration; logging defaults to `none`, so info logging must be enabled to see it (#386).

## 3.3.0
* Windows: allow app shutdown to continue when background connection disposal stalls in WinRT (#375).
* Apple: complete service discovery when a peripheral's GATT database holds multiple services with the same UUID (#369).
* iOS: allow turning off central state restoration via `UniversalBleCentralStateRestoration` (Boolean `NO` in `Info.plist`) while keeping the `bluetooth-central` background execution mode. When disabled, `CBCentralManager` is created without a restoration identifier and deferred lazily until first use (#370).

## 3.2.0
* Android Peripheral: Add `UniversalBlePeripheral.setAutoConnect(bool)` (defaulting to `true`) to configure whether `BluetoothGattServer.connect(device, autoConnect)` enables background auto-reconnection when a central connects (#368).
* Android: prevent duplicate read replies when a disconnect races a rejected or throwing native read (#364).
* Android: a read, RSSI, service-discovery or notification-subscription result that the stack reports from a binder thread is now delivered on the main thread, and the matching pending entry is found and removed under the list's lock. Those four lists were the last ones still bypassing the discipline the write, descriptor and MTU paths already follow, so a GATT callback racing an API call could corrupt the list — losing a completion, which left the Dart call awaiting forever — and completing inline sent the platform-channel reply from a binder thread. A callback now also completes only the operation it belongs to rather than every pending operation on that characteristic, so one response can no longer be reported for a request that is still in flight. A read also registers its pending result before `readCharacteristic()` is called, as writes already did, so a response that arrives before that call returns cannot be lost, and unregisters it again when the stack refuses the request (#364).
* Windows: `updateCharacteristicValue` returns after submitting notifications instead of blocking the platform thread until every subscribed client has been notified, so a slow or wedged link no longer freezes the UI. Failures while starting the operation are still returned; transport failures and truncated values are logged when error logging is enabled. Repeated failures for a characteristic are suppressed until a successful update, with recovery logged at info level. Failures observed while logging is disabled do not consume the first visible failure. Dart queues (including `QueueType.perDevice` and `QueueType.global`) and awaiting the returned future serialize submission only: Windows notification operations can overlap, and delivery order is not guaranteed (#363).
* Windows: a connect attempt that fails (the device drops the link during service or characteristic discovery, e.g. while it reboots) no longer freezes the app window. Its `BluetoothLEDevice` and GATT services were closed on Flutter's UI thread, where `Close` can deadlock as disconnect teardown did before #333; they are now closed on a background thread. The next connect to the same address waits for that close, at most 10 seconds, then fails with a connection error instead of waiting for the Dart-side timeout (#358).
* Fix Windows compilation and reject unsupported characteristic instance IDs explicitly.
* Fix Android service removal, value updates without subscribers, and per-client CCCD defaults.
* Preserve subscriptions and queued reports for other characteristic instances when one unsubscribes.
* Peripheral mode: characteristics can declare a stable `instanceId`. GATT allows several characteristics with the same UUID (HID exposes one Report characteristic per report), but the plugin addressed them by UUID and could only reach the first. Set `BlePeripheralCharacteristic.instanceId` to address each instance in `updateCharacteristicValue` and `getSubscribedClients`; read/write/descriptor callbacks and subscription events echo it back. UUID-only callers keep the first-match behaviour. `OnPeripheralReadRequestWithInstance` (and the write/descriptor variants, plus `setReadRequestHandlersWithInstance` etc.) receive the identity; the existing callbacks and setters are unchanged.
* Peripheral mode: each client's CCCD is tracked per characteristic instance and defaults to disabled, so one subscriber cannot change what another reads. CCCD and descriptor reads without an app handler now return the configured or per-client value instead of `GATT_FAILURE`.
* Peripheral mode: read request handlers return the complete value; the platform applies the client's read offset once. Previously Android sent handler data with the handler-supplied offset while Apple sliced it again, so handlers had to slice for one platform and not the other.
* Peripheral mode (Android, Apple): characteristic notifications are queued through native backpressure. Android drains FIFO from `onNotificationSent`; Apple retries from `peripheralManagerIsReady(toUpdateSubscribers)`. A release report can no longer be dropped or overtake its press when the transmit queue is full.
* Android: a peripheral characteristic whose read handler declines now serves its configured `value` instead of failing.
* Apple peripheral: retain service registration order after adapter recovery and when rebinding restored services.
* Apple peripheral: reject multi-request write batches once, before invoking Dart handlers, to avoid partially applying an atomic batch. Single-request writes keep their existing result handling; stale session completions are rejected.
* Apple peripheral: create dynamic characteristics with nil native values, support optional encrypted notification subscriptions, preserve notification FIFO ordering under backpressure, and discard unsent reports on session/service/adapter loss.
* Add opt-in peripheral state restoration with stable characteristic-instance identities and buffered events until Dart configuration.
* Add `clearPendingNotifications` for discarding unsent native updates. Android retains already submitted packets until their completion callback; Windows has no plugin-owned pending queue.
* Remove failed Apple service additions from pending state and cancel Dart service-add listeners on errors/timeouts.

## 3.1.2
* Windows: Service Data advertised under a 128-bit UUID is reported under that UUID, and `ScanFilter.withServiceData` matches it. The 16 UUID bytes are little-endian on air but were read in the order they arrive, so `BleDevice.serviceData` used a byte-reversed key and a filter with the real UUID found nothing (#356).

## 3.1.1
* Apple, Linux: `discoverServices` honours its `timeout`. Both gave up after a fixed 10 seconds, so a longer `timeout` could not help a peripheral that is slow to answer. On Apple, `timeout` (or, without one, the global `UniversalBle.timeout`) is now passed on as the native limit, which `AppleDiscoverServicesOptions(timeoutMillis:)` in `DiscoverServicesPlatformConfig.apple` also sets directly, and then bounds the whole call when no `timeout` is given; without either, it stays 10 seconds. On Linux the discovery no longer has a limit of its own and is bounded by `timeout` alone, as on Android, Windows and Web, so one that runs out of time now fails with a `TimeoutException` rather than `Failed to resolve services` (#349).
* Apple: a read, write or subscription the peripheral refuses now reports its ATT error as the matching `UniversalBleErrorCode` (`insufficientEncryption`, `insufficientAuthentication`, `readNotPermitted`, ...), as Android does, instead of `unknownError`. The error code is still in `details`. Codes in `CBErrorDomain` are unchanged: its numbers overlap ATT's with other meanings (#348).
* Windows: a read, write or subscription the peripheral refuses now reports its ATT error as the matching `UniversalBleErrorCode` (`insufficientEncryption`, `insufficientAuthentication`, `readNotPermitted`, ...) instead of the generic `failed`, as Android already does. Characteristic/descriptor reads and writes and `SetNotifiable` are covered; service/characteristic discovery at connect time is unchanged. Application-defined codes `0x80`-`0xFF` now report `unknownError`. The raw ATT error code is still in `details`.
* Linux: take the ATT error code from the BlueZ failure message only when it follows `ATT error:`, so an unrelated hex value in the message is no longer mistaken for the code.
* Bump `bluez` to `^0.9.0`.
* Bump the `pigeon` dev dependency to `^29.0.0`.
* Regenerate the Pigeon bindings with Pigeon 29. The async platform channels now use `@asyncCallback`, so the existing callback-based native implementations (Swift completion handlers, Kotlin callbacks) are kept as-is rather than migrated to native `async`/`suspend`. No public API change.
* Windows: compile the plugin with `/utf-8`. The Pigeon-generated sources contain UTF-8 doc comments, and MSVC decoded them using the system ANSI code page, so a clean build failed with C4819/C2220 on machines configured with a code page such as 936, 932, 949 or 950 (#354).

## 3.1.0
* `BleDevice.services` is now normalised to full 128-bit lower-case UUIDs on every platform, matching the keys of `BleDevice.serviceData`. Apple was the outlier: it reported 16-bit advertised service UUIDs in their short form (`180D`), so the same field had a different shape per platform and stored keys or comparisons did not transfer between them. Compare against, or store, the 128-bit form; short (`180D`) and `0x`-prefixed forms are still accepted as *input*. Entries that are not valid UUIDs are kept verbatim rather than dropped.
* Add `ScanFilter.withServiceData` to discover devices that carry a service UUID inside their advertising Service Data (the `0x16`/`0x20`/`0x21` advertising data types) — beacons such as Eddystone (`0xFEAA`) or the ATC_MiThermometer (`0x181A`) — which `withServices` cannot match, because it only looks at the advertised service UUID list (#57). The matching payloads are reported in `BleDevice.serviceData`. On Android and Apple this switches the scan to the software filter path (the platform cannot filter on Service Data), so more advertisements reach the app process; on Web it throws `notSupported`.
* Apple: compare service UUIDs in their 128-bit form when the custom filter path is active (`withNamePrefix`/`withManufacturerData`), instead of relying on `CBUUID` equality, which does not match a 16-bit advertised service UUID against the full 128-bit form the API sends. `ScanFilter.withServices` can now filter 16-bit services on that path.
* Linux: re-evaluate the scan filter against the device's current properties instead of the snapshot taken when BlueZ added it, and keep listening to a device that did not match at that point. A peripheral that only advertises its Service Data (or UUIDs) in a later advertisement was previously dropped permanently by any filter.
* Add `BleDevice.serviceData` documentation to the README (the API existed but was undocumented).

## 3.0.2
* Fix the broken "Try it online" demo URL in the README.

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
