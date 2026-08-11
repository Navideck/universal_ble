import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:universal_ble_hil/src/hil_peripheral.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('UniversalBle fault injection tests (FIT)', () {
    late HilPeripheral peripheral;
    var setupSucceeded = false;

    setUp(() async {
      setupSucceeded = false;
      peripheral = await HilPeripheral.open();
      setupSucceeded = true;
    });

    tearDown(() async {
      UniversalBle.queueType = QueueType.global;
      if (setupSucceeded) {
        setupSucceeded = false;
        try {
          await peripheral.close();
        } catch (_) {
          // A fault scenario may deliberately leave the peripheral offline.
        }
      }
    });

    group('advertising and scanning', () {
      _pending(
        '[FIT-ADV-001] discovers a peripheral that starts advertising after the scan begins',
      );
      _pending(
        '[FIT-ADV-002] stops scanning cleanly when advertising disappears during a scan',
      );
      _pending(
        '[FIT-ADV-003] rediscovers the peripheral after advertising stops and restarts',
      );
      _pending(
        '[FIT-ADV-004] reports changed manufacturer data after an advertising restart',
      );
      _pending(
        '[FIT-ADV-005] reports a changed local name after an advertising restart',
      );
      _pending(
        '[FIT-ADV-006] filters out an advertising profile with a nonmatching service UUID',
      );
      _pending(
        '[FIT-ADV-007] accepts the fixture after it restores the matching service UUID',
      );
      _pending(
        '[FIT-ADV-008] tolerates repeated advertising start and stop cycles',
      );
    });

    group('connection establishment and teardown', () {
      _pending(
        '[FIT-CONN-001] fails within the deadline when advertising stops before connection',
      );
      testWidgets(
        '[FIT-CONN-002] reports one disconnect when the peripheral disconnects immediately after connecting',
        (_) async {
          final events = <bool>[];
          final subscription = peripheral.connections.listen(events.add);
          addTearDown(subscription.cancel);

          await peripheral.requestDisconnect(Duration.zero);
          await _waitForDisconnect(peripheral);
          await Future<void>.delayed(const Duration(milliseconds: 500));

          expect(events.where((connected) => !connected), hasLength(1));
        },
      );
      testWidgets(
        '[FIT-CONN-003] reconnects after an immediate peripheral disconnect',
        (_) async {
          await peripheral.requestDisconnect(Duration.zero);
          await _waitForDisconnect(peripheral);

          await peripheral.reconnect();

          expect(
            await UniversalBle.getConnectionState(peripheral.deviceId),
            BleConnectionState.connected,
          );
          expect(
            utf8.decode(await peripheral.read(HilUuid.read)),
            'HIL-READ-V1',
          );
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );
      _pending(
        '[FIT-CONN-004] recovers when the peripheral reboots immediately after connecting',
      );
      _pending(
        '[FIT-CONN-005] ignores completion from a superseded connection attempt',
      );
      _pending(
        '[FIT-CONN-006] prevents an older disconnect callback from removing a replacement connection',
      );
      testWidgets(
        '[FIT-CONN-007] handles a host disconnect racing a peripheral disconnect',
        (_) async {
          await peripheral.requestDisconnect(const Duration(milliseconds: 25));
          await Future.wait<void>([
            UniversalBle.disconnect(
              peripheral.deviceId,
              timeout: HilPeripheral.operationTimeout,
            ).catchError((_) {}),
            _waitForDisconnect(peripheral),
          ]);

          await peripheral.reconnect();
          expect(
            (await peripheral.readState()).contractRevision,
            HilPeripheral.contractRevision,
          );
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );
      _pending(
        '[FIT-CONN-008] handles two concurrent connect requests without duplicate connected events',
      );
      _pending(
        '[FIT-CONN-009] handles disconnect while a connection attempt is pending',
      );
      testWidgets(
        '[FIT-CONN-010] reconnects after repeated peripheral disconnect cycles',
        (_) async {
          const cycles = 5;
          for (var cycle = 0; cycle < cycles; cycle++) {
            await peripheral.requestDisconnect(Duration.zero);
            await _waitForDisconnect(peripheral);
            await peripheral.reconnect();
            expect(
              (await peripheral.readState()).contractRevision,
              HilPeripheral.contractRevision,
            );
          }
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );
      _pending(
        '[FIT-CONN-011] reconnects after repeated peripheral reboot cycles',
      );
      _pending(
        '[FIT-CONN-012] remains usable after a connection timeout followed by a successful connection',
      );
      testWidgets(
        '[FIT-CONN-013] emits connection events in order during rapid disconnect and reconnect cycles',
        (_) async {
          const cycles = 5;
          final events = <bool>[];
          final subscription = peripheral.connections.listen(events.add);
          addTearDown(subscription.cancel);

          for (var cycle = 0; cycle < cycles; cycle++) {
            await peripheral.requestDisconnect(Duration.zero);
            await _waitForDisconnect(peripheral);
            await peripheral.reconnect();
            await _waitUntil(
              () async =>
                  events.where((connected) => connected).length >= cycle + 1,
            );
          }

          final transitions = <bool>[];
          for (final event in events) {
            if (transitions.isEmpty || transitions.last != event) {
              transitions.add(event);
            }
          }
          expect(
            transitions,
            containsAllInOrder(
              List<bool>.generate(cycles * 2, (index) => index.isOdd),
            ),
          );
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );
      _pending(
        '[FIT-CONN-014] does not emit a stale connection failure after a newer connection succeeds',
      );
    });

    group('service discovery and GATT database changes', () {
      _pending(
        '[FIT-DISC-001] fails safely when the peripheral disconnects during service discovery',
      );
      _pending(
        '[FIT-DISC-002] recovers when the peripheral reboots during service discovery',
      );
      _pending(
        '[FIT-DISC-003] rediscovers services after the fixture boots with an alternate GATT profile',
      );
      _pending(
        '[FIT-DISC-004] does not reuse a removed characteristic after reconnect',
      );
      _pending(
        '[FIT-DISC-005] observes changed characteristic properties after reconnect',
      );
      _pending(
        '[FIT-DISC-006] observes a newly added descriptor after reconnect',
      );
      _pending(
        '[FIT-DISC-007] invalidates cached services after a Service Changed indication',
      );
      _pending('[FIT-DISC-008] handles a large vanilla GATT service table');
      _pending(
        '[FIT-DISC-009] remains usable after one service discovery returns an ATT error',
      );
      _pending(
        '[FIT-DISC-010] ignores discovery completion from a superseded connection',
      );
    });

    group('read faults', () {
      testWidgets(
        '[FIT-READ-001] reports an ATT read error without disconnecting',
        (_) async {
          await peripheral.armReadFault(attError: 0x0e);
          await expectLater(peripheral.read(HilUuid.read), throwsA(anything));

          expect(
            await UniversalBle.getConnectionState(peripheral.deviceId),
            BleConnectionState.connected,
          );
          expect(
            utf8.decode(await peripheral.read(HilUuid.read)),
            'HIL-READ-V1',
          );
        },
      );
      _pending(
        '[FIT-READ-002] reports an insufficient authentication read error',
      );
      _pending(
        '[FIT-READ-003] reports an insufficient authorization read error',
      );
      _pending('[FIT-READ-004] reports an invalid offset during a long read');
      testWidgets('[FIT-READ-005] returns an empty characteristic value', (
        _,
      ) async {
        await peripheral.setReadValue(const []);
        expect(await peripheral.read(HilUuid.read), isEmpty);
      });
      testWidgets('[FIT-READ-006] returns values at ATT payload boundaries', (
        _,
      ) async {
        for (final size in [1, 20, 22, 23, 64, 128, 244]) {
          final expected = List<int>.generate(size, (index) => index & 0xff);
          await peripheral.setReadValue(expected);
          expect(await peripheral.read(HilUuid.read), orderedEquals(expected));
        }
      });
      testWidgets(
        '[FIT-READ-007] times out a deliberately blocked read callback',
        (_) async {
          await peripheral.armReadFault(delay: const Duration(seconds: 11));
          await expectLater(peripheral.read(HilUuid.read), throwsA(anything));
          await Future<void>.delayed(const Duration(seconds: 2));

          expect(
            utf8.decode(await peripheral.read(HilUuid.read)),
            'HIL-READ-V1',
          );
        },
        timeout: const Timeout(Duration(minutes: 1)),
      );
      testWidgets(
        '[FIT-READ-008] fails safely when the peripheral disconnects before the read callback returns',
        (_) async {
          await peripheral.armReadFault(
            delay: const Duration(seconds: 1),
            disconnectAfter: const Duration(milliseconds: 50),
          );
          await expectLater(peripheral.read(HilUuid.read), throwsA(anything));
          await _waitForDisconnect(peripheral);

          await peripheral.reconnect();
          expect(
            utf8.decode(await peripheral.read(HilUuid.read)),
            'HIL-READ-V1',
          );
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );
      _pending(
        '[FIT-READ-009] fails safely when the peripheral reboots during a read',
      );
      _pending(
        '[FIT-READ-010] ignores a read completion from a previous connection',
      );
      testWidgets(
        '[FIT-READ-011] completes concurrent reads on different characteristics independently',
        (_) async {
          UniversalBle.queueType = QueueType.none;
          final values = await Future.wait([
            peripheral.read(HilUuid.read),
            peripheral.read(HilUuid.state),
            peripheral.read(HilUuid.writeMirror),
          ]);

          expect(utf8.decode(values[0]), 'HIL-READ-V1');
          expect(
            HilState.fromBytes(values[1]).contractRevision,
            HilPeripheral.contractRevision,
          );
          expect(values[2], isEmpty);
        },
      );
      _pending(
        '[FIT-READ-012] recovers with a successful read after every injected read failure',
      );
    });

    group('write-with-response faults', () {
      testWidgets(
        '[FIT-WRITE-001] reports an ATT write error without disconnecting',
        (_) async {
          await peripheral.armWriteFault(attError: 0x0e);
          await expectLater(
            peripheral.write(HilUuid.write, [0x01]),
            throwsA(anything),
          );

          expect(
            await UniversalBle.getConnectionState(peripheral.deviceId),
            BleConnectionState.connected,
          );
          await peripheral.write(HilUuid.write, [0x02]);
          expect(await peripheral.read(HilUuid.writeMirror), [0x02]);
        },
      );
      _pending(
        '[FIT-WRITE-002] reports an insufficient authentication write error',
      );
      _pending(
        '[FIT-WRITE-003] reports an insufficient authorization write error',
      );
      _pending('[FIT-WRITE-004] reports an invalid offset during a long write');
      _pending('[FIT-WRITE-005] reports an invalid attribute length');
      testWidgets(
        '[FIT-WRITE-006] times out a deliberately blocked write callback',
        (_) async {
          await peripheral.armWriteFault(delay: const Duration(seconds: 11));
          await expectLater(
            peripheral.write(HilUuid.write, [0x06]),
            throwsA(anything),
          );
          await Future<void>.delayed(const Duration(seconds: 2));

          await peripheral.write(HilUuid.write, [0x60]);
          expect(await peripheral.read(HilUuid.writeMirror), [0x60]);
        },
        timeout: const Timeout(Duration(minutes: 1)),
      );
      testWidgets(
        '[FIT-WRITE-007] fails safely when the peripheral disconnects before acknowledging a write',
        (_) async {
          await peripheral.armWriteFault(
            delay: const Duration(seconds: 1),
            disconnectAfter: const Duration(milliseconds: 50),
          );
          await expectLater(
            peripheral.write(HilUuid.write, [0x07]),
            throwsA(anything),
          );
          await _waitForDisconnect(peripheral);

          await peripheral.reconnect();
          await peripheral.write(HilUuid.write, [0x70]);
          expect(await peripheral.read(HilUuid.writeMirror), [0x70]);
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );
      _pending(
        '[FIT-WRITE-008] defines the result when the peripheral disconnects after accepting a write',
      );
      _pending(
        '[FIT-WRITE-009] fails safely when the peripheral reboots during a write',
      );
      _pending(
        '[FIT-WRITE-010] ignores a write completion from a previous connection',
      );
      _pending(
        '[FIT-WRITE-011] completes concurrent writes to different characteristics independently',
      );
      _pending(
        '[FIT-WRITE-012] recovers with a verified mirrored write after every injected write failure',
      );
    });

    group('write-without-response faults', () {
      _pending(
        '[FIT-WNR-001] remains connected when the peripheral rejects a command write',
      );
      _pending(
        '[FIT-WNR-002] detects through the firmware journal that a command write was not accepted',
      );
      _pending(
        '[FIT-WNR-003] handles peripheral disconnect immediately after a command write',
      );
      _pending(
        '[FIT-WNR-004] handles peripheral reboot during a stream of command writes',
      );
      _pending(
        '[FIT-WNR-005] applies backpressure during a sustained command-write burst',
      );
      _pending(
        '[FIT-WNR-006] preserves accepted command-write ordering under load',
      );
      _pending(
        '[FIT-WNR-007] reconnects and writes successfully after command-write buffer exhaustion',
      );
    });

    group('notification subscription faults', () {
      _pending(
        '[FIT-SUB-001] fails safely when the peripheral disconnects during CCC enable',
      );
      _pending(
        '[FIT-SUB-002] fails safely when the peripheral reboots during CCC enable',
      );
      _pending(
        '[FIT-SUB-003] reports authorization rejection of a CCC enable write',
      );
      _pending(
        '[FIT-SUB-004] times out a deliberately blocked CCC enable authorization callback',
      );
      _pending(
        '[FIT-SUB-005] rolls back a handler when disconnect occurs after registration',
      );
      _pending(
        '[FIT-SUB-006] allows subscription recovery after a failed CCC enable',
      );
      _pending(
        '[FIT-SUB-007] fails safely when the peripheral disconnects during CCC disable',
      );
      _pending(
        '[FIT-SUB-008] fails safely when the peripheral reboots during CCC disable',
      );
      _pending(
        '[FIT-SUB-009] reports authorization rejection of a CCC disable write',
      );
      _pending(
        '[FIT-SUB-010] allows unsubscribe recovery after a failed CCC disable',
      );
      _pending(
        '[FIT-SUB-011] serializes overlapping enable and disable operations on one characteristic',
      );
      _pending(
        '[FIT-SUB-012] keeps operations on different characteristics independent',
      );
      testWidgets(
        '[FIT-SUB-013] does not retain a subscription from a previous connection',
        (_) async {
          await peripheral.subscribe(HilUuid.notify);
          expect((await peripheral.readState()).notificationsEnabled, isTrue);
          await peripheral.requestDisconnect(Duration.zero);
          await _waitForDisconnect(peripheral);
          await peripheral.reconnect();

          expect((await peripheral.readState()).notificationsEnabled, isFalse);
          await peripheral.subscribe(HilUuid.notify);
          final received = peripheral.values(HilUuid.notify).first;
          await peripheral.requestNotification([0x13]);
          expect(await received.timeout(HilPeripheral.operationTimeout), [
            0x13,
          ]);
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );
      testWidgets(
        '[FIT-SUB-014] does not register duplicate callbacks after repeated resubscription',
        (_) async {
          for (var cycle = 0; cycle < 5; cycle++) {
            await peripheral.subscribe(HilUuid.notify);
            await peripheral.unsubscribe(HilUuid.notify);
          }
          await peripheral.subscribe(HilUuid.notify);

          final values = <List<int>>[];
          final subscription = peripheral
              .values(HilUuid.notify)
              .listen(values.add);
          addTearDown(subscription.cancel);
          await peripheral.requestNotification([0x14]);
          await _waitUntil(() async => values.isNotEmpty);
          await Future<void>.delayed(const Duration(milliseconds: 300));

          expect(values, [
            [0x14],
          ]);
        },
      );
      testWidgets(
        '[FIT-SUB-015] remains usable after rapid subscribe and unsubscribe cycles',
        (_) async {
          for (var cycle = 0; cycle < 10; cycle++) {
            await peripheral.subscribe(HilUuid.notify);
            await peripheral.unsubscribe(HilUuid.notify);
          }
          await peripheral.subscribe(HilUuid.notify);
          final received = peripheral.values(HilUuid.notify).first;
          await peripheral.requestNotification([0x15]);
          expect(await received.timeout(HilPeripheral.operationTimeout), [
            0x15,
          ]);
        },
      );
    });

    group('notification delivery faults', () {
      testWidgets(
        '[FIT-NOTIFY-001] receives a notification emitted immediately after CCC enable',
        (_) async {
          final received = peripheral.values(HilUuid.notify).first;
          await peripheral.subscribe(HilUuid.notify);
          await peripheral.requestNotification([0x01]);
          expect(await received.timeout(HilPeripheral.operationTimeout), [
            0x01,
          ]);
        },
      );
      testWidgets(
        '[FIT-NOTIFY-002] does not deliver values after CCC disable completes',
        (_) async {
          await peripheral.subscribe(HilUuid.notify);
          await peripheral.unsubscribe(HilUuid.notify);
          final values = <List<int>>[];
          final subscription = peripheral
              .values(HilUuid.notify)
              .listen(values.add);
          addTearDown(subscription.cancel);

          await expectLater(
            peripheral.requestNotification([0x02]),
            throwsA(anything),
          );
          await Future<void>.delayed(const Duration(milliseconds: 300));
          expect(values, isEmpty);
        },
      );
      _pending(
        '[FIT-NOTIFY-003] detects an intentionally omitted sequence number',
      );
      _pending(
        '[FIT-NOTIFY-004] preserves an intentionally duplicated sequence number exactly once per packet',
      );
      _pending(
        '[FIT-NOTIFY-005] preserves intentionally reordered application sequence numbers as received',
      );
      testWidgets(
        '[FIT-NOTIFY-006] receives alternating minimum and maximum payload sizes',
        (_) async {
          await peripheral.subscribe(HilUuid.notify);
          final received = peripheral.values(HilUuid.notify).take(4).toList();
          final maximum = List<int>.generate(244, (index) => index & 0xff);

          await peripheral.requestNotification([0]);
          await peripheral.requestNotification(maximum);
          await peripheral.requestNotification([1]);
          await peripheral.requestNotification(maximum.reversed.toList());

          expect(await received.timeout(HilPeripheral.operationTimeout), [
            [0],
            maximum,
            [1],
            maximum.reversed.toList(),
          ]);
        },
      );
      _pending(
        '[FIT-NOTIFY-007] keeps two notification characteristics isolated under interleaved load',
      );
      testWidgets(
        '[FIT-NOTIFY-008] reports disconnect during a notification burst without hanging',
        (_) async {
          await peripheral.subscribe(HilUuid.notify);
          final values = <List<int>>[];
          final subscription = peripheral
              .values(HilUuid.notify)
              .listen(values.add);
          addTearDown(subscription.cancel);
          await peripheral.requestNotificationBurst(
            count: 100,
            size: 64,
            interval: const Duration(milliseconds: 10),
          );
          await peripheral.requestDisconnect(const Duration(milliseconds: 100));

          await _waitForDisconnect(peripheral);
          expect(values, isNotEmpty);
          expect(values.length, lessThan(100));
          await peripheral.reconnect();
          expect(
            (await peripheral.readState()).contractRevision,
            HilPeripheral.contractRevision,
          );
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );
      _pending(
        '[FIT-NOTIFY-009] reports reboot during a notification burst without hanging',
      );
      testWidgets(
        '[FIT-NOTIFY-010] receives a clean sequence after reconnect and resubscribe',
        (_) async {
          await peripheral.subscribe(HilUuid.notify);
          await peripheral.requestDisconnect(Duration.zero);
          await _waitForDisconnect(peripheral);
          await peripheral.reconnect();
          await peripheral.subscribe(HilUuid.notify);
          final received = peripheral.values(HilUuid.notify).take(5).toList();
          await peripheral.requestNotificationBurst(
            count: 5,
            size: 8,
            interval: const Duration(milliseconds: 20),
          );

          final values = await received.timeout(HilPeripheral.operationTimeout);
          expect(
            values.map((value) => _uint16(value, 0)),
            orderedEquals([0, 1, 2, 3, 4]),
          );
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );
      _pending(
        '[FIT-NOTIFY-011] handles Zephyr notification buffer backpressure without native failure',
      );
      testWidgets(
        '[FIT-NOTIFY-012] completes teardown while notifications are still queued',
        (_) async {
          await peripheral.subscribe(HilUuid.notify);
          await peripheral.requestNotificationBurst(
            count: 500,
            size: 64,
            interval: const Duration(milliseconds: 1),
          );

          await UniversalBle.disconnect(
            peripheral.deviceId,
            timeout: HilPeripheral.operationTimeout,
          );
          await peripheral.reconnect();
          expect(
            (await peripheral.readState()).contractRevision,
            HilPeripheral.contractRevision,
          );
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );
    });

    group('indication delivery faults', () {
      _pending(
        '[FIT-IND-001] receives an indication emitted immediately after CCC enable',
      );
      _pending(
        '[FIT-IND-002] handles peripheral disconnect while an indication is outstanding',
      );
      _pending(
        '[FIT-IND-003] handles peripheral reboot while an indication is outstanding',
      );
      _pending(
        '[FIT-IND-004] prevents a second indication from corrupting an outstanding indication',
      );
      _pending(
        '[FIT-IND-005] resumes indication delivery after reconnect and resubscribe',
      );
      _pending(
        '[FIT-IND-006] keeps indication and notification characteristics independent',
      );
    });

    group('MTU, long values, and resource pressure', () {
      _pending(
        '[FIT-MTU-001] handles disconnect while querying the negotiated MTU',
      );
      _pending(
        '[FIT-MTU-002] handles reboot while querying the negotiated MTU',
      );
      _pending(
        '[FIT-MTU-003] reads and writes at MTU minus ATT header boundaries',
      );
      _pending(
        '[FIT-MTU-004] handles values larger than one ATT payload through supported long operations',
      );
      _pending(
        '[FIT-MTU-005] reports an oversized value rejected by the peripheral',
      );
      _pending(
        '[FIT-MTU-006] recovers after peripheral notification-buffer exhaustion',
      );
      _pending(
        '[FIT-MTU-007] recovers after peripheral prepare-write queue exhaustion',
      );
      _pending(
        '[FIT-MTU-008] remains stable while payload sizes alternate around the negotiated boundary',
      );
    });

    group('pairing, bonding, and encrypted attributes', () {
      _pending(
        '[FIT-SMP-001] triggers pairing when an encrypted read is attempted',
      );
      _pending(
        '[FIT-SMP-002] triggers pairing when an encrypted write is attempted',
      );
      _pending('[FIT-SMP-003] reports a rejected passkey pairing attempt');
      _pending('[FIT-SMP-004] reports a peripheral-cancelled pairing attempt');
      _pending(
        '[FIT-SMP-005] reports disconnect during pairing without hanging',
      );
      _pending(
        '[FIT-SMP-006] reconnects and accesses encrypted attributes with a valid bond',
      );
      _pending(
        '[FIT-SMP-007] reports access failure after the peripheral deletes its bond',
      );
      _pending(
        '[FIT-SMP-008] repairs successfully after both sides remove the bond',
      );
    });

    group('deterministic timing sweeps and recovery', () {
      _pending(
        '[FIT-RACE-001] sweeps disconnect timing across connection establishment',
      );
      _pending(
        '[FIT-RACE-002] sweeps disconnect timing across service discovery',
      );
      _pending('[FIT-RACE-003] sweeps disconnect timing across reads');
      _pending('[FIT-RACE-004] sweeps disconnect timing across writes');
      _pending('[FIT-RACE-005] sweeps disconnect timing across CCC enable');
      _pending('[FIT-RACE-006] sweeps disconnect timing across CCC disable');
      _pending(
        '[FIT-RACE-007] repeats each injected fault with a clean recovery probe',
      );
      _pending(
        '[FIT-RACE-008] replays a timing sweep from a recorded scenario seed',
      );
    });
  });
}

void _pending(String description) {
  testWidgets(description, (_) async {
    fail(
      'Remove skip only after the matching firmware scenario and assertions exist.',
    );
  }, skip: true);
}

Future<void> _waitForDisconnect(HilPeripheral peripheral) async {
  if (await UniversalBle.getConnectionState(peripheral.deviceId) ==
      BleConnectionState.disconnected) {
    return;
  }
  await peripheral.connections
      .firstWhere((connected) => !connected)
      .timeout(HilPeripheral.operationTimeout);
}

Future<void> _waitUntil(
  Future<bool> Function() condition, {
  Duration timeout = HilPeripheral.operationTimeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  fail('Condition was not satisfied within $timeout');
}

int _uint16(List<int> value, int offset) =>
    value[offset] | value[offset + 1] << 8;
