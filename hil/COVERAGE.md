# Hardware-in-the-loop coverage

The Windows HIL suite runs 57 tests against a physical nRF52 peripheral:
18 baseline tests and 39 fault injection tests (FIT).

The calls start at the public Dart API and go through the operation queue,
Pigeon channel, Windows C++ plugin, WinRT, Windows Bluetooth stack, radio link,
and finally the Zephyr GATT server on the fixture.

## 1. Baseline coverage

### 1.1. Scan and discovery (2 tests)

- Verifies filtered discovery, name, service UUID, RSSI, all ten
  characteristics, and their properties.
- This catches problems in advertisement parsing, UUID conversion, WinRT
  discovery, and Dart model mapping.

### 1.2. Reads and writes (4 tests)

- Verifies exact reads up to 200 bytes, 200-byte writes with response, and
  120-byte writes without response using firmware mirrors and counters. It
  also verifies an exact binary round trip through a writable descriptor.
- This catches payload corruption, bad length handling, confusion between the
  two write paths, and incorrect native completion results.

### 1.3. Notifications and indications (4 tests)

- Verifies exact binary delivery, CCC state, unsubscribe/resubscribe, and 40
  ordered 64-byte notifications.
- This catches broken event registration, CCC state, byte conversion, packet
  ordering, loss, and duplication.

### 1.4. Connection lifecycle (3 tests)

- Verifies remote disconnect delivery, reconnect with a successful read, and
  ten host disconnect/reconnect cycles.
- This catches incomplete cleanup, bad replacement ownership, missing events,
  and GATT state that no longer works after reconnecting.

### 1.5. Concurrency, refresh, and platform results (5 tests)

- Verifies recovery from overlapping subscriptions, a valid MTU result, and
  `notImplemented` for Windows RSSI without disconnecting. It also verifies
  that system-device enumeration and ordinary service changes leave the
  active connection readable and writable.
- This catches subscription races, invalid MTU completion, incorrect error
  mapping, and operations that damage an otherwise usable connection.

## 2. Fault injection coverage

### 2.1. Connection lifecycle

| Test           | What it does                                                              | What it catches                                       |
| -------------- | ------------------------------------------------------------------------- | ----------------------------------------------------- |
| `FIT-CONN-002` | Immediate peripheral disconnect produces exactly one disconnect event     | Duplicate disconnect callbacks                        |
| `FIT-CONN-003` | Immediate disconnect is followed by reconnect and a successful read       | Incomplete cleanup of the old connection              |
| `FIT-CONN-006` | Two simultaneous connects resolve to one usable replacement connection     | Superseded native attempts disturbing the active link |
| `FIT-CONN-007` | Host and peripheral disconnect concurrently; reconnect remains usable     | Double cleanup when both sides disconnect             |
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
| `FIT-READ-010` | A delayed read finishes after reconnect without disturbing the new link      | Completion leaking across connection generations            |
| `FIT-READ-011` | Three characteristics are read concurrently with queueing disabled            | Independent concurrent completion routing                   |

### 2.3. Writes with response

| Test            | What it does                                                                                    | What it catches                                                |
| --------------- | ----------------------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| `FIT-WRITE-001` | ATT error `0x0e`; write fails, connection survives, next mirrored write succeeds                | Error propagation without corrupting connection or write state |
| `FIT-WRITE-006` | 11-second callback delay times out; later mirrored write succeeds                               | Timeout completion, late callbacks, and queue release          |
| `FIT-WRITE-007` | Disconnect precedes acknowledgement of a delayed write; write fails and recovery write succeeds | Native state being freed while a write still uses it           |
| `FIT-WRITE-010` | A delayed write finishes after reconnect; the replacement remains writable                  | Stale completion and incomplete replacement discovery          |

### 2.4. Service database changes

| Test           | What it does                                                     | What it catches                                  |
| -------------- | ---------------------------------------------------------------- | ------------------------------------------------ |
| `FIT-DISC-007` | Dynamically adds and removes a service using Service Changed        | Stale WinRT service caches and non-atomic refresh       |
| `FIT-DISC-008` | Keeps notifications active while services are added and removed     | Subscription loss while replacing the cached GATT map  |
| `FIT-DISC-009` | Changes the service database while a delayed read is pending        | Closing a service object still owned by an active read |
| `FIT-DISC-010` | Changes the service database while a delayed write is pending       | Closing a service object still owned by an active write |
| `FIT-DISC-011` | Changes the service database while a delayed CCC write is pending   | Stale refresh installation and lost subscriptions      |

### 2.5. Descriptors

| Test           | What it does                                                        | What it catches                                      |
| -------------- | ------------------------------------------------------------------- | ---------------------------------------------------- |
| `FIT-DESC-001` | Injected ATT descriptor-read error, followed by a successful read   | Error propagation and poisoned descriptor-read state |
| `FIT-DESC-002` | Injected ATT descriptor-write error, followed by a verified write   | Error propagation and poisoned descriptor-write state |
| `FIT-DESC-003` | Disconnect during a delayed descriptor read, then reconnect and read | Cleanup while descriptor discovery or read is active |
| `FIT-DESC-004` | Disconnect during a delayed descriptor write, then recover and write | Cleanup while descriptor discovery or write is active |

### 2.6. Subscriptions

| Test          | What it does                                                                        | What it catches                                  |
| ------------- | ----------------------------------------------------------------------------------- | ------------------------------------------------ |
| `FIT-SUB-005` | Notification is emitted while the CCC enable write is completing                   | Handler registration after CCC enable            |
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
