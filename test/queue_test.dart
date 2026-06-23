import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/src/queue.dart';

void main() {
  group('Queue', () {
    test('executes commands sequentially in order', () async {
      final queue = Queue();
      final order = <int>[];

      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      final secondStarted = Completer<void>();

      final future1 = queue.add(() async {
        firstStarted.complete();
        await releaseFirst.future;
        order.add(1);
        return 1;
      });
      final future2 = queue.add(() async {
        secondStarted.complete();
        order.add(2);
        return 2;
      });

      await firstStarted.future;
      expect(order, isEmpty);

      releaseFirst.complete();
      await future1;
      await secondStarted.future;
      await future2;

      expect(order, [1, 2]);
    });

    test('completes void commands with null', () async {
      final queue = Queue();

      await queue.add(() async {});

      expect(await queue.add(() async => null), isNull);
    });

    test('returns command results', () async {
      final queue = Queue();

      expect(await queue.add(() async => 42), 42);
      expect(await queue.add(() async => 'ok'), 'ok');
    });

    test('propagates command errors', () async {
      final queue = Queue();

      final future = queue.add(() async {
        throw StateError('failed');
      });

      await expectLater(future, throwsA(isA<StateError>()));
    });

    test('times out slow commands', () async {
      final queue = Queue();

      final future = queue.add(
        () => Future<void>.delayed(const Duration(seconds: 5)),
        const Duration(milliseconds: 50),
      );

      await expectLater(future, throwsA(isA<TimeoutException>()));
    });

    test('reports remaining items via onRemainingItemsUpdate', () async {
      final queue = Queue();
      final remaining = <int>[];

      queue.onRemainingItemsUpdate = remaining.add;

      final release = Completer<void>();
      final started = Completer<void>();

      final first = queue.add(() async {
        started.complete();
        await release.future;
      });
      queue.add(() async {});
      queue.add(() async {});

      await started.future;
      expect(remaining, contains(3));

      release.complete();
      await first;
      await pumpEventQueue();

      expect(remaining.last, 0);
    });

    test('dispose completes pending commands with error', () async {
      final queue = Queue();
      final started = Completer<void>();

      queue.add(() async {
        started.complete();
        await Future<void>.delayed(const Duration(seconds: 5));
      });

      final pending = queue.add(() async => 'pending');

      await started.future;
      queue.dispose();

      await expectLater(
        pending,
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Queue Cancelled'),
          ),
        ),
      );
    });

    test('dispose prevents adding new commands', () {
      final queue = Queue()..dispose();

      expect(
        () => queue.add(() async {}),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Queue Cancelled'),
          ),
        ),
      );
    });

    test('in-flight command completes after dispose', () async {
      final queue = Queue();
      final release = Completer<void>();
      final started = Completer<void>();

      final inFlight = queue.add(() async {
        started.complete();
        await release.future;
        return 'done';
      });

      final pending = queue.add(() async => 'pending');
      unawaited(pending.catchError((_) => 'ignored'));

      await started.future;
      queue.dispose();

      release.complete();
      expect(await inFlight, 'done');
    });
  });
}
