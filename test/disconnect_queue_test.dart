import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/src/utils/ble_command_queue.dart';
import 'package:universal_ble/universal_ble.dart';
import 'universal_ble_test_mock.dart';

class _DisconnectPlatform extends UniversalBlePlatformMock {
  final started = Completer<void>();
  final readFinished = Completer<Uint8List>();
  bool disconnected = false;
  @override
  Future<BleConnectionState> getConnectionState(String id) async =>
      BleConnectionState.connected;
  @override
  Future<Uint8List> readValue(String id, String service, String characteristic,
      {Duration? timeout}) {
    started.complete();
    return readFinished.future;
  }

  @override
  Future<void> disconnect(String id) async {
    disconnected = true;
    readFinished.complete(Uint8List(0));
    updateConnection(id, false);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('public disconnect releases a read waiting for native disconnect',
      () async {
    final platform = _DisconnectPlatform();
    UniversalBle.setInstance(platform);
    UniversalBle.queueType = QueueType.global;
    UniversalBle.timeout = null;
    try {
      final read = UniversalBle.read('AA:BB:CC:DD:EE:FF', '180d', '2a37');
      await platform.started.future;
      await UniversalBle.disconnect('aa:bb:cc:dd:ee:ff')
          .timeout(const Duration(seconds: 1));
      expect(platform.disconnected, isTrue);
      await read;
    } finally {
      if (!platform.readFinished.isCompleted) {
        platform.readFinished.complete(Uint8List(0));
      }
      UniversalBle.clearQueue();
      UniversalBle.setInstance(_DisconnectPlatform());
      UniversalBle.queueType = QueueType.auto;
      UniversalBle.timeout = const Duration(seconds: 10);
    }
  });

  test('queue listeners cannot re-enter before native teardown starts',
      () async {
    final queue = BleCommandQueue(queueType: QueueType.global, isAddress: true);
    final release = Completer<void>();
    final running =
        queue.queueCommand(() => release.future, deviceId: 'AA:BB:CC:DD:EE:FF');
    final pending = queue.queueCommand(() async => fail('canceled command ran'),
        deviceId: 'AA:BB:CC:DD:EE:FF');
    final canceled = expectLater(pending, throwsException);
    var nativeStarted = false;
    var updates = 0;
    queue.onQueueUpdate = (_, __) {
      expect(nativeStarted, isTrue);
      updates++;
      unawaited(queue.runTeardown(() async {}, deviceId: 'AA:BB:CC:DD:EE:FF'));
    };
    await queue.runTeardown(() async {
      nativeStarted = true;
      release.complete();
    }, deviceId: 'AA:BB:CC:DD:EE:FF');
    await running;
    await canceled;
    await Future<void>.delayed(Duration.zero);
    expect(updates, greaterThan(0));
    expect(updates, lessThan(5));
  });

  test('teardown cancels matching commands across two custom queues', () async {
    final queue =
        BleCommandQueue(queueType: QueueType.perDevice, isAddress: true);
    final release = Completer<void>();
    final active = <Future<void>>[];
    final canceled = <Future<void>>[];
    for (final id in ['first', 'second']) {
      active.add(queue.queueCommand(() => release.future,
          deviceId: 'other', queueId: id));
      canceled.add(expectLater(
          queue.queueCommand(() async => fail('canceled command ran'),
              deviceId: 'AA:BB:CC:DD:EE:FF', queueId: id),
          throwsException));
    }
    await queue.runTeardown(() async => release.complete(),
        deviceId: 'aa:bb:cc:dd:ee:ff');
    await Future.wait([...active, ...canceled]);
  });

  test('teardown preserves in-flight work with queueing disabled', () async {
    final queue = BleCommandQueue(queueType: QueueType.none);
    final release = Completer<String>();
    final active = queue.queueCommandWithoutTimeout(() => release.future,
        deviceId: 'device');
    await queue.runTeardown(() async {}, deviceId: 'device');
    release.complete('native result');
    expect(await active, 'native result');
  });

  for (final type in [QueueType.global, QueueType.perDevice, QueueType.auto]) {
    test('$type teardown cancels target across custom queues only', () async {
      final queue = BleCommandQueue(queueType: type, isAddress: true);
      final release = Completer<void>();
      final running = queue.queueCommandWithoutTimeout(() => release.future,
          deviceId: 'AA:BB:CC:DD:EE:FF', queueId: 'shared');
      final pending = queue.queueCommandWithoutTimeout(
          () async => fail('retired command ran'),
          deviceId: 'aa:bb:cc:dd:ee:ff',
          queueId: 'shared');
      final canceled = expectLater(pending, throwsException);
      final other = queue.queueCommandWithoutTimeout(() async => 'other',
          deviceId: '11:22:33:44:55:66', queueId: 'shared');
      await queue.runTeardown(() async {
        release.complete();
      }, deviceId: 'Aa:Bb:Cc:Dd:Ee:Ff');
      await running;
      await canceled;
      expect(await other, 'other');
    });
  }
}
