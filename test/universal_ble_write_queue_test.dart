import 'dart:async';

import 'package:flutter/foundation.dart';
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
    debugDefaultTargetPlatformOverride = null;
  });

  test('pipelines consecutive Apple writes', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final platform = _PendingWritePlatform();
    UniversalBle.setInstance(platform);

    final first = _write(1);
    final second = _write(2);

    expect(platform.started, [1, 2]);

    platform.pending[1].complete();
    platform.pending[0].complete();
    await first;
    await second;
  });

  test('keeps Android writes strictly serialized', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
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

  test('does not pipeline an Apple write across a queue barrier', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final platform = _PendingWritePlatform();
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
}

Future<void> _write(int value) =>
    UniversalBle.write('device', '180a', '202a', Uint8List.fromList([value]));

class _PendingWritePlatform extends UniversalBlePlatformMock {
  final started = <int>[];
  final pending = <Completer<void>>[];
  final readPending = Completer<Uint8List>();
  var reads = 0;

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
  Future<int> readRssi(String deviceId) => throw UnimplementedError();

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
