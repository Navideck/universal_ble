# AGENTS.md

Persistent instructions and architectural rules for AI coding agents working on `universal_ble`.

---

## 1. Core Rule: Mind Hot Reload & Hot Restart (Native Source of Truth)

**Never rely on in-memory Dart caches as the source of truth for BLE hardware or peripheral state.**

### Why This Matters:
- **Flutter Hot Restart** resets the Dart VM and wipes all in-memory Dart state (caches, singletons, static maps, stream controllers).
- The **native host process** (Android Activity/Service, iOS/macOS host, Windows Win32 host, Linux BlueZ daemon, Web browser page) **remains alive**.
- BLE connections, peripheral hardware states, negotiated MTUs, pairing bonds, and **active characteristic subscriptions (CCCD notifications/indications) remain active in hardware and the native OS**.
- If state (such as `isSubscribed`, `getConnectionState`, `isPaired`, etc.) is tracked only in Dart memory, a Hot Restart resets that state to default/false, causing silent desynchronization between the Dart layer and the peripheral.

### Implementation Guidelines:
1. **Native is the Source of Truth:**
   - Any API querying peripheral or connection state (e.g., `isSubscribed`, `getSubscribedCharacteristics`, `getConnectionState`, `isPaired`) must query the native platform layer or the underlying OS GATT stack.
   - On native platforms, query the actual OS/hardware state where possible (e.g. `CBCharacteristic.isNotifying` on Apple, CCCD `0x2902` descriptor bytes or process-level tracking on Android, `GattCharacteristic::ValueChanged` tokens on Windows, BlueZ `char.notifying` on Linux).
2. **Asynchronous Query APIs:**
   - Because retrieving native state requires crossing the platform channel (Pigeon), state inspection APIs must return `Future<T>` (e.g., `Future<bool> isSubscribed(...)`).
3. **Clean Disconnect Handling:**
   - Ensure native and platform layers clear or update tracking when a peripheral disconnects.
4. **Dart Caching:**
   - In-memory Dart caches are acceptable only as short-lived optimizations or fallback hints, but must never mask or substitute for the authoritative native state.

---

## 2. Project Architecture & Platform Coverage

`universal_ble` is a unified Flutter BLE plugin supporting six platforms:
- **Android**: Kotlin via Pigeon (`android/src/main/kotlin/...`)
- **iOS & macOS**: Swift via Pigeon (`darwin/universal_ble/Sources/...`)
- **Windows**: C++ WinRT via Pigeon (`windows/src/...`)
- **Linux**: BlueZ DBus via pure Dart (`lib/src/universal_ble_linux/...`)
- **Web**: Web Bluetooth API via pure Dart (`lib/src/universal_ble_web/...`)

### Pigeon & Codegen Workflow:
- Host–native APIs are defined in `pigeon/universal_ble.dart`.
- Whenever modifying Pigeon definitions, regenerate bindings by running:
  ```bash
  ./build_pigeon.sh
  # or: dart run pigeon --input pigeon/universal_ble.dart
  ```
- Keep all platform implementations (Kotlin, Swift, C++, Linux Dart, Web Dart) in sync whenever adding or modifying platform channel methods.

---

## 3. Platform Capabilities & Queue Management

- **Serialization & Queueing:**
  - BLE operations (especially on Android and Web) can be sensitive to concurrency. Command queuing is managed through `BleCommandQueue` in `UniversalBle`.
  - Maintain queue awareness when executing commands (pass `queueId` and `timeout` consistently).
- **Platform-Specific Options:**
  - Single-platform configurations should be exposed via scoped parameter objects (e.g. `PlatformConfig`, `ScanFilter`) rather than cluttering shared method signatures.

---

## 4. Verification & Testing

Before submitting or concluding any change, always run:

```bash
flutter test
dart analyze
dart format .
```

Ensure all tests pass with zero analyzer warnings or errors.
