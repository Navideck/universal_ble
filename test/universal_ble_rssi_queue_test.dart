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

  test('readRssi bypasses queue by default and does not block queued writes',
      () async {
    final platform = _PendingPlatform();
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

  test('readRssi is not queued even when queue is blocked', () async {
    final platform = _PendingPlatform();
    UniversalBle.setInstance(platform);

    final readFuture = UniversalBle.read('device', '180a', '202a');
    expect(platform.reads, 1);

    // readRssi should execute immediately without waiting for readFuture
    final rssiFuture = UniversalBle.readRssi('device');
    await pumpEventQueue();
    expect(platform.rssiReads, 1);

    platform.rssiPending.complete(-70);
    expect(await rssiFuture, -70);

    platform.readPending.complete(Uint8List(0));
    await readFuture;
  });
}

Future<void> _write(int value) =>
    UniversalBle.write('device', '180a', '202a', Uint8List.fromList([value]));

class _PendingPlatform extends UniversalBlePlatformMock {
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
