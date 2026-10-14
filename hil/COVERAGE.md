# Hardware-in-the-loop coverage

The Windows HIL suite implements 85 tests against a physical nRF52 peripheral:
25 baseline tests and 60 fault injection tests (FIT). Skipped scenarios are not
included in these counts. Firmware contract revision 2 (v2) is required.

The calls start at the public Dart API and go through the operation queue,
Pigeon channel, Windows C++ plugin, WinRT, Windows Bluetooth stack, radio link,
and finally the Zephyr GATT server on the fixture.

## 1. Baseline coverage

### 1.1. Scan and discovery (4 tests)

- Verifies a fresh filtered scan through both the stream and callback APIs,
  scanner state, name, service UUID, RSSI, all eleven characteristics, their
  properties, and descriptor discovery enabled and disabled.
- This catches problems in advertisement parsing, UUID conversion, WinRT
  discovery, and Dart model mapping.

### 1.2. Reads and writes (5 tests)

- Verifies exact reads up to 200 bytes, 200-byte writes with response, and
  120-byte writes without response using firmware mirrors and counters. It
  also verifies an exact binary round trip through a writable descriptor and
  every operation exposed by the read/write/notify characteristic.
- This catches payload corruption, bad length handling, confusion between the
  two write paths, and incorrect native completion results.

### 1.3. Notifications and indications (6 tests)

- Verifies exact binary delivery, CCC state, unsubscribe/resubscribe, and 40
  ordered 64-byte notifications. Values must reach both the stream and callback
  APIs, and indications must recover after being disabled.
- This catches broken event registration, CCC state, byte conversion, packet
  ordering, loss, and duplication.

### 1.4. Connection lifecycle (4 tests)

- Verifies remote disconnect delivery, reconnect with a successful read, and
  ten host disconnect/reconnect cycles. A host disconnect must also reach the
  stream and callback APIs and agree with the queried connection state.
- This catches incomplete cleanup, bad replacement ownership, missing events,
  and GATT state that no longer works after reconnecting.

### 1.5. Concurrency, refresh, and platform results (6 tests)

- Verifies recovery from overlapping subscriptions, a valid MTU result, and
  `notImplemented` for Windows RSSI without disconnecting. It also verifies
  that system-device enumeration, client capability queries, connection
  priority handling, and ordinary service changes leave the active connection
  readable and writable.
- This catches subscription races, invalid MTU completion, incorrect error
  mapping, and operations that damage an otherwise usable connection.

## 2. Fault injection coverage

### 2.1. Connection lifecycle

| Test           | What it does                                                              | What it catches                                       |
| -------------- | ------------------------------------------------------------------------- | ----------------------------------------------------- |
| `FIT-CONN-002` | Immediate peripheral disconnect produces exactly one disconnect event     | Duplicate disconnect callbacks                        |
| `FIT-CONN-003` | Immediate disconnect is followed by reconnect and a successful read       | Incomplete cleanup of the old connection              |
| `FIT-CONN-006` | Two simultaneous connects resolve to one usable replacement connection    | Superseded native attempts disturbing the active link |
| `FIT-CONN-007` | Sweep host disconnect before/around/after a measured peripheral deadline; verify timer telemetry and reconnect | Blocking WinRT teardown, double cleanup, and stale timers |
| `FIT-CONN-009` | Reconnects before the old native disconnect callback has necessarily run  | Stale map entries suppressing the replacement attempt  |
| `FIT-CONN-010` | Five immediate peripheral disconnect/reconnect cycles all remain readable | State or resources leaking between connections        |
| `FIT-CONN-013` | Five rapid cycles emit alternating disconnected/connected events in order | Missing, duplicate, stale, and out-of-order callbacks |

For immediate disconnects, observation starts before the control write. A lost
write acknowledgement is accepted only when the disconnect occurs; otherwise
the original write error is rethrown.

### 2.2. Reads

| Test           | What it does                                                                  | What it catches                                             |
| -------------- | ----------------------------------------------------------------------------- | ----------------------------------------------------------- |
| `FIT-READ-001` | ATT error `0x0e`; read fails, connection survives, next read succeeds         | WinRT error handling without native abort or poisoned state |
| `FIT-READ-005` | Zero-length value returns an empty byte array                                 | Empty-buffer conversion                                     |
| `FIT-READ-006` | Exact reads of 1, 20, 22, 23, 64, 128, and 244 bytes                          | Boundary and large-value handling                           |
| `FIT-READ-007` | 11-second callback delay exceeds the 10-second timeout; later read succeeds   | Timeout completion, late callbacks, and queue release       |
| `FIT-READ-008` | Disconnect 50 ms into a delayed read; read fails and succeeds after reconnect | Native state being freed while a read still uses it         |
| `FIT-READ-010` | A delayed read finishes after reconnect without disturbing the new link       | Completion leaking across connection generations            |
| `FIT-READ-011` | Three characteristics are read concurrently with queueing disabled            | Independent concurrent completion routing                   |

### 2.3. Writes with response

| Test            | What it does                                                                                    | What it catches                                                |
| --------------- | ----------------------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| `FIT-WRITE-001` | ATT error `0x0e`; write fails, connection survives, next mirrored write succeeds                | Error propagation without corrupting connection or write state |
| `FIT-WRITE-006` | 11-second callback delay times out; later mirrored write succeeds                               | Timeout completion, late callbacks, and queue release          |
| `FIT-WRITE-007` | Disconnect precedes acknowledgement of a delayed write; write fails and recovery write succeeds | Native state being freed while a write still uses it           |
| `FIT-WRITE-010` | A delayed write finishes after reconnect; the replacement remains writable                      | Stale completion and incomplete replacement discovery          |

### 2.4. Service database changes

| Test           | What it does                                                      | What it catches                                         |
| -------------- | ----------------------------------------------------------------- | ------------------------------------------------------- |
| `FIT-DISC-007` | Dynamically adds and removes a service using Service Changed      | Stale WinRT service caches and non-atomic refresh       |
| `FIT-DISC-008` | Keeps notifications active while services are added and removed   | Subscription loss while replacing the cached GATT map   |
| `FIT-DISC-009` | Changes the service database while a delayed read is pending      | Closing a service object still owned by an active read  |
| `FIT-DISC-010` | Changes the service database while a delayed write is pending     | Closing a service object still owned by an active write |
| `FIT-DISC-011` | Changes the service database while a delayed CCC write is pending | Stale refresh installation and lost subscriptions       |

### 2.5. Descriptors

| Test           | What it does                                                         | What it catches                                       |
| -------------- | -------------------------------------------------------------------- | ----------------------------------------------------- |
| `FIT-DESC-001` | Injected ATT descriptor-read error, followed by a successful read    | Error propagation and poisoned descriptor-read state  |
| `FIT-DESC-002` | Injected ATT descriptor-write error, followed by a verified write    | Error propagation and poisoned descriptor-write state |
| `FIT-DESC-003` | Disconnect during a delayed descriptor read, then reconnect and read | Cleanup while descriptor discovery or read is active  |
| `FIT-DESC-004` | Disconnect during a delayed descriptor write, then recover and write | Cleanup while descriptor discovery or write is active |

### 2.6. Subscriptions

| Test          | What it does                                                                        | What it catches                                  |
| ------------- | ----------------------------------------------------------------------------------- | ------------------------------------------------ |
| `FIT-SUB-005` | Notification is emitted while the CCC enable write is completing                    | Handler registration after CCC enable            |
| `FIT-SUB-013` | Subscription is cleared by disconnect; resubscription after reconnect delivers once | Old event-token and cached CCC cleanup           |
| `FIT-SUB-014` | Five subscribe/unsubscribe cycles followed by one notification produce one callback | Leaked handler and duplicate delivery prevention |
| `FIT-SUB-015` | Ten rapid subscribe/unsubscribe cycles still allow exact delivery                   | CCC serialization and handler churn recovery     |

### 2.7. Notifications

| Test             | What it does                                                                     | What it catches                                             |
| ---------------- | -------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| `FIT-NOTIFY-001` | Notification emitted immediately after CCC enable is received exactly            | First-value loss at the enable boundary                     |
| `FIT-NOTIFY-002` | Emission after CCC disable fails and no value reaches the stream                 | Disable completion and handler removal                      |
| `FIT-NOTIFY-003` | Fixture emits `0, 1, 3, 4`; host receives exactly that gap                       | Transparent delivery without synthesized data               |
| `FIT-NOTIFY-004` | Fixture emits `0, 1, 1, 2`; host receives both duplicate-numbered packets        | No application-level deduplication                          |
| `FIT-NOTIFY-005` | Fixture emits `0, 2, 1, 3`; host preserves that order                            | No host-side payload reordering                             |
| `FIT-NOTIFY-006` | Alternating 1-byte and 244-byte values arrive intact and in order                | Buffer resizing, ownership, and binary integrity            |
| `FIT-NOTIFY-008` | Disconnect interrupts a 100-packet burst; partial delivery and reconnect succeed | Callback teardown during active delivery                    |
| `FIT-NOTIFY-010` | Reconnect and resubscribe produce a clean `0, 1, 2, 3, 4` sequence               | Stale callback/value rejection and new handler installation |
| `FIT-NOTIFY-012` | Host disconnects during a 500-packet burst and reconnects successfully           | Crashes, hangs, or use-after-free with queued callbacks     |

### 2.8. Indications, MTU/resource pressure, and timing sweeps

These tests use the public BLE API and real fixture callbacks. Firmware telemetry
proves faults were triggered; successful API calls alone do not count as proof.

| Cases | Fixture behavior and assertions |
| ----- | ------------------------------- |
| IND-001 | Send inside indication CCC enable; exact payload and successful confirmation |
| IND-002/003 | Disconnect or software reboot before the RX handler can process indication confirmation; bounded disconnect, triggered counter or retained boot count, recovery read |
| IND-004 | Attempt a second indication in the same RX callback; busy counter, uncorrupted first payload and successful subsequent send |
| IND-005 | Exact indications before disconnect and after reconnect/resubscribe |
| IND-006 | Interleaved notifications and indications, independent payload lists and completion ownership |
| MTU-003 | Read/write values at MTU-minus-header boundaries with exact mirrors |
| MTU-004 | Long reads through 512 bytes; prepared writes through 384 bytes, exact mirrors |
| MTU-005 | Reject 385-byte write on the fixture (counter required), preserve previous mirror and recover |
| MTU-006 | 128 nonblocking notification attempts; require actual ENOMEM, completion and receipt of all accepted frames, then successful notification/read/write |
| MTU-008 | Alternate payload sizes immediately below, at and above the negotiated boundary |
| RACE-001 | Persist an armed plan through host disconnect; trigger inside the next firmware connection callback; assert trigger and physical-disconnect counts, then recovery |
| RACE-002 | One-shot fault in the service-declaration reader during uncached discovery inside connect; assert trigger and physical-disconnect counts, then recovery |
| RACE-003/004 | Block a read/write callback for 300 ms; disconnect at 0, 25, 100 and 350 ms relative to its entry; bounded result and recovery |
| RACE-005/006 | Same sweep inside notification CCC enable/disable; assert the callback-trigger counter and recovery |
| RACE-007 | Repeat read/write ATT errors and interrupted operations with successful read and mirrored write after each fault |
| RACE-008 | Seeded sequence of read/write/CCC timing plans, with a trace for replay |

For the 350 ms sweep point, the fixture callback has returned, but the response
can still lose the transport race to Windows. Either success or a BLE error is
allowed; disconnection and clean recovery are required. Earlier points must
fail because the fixture callback is still blocked.

## 3. Explicit limitations and skips

- MTU-001/002: Windows MTU queries read local metadata. There is no server-side
  MTU-query callback for the fixture to interrupt deterministically.
- MTU-007: universal_ble does not expose raw Prepare Writes retained without an
  Execute Write. An ordinary long write does not prove prepare-queue exhaustion.
- SMP-001..008: this fixture has no SMP/encrypted-attribute profile, persistent
  bonds or passkey control. UniversalBle exposes pair/unpair, but its Windows
  backend cannot drive consent and passkey prompts unattended. These remain
  explicitly skipped, not implemented tests.

Reset clears counters and armed plans but preserves active subscriptions. It
does not release indication parameters still owned by Zephyr. Software reboot
starts a new boot count in retained no-init RAM; power loss/reflashing is outside
that retention guarantee.

CONN-007 sweeps host teardown offsets of 0, 100, 250 and 500 ms after arming a
250 ms peripheral timer. Firmware timers retain the original connection and
are cancelled when that link closes. Timer counters prove execution or
cancellation, and event ordering proves both host-first and peripheral-first
teardown across the sweep. WinRT may retain the physical link after the app's
disconnect returns, so host-first teardown does not require timer cancellation.
Each step requires exactly one physical disconnect, followed by a usable
replacement link beyond the old deadline.

This sweep reproduced a Windows UI-thread freeze inside synchronous
`GattDeviceService.Close()`. Connection disposal now marks the old agent
inactive immediately and closes its WinRT objects on a background MTA thread.
Shutdown drains the tracked cleanup operations before releasing plugin state.
That MTA cleanup drain does not pump application messages during teardown.

The full FIT catalog also contains 58 pending scenarios. Together with the 11
explicit limitations above, these account for 69 skips; none are counted among
the 60 implemented FIT cases.
