# Hardware-in-the-loop tests

This is a standalone Flutter application for testing `universal_ble` against
a physical nRF52 DK. It lives outside the normal package tests because it
needs the DK and exclusive access to a Bluetooth adapter.

The firmware is in the [`universal_ble_hil_firmware`](https://github.com/usmanmehmood55/universal_ble_hil_firmware)
repository. On Windows, fixture commands go over the DK's USB virtual COM
port. The BLE operations under test still go over the radio. Android and the
interactive Web runner retain the BLE control path.

## 1. Current coverage

The Windows suite contains 86 implemented hardware tests:

- 26 baseline tests for ordinary BLE behavior;
- 60 fault injection tests for hostile peripheral behavior, timing, and
  lifecycle races.

The fixture requires contract revision 2 (v2, following the original v1). Of the 30 indication, MTU/resource,
pairing, and timing scenarios, 19 are implemented and 11 have explicit
unattended/API limitation reasons. Those skips are not counted as coverage.

[`COVERAGE.md`](COVERAGE.md) lists every implemented test, what it does, and
the bugs it is meant to catch.

The indication, MTU/resource, timing-sweep assertions, and explicit limitations
are documented in the corresponding sections of `COVERAGE.md`. Build and flash
the v2 firmware before running this harness; the v1 contract is incompatible.

[`lib/main.dart`](lib/main.dart) also provides an interactive Web Bluetooth
runner for the portable baseline path.

## 2. How fault injection tests work

The Windows test first sends a fault plan over USB serial and waits for the
fixture to acknowledge it.
The firmware keeps that plan and applies it when the next matching GATT
operation arrives.

For example, a disconnect-during-read test performs these steps:

1. Arm a one-shot read plan containing a callback delay and disconnect delay.
2. Start a normal read through `universal_ble`.
3. Let the firmware disconnect while its read callback is pending.
4. Assert bounded failure, reconnect, and a successful recovery read.

The timing happens on the nRF52, where it is predictable. A reset clears fault
plans, scheduled disconnects, bursts, values, and counters. It leaves the
active connection and CCC state alone.

### UART reply framing

The fixture logs on the same console UART that carries commands, so a reply can
share a line with log output. The host finds the `HIL <request-id>` marker from
the end of the line, validates the payload with an anchored pattern, and ignores
whatever follows it. A line without a reply only goes to the test log. The
bridge behind the port reads continuously, so buffered log output cannot
overflow and discard a pending reply, and a missed reply fails that one exchange
instead of the whole session.

This is a host-side mitigation, not a protocol guarantee. The durable fix is
firmware-side: prefix every reply with `\r\n` so it always starts a line, or
suppress logging around replies. Only the reset/reboot acknowledgement emits
that prefix today.

## 3. Execution boundary

The automated suite currently runs on Windows. Calls start at the public Dart
API and go through Pigeon, the Windows C++ plugin, WinRT, the Bluetooth stack,
the radio link, and finally the Zephyr GATT server.

The UART acknowledgement means the fixture accepted a command, not that a
disconnect or notification has already occurred. Tests still assert the BLE
outcome and use fixture telemetry where they need proof a fault fired.

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

Flash the UART-enabled revision 2 firmware (older revision 2 images do not
implement the serial handshake). Connect the DK over USB, find its COM port
in Device Manager, and close any serial monitor using that port. The harness
uses Windows PowerShell (`powershell.exe`) to open the port. From this
directory, run:

```powershell
flutter pub get
$env:HIL_SERIAL_PORT = 'COM4' # Replace with the DK's port.
flutter test integration_test/baseline_hil_test.dart -d windows
flutter test integration_test/fault_injection_hil_test.dart -d windows
```

The UART handshake supplies the fixture's BLE address. Optionally assert that
it matches the expected address:

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

### Maintainer-triggered Windows CI

In Actions, open Windows HIL and fault insertion tests and click Run workflow.
Choose `all` (the default) or one group: `baseline`,
`connection-discovery`, `gatt-operations`, `notifications-indications`,
`mtu-resources`, or `timing-sweeps`. Existing pairing and bonding cases are
included in `connection-discovery`.

The job requires the protected default branch and the default-branch copy of
the workflow file. That is an accident guard, not a security boundary; see
[Required organization settings](#required-organization-settings) for the two
organization controls the job actually depends on. The guard names the workflow
reference literally (`Navideck/universal_ble/...@refs/heads/main`), so update
that value if the workflow is renamed, forked, or moved to another default
branch.

The workflow regenerates the Windows app from scratch, warms the CMake/MSVC
build once outside the timed groups, flashes once, then runs the selected groups
serially on the same fixture. Each group has its own budget and log:

| Group                     | Budget |
| ------------------------- | ------ |
| baseline                  | 20 min |
| connection-discovery      | 30 min |
| gatt-operations           | 30 min |
| notifications-indications | 30 min |
| mtu-resources             | 25 min |
| timing-sweeps             | 45 min |

`timing-sweeps` needs the largest budget because its declared per-test timeouts
alone add up to 34 minutes: four 4-minute sweep bodies (one of which four
generated tests reuse) plus a 6-minute seed replay. Each group budget is above
the sum of that group's per-test bounds and is the single wall-clock authority;
the job timeout covers every selected group plus preparation, the warm build, and
the flash. A failed or timed-out group fails the job without preventing later
selected groups from running. Logs are kept separately for each run attempt. The
workflow does not run on pushes or pull requests and does not accept a separate
checkout ref.

To run a single group locally from this directory after preparing the fixture:

```powershell
pwsh -NoProfile -File ./run_windows_hil_group.ps1 -Group gatt-operations
```

If the machine restricts local scripts, pass the policy explicitly:
`pwsh -NoProfile -ExecutionPolicy Bypass -File ./run_windows_hil_group.ps1
-Group gatt-operations`. The CI workflow always passes `-ExecutionPolicy
Bypass`.

### Required organization settings

The hardware runner is only safe when these are configured. The workflow file
cannot enforce either of them, and its own branch guard is an accident guard
only: `workflow_dispatch` runs the workflow file of the selected ref, so a
branch can dispatch a copy that drops the guard.

- A dedicated Windows x64 self-hosted runner with the label `universal-ble-hil`,
  in the organization runner group `windows-hil`. The workflow already selects
  that group; restrict the group's workflow access to this repository and to
  `Navideck/universal_ble/.github/workflows/windows_hil.yml@refs/heads/main`
  (adjust owner, repository and ref for another deployment). Do not use a
  general-purpose runner and do not allow pull-request workflows to use it.
- A repository environment named `windows-hil`, restricted to the protected
  default branch, with maintainers as required reviewers. Users with write
  access can request a run; a maintainer must approve the hardware job.

### Runner prerequisites

- Flutter and PowerShell 7 on the runner account's PATH, Visual Studio with
  **Desktop development with C++**, and an interactive Windows session with a
  working Bluetooth adapter. Check `flutter doctor -v` and `flutter devices`
  from the same account that runs Actions.
- A dedicated nRF52 DK (nRF52832 on a PCA10040 board) connected over USB with no
  external SWD target attached. Install SEGGER J-Link Commander (7.92d or newer)
  at the default location, `%ProgramFiles%\SEGGER\JLink\JLink.exe`. The workflow
  uses this path to avoid picking up Java's `jlink.exe`. In the GitHub
  environment's **Variables**, set `HIL_JLINK_SERIAL` to the onboard probe's
  serial number. You can copy it from nRF Connect, including any leading zeros.
  The value is masked in the run log, kept verbatim for the `jlink -USB`
  selection, and compared against the PnP instance id with its leading zeros
  stripped, because that id drops them. Optionally set `HIL_DEVICE_ID` to assert
  the expected BLE address.

CI resolves the COM port from the J-Link serial by walking the Windows PnP
device tree. It keeps ports whose parent chain contains the DK's
`USB\VID_1366&PID_...\<serial>` instance, fails when it finds none, prints the
ports it did find, and otherwise prefers the interface whose instance id
contains `&MI_00` (the fixture's VCOM0). It fails instead of guessing when no
VCOM0 interface exists.

Before running the selected groups, CI downloads `zephyr.hex` from the firmware
release pinned by `HIL_FIRMWARE_TAG` in the workflow. It checks the file against
`HIL_FIRMWARE_SHA256` before erasing, programming, verifying, and resetting the
selected DK. This wipes existing target firmware and settings. When the Flutter
harness needs new firmware, publish it under a new release tag and update both
pins in the same change as the harness. The firmware must support the UART
telemetry command (`fe`) used by the timing sweeps. The flash log is included in
the test artifact when J-Link runs.

Those releases live in the personal `usmanmehmood55/universal_ble_hil_firmware`
repository. That is acceptable while this workflow is a draft; before it is
relied on, move the firmware (or a build-from-source step) under the Navideck
organization.

The run uploads the test output as a log artifact. Existing test skips still
apply; the Apple-only duplicate-UUID suite is not part of Windows CI.

## 5. Isolation and diagnosis

Each Windows test connects, resets the fixture, runs one case, and disconnects.
The fixture only accepts one connection, so run the tests serially.

A completed Dart call does not prove that the peripheral saw the same thing.
Writes are therefore checked through read-only mirrors, subscriptions through
fixture state, and notification bursts through sequence numbers.

When a test fails, collect both outputs:

- Flutter integration-test output and `universal_ble` debug logs;
- Fixture serial output, forwarded into the test log continuously and in whole
  lines, including lines that carry no command reply.

The host-side UART timeout is per exchange. A late reply, a missed reply, or a
burst of fixture logging does not end the session; the next command still works.

If setup cannot find the fixture, confirm that it is advertising and that no
other host holds its single connection slot.

## 6. Execution policy

These tests do not run in normal pull-request CI. Run them manually when a
change touches native BLE lifecycle, GATT operations, subscriptions, queueing,
or the platform channel. A native crash can kill the test runner. Use
`--plain-name` to rerun the failing case on its own.

Replay the seeded timing scenario with:

```powershell
flutter test integration_test/fault_injection_hil_test.dart -d windows `
  --plain-name "[FIT-RACE-008]" --dart-define=HIL_SCENARIO_SEED=316
```

The log records the seed, operation, callback delay and disconnect offset for
each step. Keep the same Dart SDK when replaying a sequence: `Random` does not
promise identical sequences across SDK versions.
