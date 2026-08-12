# Hardware-in-the-loop tests

This is a standalone Flutter application for testing `universal_ble` against
a physical nRF52 DK. It lives outside the normal package tests because it
needs the DK and exclusive access to a Bluetooth adapter.

The firmware is in the [`universal_ble_hil_firmware`](https://github.com/usmanmehmood55/universal_ble_hil_firmware)
repository. Test commands go over BLE. USB serial is only used for Zephyr logs.

## 1. Current coverage

The Windows suite contains 57 implemented hardware tests:

- 18 baseline tests for ordinary BLE behavior;
- 39 fault injection tests for hostile peripheral behavior, timing, and
  lifecycle races.

[`COVERAGE.md`](COVERAGE.md) lists every implemented test, what it does, and
the bugs it is meant to catch.

[`lib/main.dart`](lib/main.dart) also provides an interactive Web Bluetooth
runner for the portable baseline path.

## 2. How fault injection tests work

The test first writes a fault plan to the fixture's control characteristic.
The firmware keeps that plan and applies it when the next matching GATT
operation arrives.

For example, a disconnect-during-read test performs these steps:

1. Write a one-shot read plan containing a callback delay and disconnect delay.
2. Start a normal read through `universal_ble`.
3. Let the firmware disconnect while its read callback is pending.
4. Assert bounded failure, reconnect, and a successful recovery read.

The timing happens on the nRF52, where it is predictable. A reset clears fault
plans, scheduled disconnects, bursts, values, and counters. It leaves the
active connection and CCC state alone.

## 3. Execution boundary

The automated suite currently runs on Windows. Calls start at the public Dart
API and go through Pigeon, the Windows C++ plugin, WinRT, the Bluetooth stack,
the radio link, and finally the Zephyr GATT server.

Fixture control also uses BLE, so faults are armed while the device is
connected. The firmware then runs them locally using valid GATT behavior.

## 4. Running the tests

The platform runners are generated locally and are not stored in Git. Create
them after cloning or when testing a new platform:

```powershell
flutter create --platforms=android,web,windows .
```

For Android, add these permissions directly below the opening `<manifest>`
element in `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" android:maxSdkVersion="30" />
```

Flash the matching firmware and confirm that `UniversalBLE-HIL` is
advertising. From this directory, run:

```powershell
flutter pub get
flutter test integration_test/baseline_hil_test.dart -d windows
flutter test integration_test/fault_injection_hil_test.dart -d windows
```

If you already know the Windows device ID, you can skip the initial scan:

```powershell
flutter test integration_test/baseline_hil_test.dart -d windows `
  --dart-define=HIL_DEVICE_ID=AA:BB:CC:DD:EE:FF
```

For a longer reconnect test:

```powershell
flutter test integration_test/baseline_hil_test.dart -d windows `
  --dart-define=HIL_RECONNECT_CYCLES=100
```

Run the Web baseline with:

```powershell
flutter run -d chrome
```

Web Bluetooth requires a secure context, a real user gesture, and browser
device permission. Click **Select device and run**, then select
`UniversalBLE-HIL` in Chrome's chooser.

## 5. Isolation and diagnosis

Each Windows test connects, resets the fixture, runs one case, and disconnects.
The fixture only accepts one connection, so run the tests serially.

A completed Dart call does not prove that the peripheral saw the same thing.
Writes are therefore checked through read-only mirrors, subscriptions through
fixture state, and notification bursts through sequence numbers.

When a test fails, collect both outputs:

- Flutter integration-test output and `universal_ble` debug logs;
- Zephyr serial logs from the nRF52 DK.

If setup cannot find the fixture, confirm that it is advertising and that no
other host holds its single connection slot.

## 6. Execution policy

These tests do not run in normal pull-request CI. Run them manually when a
change touches native BLE lifecycle, GATT operations, subscriptions, queueing,
or the platform channel. A native crash can kill the test runner. Use
`--plain-name` to rerun the failing case on its own.
