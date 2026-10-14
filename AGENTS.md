# Universal BLE Agent Guidelines

This repository provides a unified cross-platform Flutter BLE plugin (`universal_ble`) supporting Android, iOS, macOS, Windows, Linux, and Web.

## Device ID Format & Handling (Critical)

Universal BLE unifies device identifiers across all supported platforms. Agents working on this codebase must adhere strictly to these rules:

### 1. Representation & The Two Forms
All case conversion and ID classification live centrally in `lib/src/utils/device_id.dart` (`DeviceId`). Do not implement ad-hoc casing logic elsewhere.

- **Addresses (Native platforms):** On Android, iOS, macOS, Windows, and Linux, device IDs are case-insensitive hardware addresses (MAC address on Android/Windows/Linux, peripheral UUID on Apple).
  - **`DeviceId.canonical` (Lower-case):** Emitted to users, used for cache keys (`CacheHandler`), deduplication (`ScanDeduplicator`), stream filtering, and queue mapping (`BleCommandQueue`).
  - **`DeviceId.native` (Upper-case):** Used when sending IDs across native platform channels.
    - Android's `BluetoothAdapter.getRemoteDevice(mac)` **throws an `IllegalArgumentException`** if the MAC address contains lowercase letters.
    - Linux BlueZ and Apple peripheral caches also expect uppercase addresses.
- **Opaque Tokens (Web Bluetooth):** Web Bluetooth generates opaque, random string tokens (e.g., Base64 strings). These are **not** Bluetooth addresses and are **case-sensitive**.
  - On Web (`hasAddressDeviceIds == false` / `isAddress: false`), `DeviceId.opaque` preserves the token verbatim without any case transformation (`canonical == native == original`).

### 2. Public API Invariants
- **Emissions:**
  - `UniversalBle`: Scan results (`scanStream`, `onScanResult`), connection state streams and listeners (`connectionStream`, `connectionChangeStream`, `onConnectionChange`), value streams (`characteristicValueStream`, `onValueChange`), pairing state streams (`pairingStateStream`, `onPairingStateChange`), and connection parameter callbacks **always emit `deviceId` in lower-case canonical form** on native platforms (and verbatim on Web).
  - `UniversalBlePeripheral`: Central client device IDs emitted in connection state updates, subscription updates, MTU changes, read/write request callbacks (`OnPeripheralReadRequest`, `OnPeripheralWriteRequest`), and `getSubscribedClients()` **always emit `deviceId` in lower-case canonical form**.
- **Inputs:**
  - All public client and peripheral methods taking `String deviceId` (`connect`, `disconnect`, `discoverServices`, `readValue`, `writeValue`, `subscribeNotifications`, `pair`, `updateCharacteristicValue`, `getMaximumNotifyLength`, `clearQueue`, etc.) **must accept any casing** from callers.
  - Public API boundaries must canonicalise caller-supplied IDs using `DeviceId.of(deviceId, isAddress: ...)`. Never assume the caller provided a lower-case ID.

### 3. Queues, Caches, and Deduplication
- **`BleCommandQueue`:**
  - Resolved with `isAddressSupplier: () => _platform.hasAddressDeviceIds` to dynamically distinguish Bluetooth addresses from Web tokens.
  - When clearing queues (`clearQueue(id)`), if `_isAddress` is true and `id` is a device address, clear both canonical and native variations of the key. Custom queue IDs are preserved as-is.
  - When `queueId` is a device address or matches `deviceId`, canonicalise it to preserve per-device command serialization across differing casing.
- **`ScanDeduplicator`:**
  - Uses `isAddress` (`true` by default on native platforms, `false` on Web).
  - When `isAddress` is true, deduplicates across different casing of the same device address.
- **`CacheHandler`:**
  - Expects callers to pass canonical device IDs (`UniversalBle.canonicalDeviceId(deviceId)`) when storing or looking up services, MTU, and subscriptions.

### 4. Testing Requirements
When modifying any device ID handling or API methods taking or returning device IDs:
- Add or update tests in `test/device_id_test.dart` and `test/device_id_case_insensitivity_test.dart`.
- Verify cross-case equivalence (calling with uppercase, lowercase, or mixed-case matches the same device).
- Verify that Apple UUID addresses and MAC addresses are tested.
- Verify that Web opaque tokens remain distinct and case-sensitive.
- Run `flutter test` and `flutter analyze` to ensure zero regressions.

---

## Architecture & Code Conventions

1. **Platform Interface Pattern:**
   - Platform interface lives in `lib/src/interfaces/universal_ble_platform_interface.dart`.
   - Native implementations are wired via Pigeon (`pigeon/universal_ble_pigeon.dart`).
   - Run `./build_pigeon.sh` after modifying Pigeon interface definitions.
2. **Logging:**
   - Use `UniversalLogger` instead of `print` or `debugPrint`.
3. **Queue Strategy (`QueueType.auto`):**
   - Android, Web, and Linux use `QueueType.perDevice` by default due to platform GATT concurrency constraints.
   - iOS, macOS, and Windows run commands concurrently (`QueueType.none`).
4. **Documentation:**
   - Maintain API doc comments (`///`) on public classes, properties, and methods in `lib/src/`.
   - Keep `README.md` and `CHANGELOG.md` updated with breaking changes and new features.
