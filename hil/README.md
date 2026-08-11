# Hardware-in-the-loop tests

This directory is a self-contained Flutter application for opt-in
`universal_ble` tests against a physical nRF52 fixture. It is separate from
the package unit tests and example application because it requires dedicated
hardware, flashed firmware, and exclusive access to a Bluetooth adapter.

The companion firmware is the `sample_ble_device` repository. Flash it and
confirm that `UniversalBLE-HIL` is advertising before starting a test run.

## 1. Test suites

### 1.1. Baseline suite

[`integration_test/baseline_hil_test.dart`](integration_test/baseline_hil_test.dart)
contains the implemented regression baseline:

- scan filtering and discovery;
- service and characteristic discovery;
- reads and writes with and without response;
- notification and indication delivery;
- unsubscribe and resubscribe;
- ordered notification bursts;
- host- and peripheral-initiated disconnects;
- repeated reconnects;
- overlapping notification operations;
- negotiated MTU behavior.

### 1.2. Fault-injection tracker

[`integration_test/fault_injection_hil_test.dart`](integration_test/fault_injection_hil_test.dart)
contains the planned fault cases. Every pending case:

- has a stable `FI-*` identifier;
- describes one observable client behavior;
- is skipped until the matching firmware scenario and assertions exist;
- fails deliberately if its skip is removed without an implementation.

The tracker is intentionally limited to behavior available through the stock
Zephyr Bluetooth Host and Nordic SoftDevice Controller APIs.

## 2. Supported fault mechanisms

The fixture can implement these faults without a custom controller:

- start, stop, and change valid advertising data;
- disconnect or reboot at scheduled application-level points;
- return standard ATT errors from read and write authorization callbacks;
- block synchronous GATT callbacks to exercise client timeouts;
- accept, reject, or partially process valid long operations;
- select a different valid GATT profile across reboot and reconnect;
- send a Service Changed indication;
- authorize or reject CCC descriptor access;
- omit, duplicate, reorder, resize, or interleave valid application
  notifications;
- disconnect while notifications or indications are outstanding;
- exhaust Zephyr notification buffers and prepare-write queues;
- exercise standard SMP pairing, bonding, cancellation, and bond removal;
- sweep deterministic delays and replay a recorded scenario configuration.

The suite does not cover malformed ATT or link-layer packets, corrupted radio
frames, invalid controller state transitions, interception, or RF jamming.
Those behaviors are not exposed by the vanilla fixture stack.

## 3. Run the Windows baseline

From this directory:

```powershell
flutter pub get
flutter test integration_test/baseline_hil_test.dart -d windows
```

The suite normally discovers the fixture by its advertised service. A known
Windows device ID can avoid initial scan setup:

```powershell
flutter test integration_test/baseline_hil_test.dart -d windows `
  --dart-define=HIL_DEVICE_ID=AA:BB:CC:DD:EE:FF
```

Increase reconnect repetitions for lifecycle validation:

```powershell
flutter test integration_test/baseline_hil_test.dart -d windows `
  --dart-define=HIL_RECONNECT_CYCLES=100
```

Use 10 cycles for normal development, at least 100 for a lifecycle change,
and 1,000 or more for a dedicated soak run.

## 4. Run the Web baseline

```powershell
flutter run -d chrome
```

Web Bluetooth requires a secure context, a real user gesture, and browser
device permission. Click **Select device and run**, then select
`UniversalBLE-HIL` in Chrome's chooser.

The browser runner executes the portable scan, discovery, read, write,
notification, indication, burst, and reconnect checks. Windows-only native
race, RSSI capability, and MTU cases are not run in the browser.

## 5. Isolation and failure diagnosis

The Windows baseline discovers the immutable device identity once per process.
Each behavioral test then connects, sends the firmware reset command, performs
one scenario, and disconnects in teardown.

Writes are verified through independent read-only mirror characteristics.
Subscription state and counters are verified through the state characteristic.
Successful Dart API completion alone is not treated as proof that the
peripheral observed an operation.

When a test fails, collect both outputs:

- Flutter integration-test output and universal_ble debug logs;
- Zephyr serial logs from the nRF52 DK.

If setup cannot find the fixture, verify that it is advertising and that no
other host holds its single connection slot.

## 6. Execution policy

HIL tests are not part of ordinary package analysis, unit tests, or pull
request CI. Run them manually when changing native BLE lifecycle, GATT,
subscription, queueing, or platform-channel behavior.

The fault-injection suite remains skipped until its out-of-band fixture-control
protocol and individual firmware scenarios are implemented.
