import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';

import 'universal_ble_test_mock.dart';

void main() {
  setUp(() {
    UniversalBle.clearQueue();
    UniversalBle.queueType = QueueType.global;
  });

  tearDown(() {
    UniversalBle.clearQueue();
  });

  test('pipelines writes when supported by the platform', () async {
    final platform = _PendingWritePlatform(supportsWritePipelining: true);
    UniversalBle.setInstance(platform);

    final first = _write(1);
    final second = _write(2);

    expect(platform.started, [1, 2]);

    platform.pending[1].complete();
    platform.pending[0].complete();
    await first;
    await second;
  });

  test('serializes writes when pipelining is unsupported', () async {
    final platform = _PendingWritePlatform();
    UniversalBle.setInstance(platform);

    final first = _write(1);
    final second = _write(2);

    expect(platform.started, [1]);

    platform.pending.single.complete();
    await first;
    await pumpEventQueue();
    expect(platform.started, [1, 2]);

    platform.pending[1].complete();
    await second;
  });

  test('does not pipeline a write across a queue barrier', () async {
    final platform = _PendingWritePlatform(supportsWritePipelining: true);
    UniversalBle.setInstance(platform);

    final read = UniversalBle.read('device', '180a', '202a');
    final write = _write(1);

    expect(platform.reads, 1);
    expect(platform.started, isEmpty);

    platform.readPending.complete(Uint8List(0));
    await read;
    await pumpEventQueue();
    expect(platform.started, [1]);

    platform.pending.single.complete();
    await write;
  });

  test('readRssi bypasses queue by default and does not block queued writes', () async {
    final platform = _PendingWritePlatform();
    UniversalBle.setInstance(platform);

    final rssiFuture = UniversalBle.readRssi('device');
    expect(platform.rssiReads, 1);

    // A write should start immediately even though readRssi is pending
    final writeFuture = _write(1);
    await pumpEventQueue();
    expect(platform.started, [1]);

    platform.pending.single.complete();
    await writeFuture;

    platform.rssiPending.complete(-65);
    expect(await rssiFuture, -65);
  });

  test('readRssi respects explicit queueId', () async {
    final platform = _PendingWritePlatform();
    UniversalBle.setInstance(platform);

    final readFuture = UniversalBle.read('device', '180a', '202a', queueId: 'custom');
    expect(platform.reads, 1);

    final rssiFuture = UniversalBle.readRssi('device', queueId: 'custom');
    await pumpEventQueue();
    // Because 'custom' queue is blocked by readFuture, readRssi should not have started
    expect(platform.rssiReads, 0);

    platform.readPending.complete(Uint8List(0));
    await readFuture;
    await pumpEventQueue();
    expect(platform.rssiReads, 1);

    platform.rssiPending.complete(-70);
    expect(await rssiFuture, -70);
  });
}

Future<void> _write(int value) =>
    UniversalBle.write('device', '180a', '202a', Uint8List.fromList([value]));

class _PendingWritePlatform extends UniversalBlePlatformMock {
  @override
  final bool supportsWritePipelining;

  _PendingWritePlatform({this.supportsWritePipelining = false});

  final started = <int>[];
  final pending = <Completer<void>>[];
  final readPending = Completer<Uint8List>();
  final rssiPending = Completer<int>();
  var reads = 0;
  var rssiReads = 0;

  @override
  Future<Uint8List> readValue(
    String deviceId,
    String service,
    String characteristic, {
    Duration? timeout,
  }) {
    reads++;
    return readPending.future;
  }

  @override
  Future<int> readRssi(String deviceId) {
    rssiReads++;
    return rssiPending.future;
  }

  @override
  Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  ) {
    started.add(value.single);
    final completion = Completer<void>();
    pending.add(completion);
    return completion.future;
  }
}
