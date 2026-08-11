# Hardware-in-the-loop tests

This directory is a standalone Flutter application for opt-in
`universal_ble` tests against a physical nRF52 fixture. It is separate from
the package unit tests and example application because it requires dedicated
hardware and exclusive access to a Bluetooth adapter.

The companion firmware is the `sample_ble_device` repository. Communication
between the tests and fixture uses BLE only. The DK's USB serial connection is
used for logs, not test control.

## 1. Current coverage

### 1.1. Windows baseline

[`integration_test/baseline_hil_test.dart`](integration_test/baseline_hil_test.dart)
contains 15 implemented tests:

- filtered scanning and advertised identity;
- the complete service, characteristic, property, and descriptor contract;
- deterministic reads, configured reads, and exact payload comparison;
- writes with and without response, verified through independent mirrors and
  firmware counters;
- notification and indication payload delivery;
- unsubscribe followed by clean resubscription;
- ordered notification bursts with sequence and payload checks;
- peripheral-initiated disconnect reporting and reconnect recovery;
- repeated host disconnect and reconnect cycles;
- recovery after overlapping notification subscriptions;
- negotiated MTU reporting;
- the documented Windows result for unsupported connected RSSI reads.

### 1.2. Windows fault injection tests (FIT)

[`integration_test/fault_injection_hil_test.dart`](integration_test/fault_injection_hil_test.dart)
contains 120 scenarios with stable `FIT-*` identifiers. Of these, 23 have
firmware controls and assertions:

- Connection lifecycle (5): single disconnect delivery, immediate reconnect,
  a host/peripheral disconnect race, repeated peripheral disconnects, and
  ordered events during rapid cycles.
- Reads (6): ATT error propagation, empty and boundary-sized values, callback
  timeout, disconnect during a pending read, and independent concurrent reads.
- Writes with response (3): ATT error propagation, callback timeout, and
  disconnect before acknowledgement followed by recovery.
- Subscriptions (3): cleanup across reconnect, no duplicate callbacks after
  repeated resubscription, and rapid subscribe/unsubscribe cycles.
- Notifications (6): delivery immediately after enable, no delivery after
  disable, minimum and maximum payloads, disconnect during a burst, a clean
  post-reconnect sequence, and teardown with queued notifications.

The remaining 97 scenarios are deliberately skipped. Each skipped body fails
if its `skip` is removed, preventing an unimplemented scenario from appearing
green.

The `FIT-READ-001` ATT-error test reproduces a native abort on the Windows
implementation from `main`. This is a known regression result, not a harness
failure, and is the focused regression case for the Windows hardening work.

### 1.3. Web baseline

[`lib/main.dart`](lib/main.dart) provides an interactive Web Bluetooth runner.
It verifies nine portable behaviors:

- scan, selection, and connection;
- service discovery;
- deterministic and configured reads;
- writes with and without response, verified by the fixture;
- notification and indication delivery;
- ordered notification bursts;
- peripheral disconnect and reconnect.

The Windows FIT suite is not currently exposed by the Web runner.

## 2. How fault injection tests work

The fixture's control characteristic arms a deterministic scenario before the
operation under test. The firmware then applies that scenario locally when the
matching GATT operation arrives.

For example, a disconnect-during-read test performs these steps:

1. Write a one-shot read plan containing a callback delay and disconnect delay.
2. Start a normal read through `universal_ble`.
3. Let the firmware disconnect while its read callback is pending.
4. Assert bounded failure, reconnect, and a successful recovery read.

This avoids relying on host-side sleeps for critical timing. Reset clears
every armed fault, scheduled disconnect, burst, value, and counter while
leaving the active connection and CCC state intact.

## 3. Scope and limitations

The current implementation intentionally uses BLE as both the test path and the
fixture-control path. It covers faults that can be armed while connected and
then executed locally by the firmware.

It does not currently cover:

- stopping or changing advertising before a connection exists;
- rebooting or recovering a fixture after BLE control is unavailable;
- selecting a different GATT profile before connection;
- out-of-band bond deletion;
- true power loss or brownout behavior;
- malformed ATT or link-layer packets, corrupted radio frames, interception,
  or RF jamming.

The first four require an out-of-band fixture controller and remain out of
scope. The remaining protocol and radio faults are not exposed by the stock
Zephyr Bluetooth Host and Nordic SoftDevice Controller APIs.

## 4. Running the tests

Flash the matching firmware and confirm that `UniversalBLE-HIL` is
advertising. From this directory, run:

```powershell
flutter pub get
flutter test integration_test/baseline_hil_test.dart -d windows
flutter test integration_test/fault_injection_hil_test.dart -d windows
```

A known Windows device ID can avoid the initial scan:

```powershell
flutter test integration_test/baseline_hil_test.dart -d windows `
  --dart-define=HIL_DEVICE_ID=AA:BB:CC:DD:EE:FF
```

Increase reconnect repetitions for a lifecycle soak run:

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

Each Windows test connects, sends the firmware reset command, runs one
scenario, and disconnects. Tests must run serially against one fixture.

Successful Dart completion is not treated as proof that the fixture observed
an operation. Writes are checked through read-only mirrors, subscriptions
through fixture state, and bursts through sequence numbers.

When a test fails, collect both outputs:

- Flutter integration-test output and `universal_ble` debug logs;
- Zephyr serial logs from the nRF52 DK.

If setup cannot find the fixture, confirm that it is advertising and that no
other host holds its single connection slot.

## 6. Execution policy

HIL tests are not part of ordinary analysis, unit tests, or pull-request CI.
Run them manually for native BLE lifecycle, GATT, subscription, queueing, or
platform-channel changes. A physical test failure may terminate the native
runner; rerun a focused case with `--plain-name` when isolating a crash.
