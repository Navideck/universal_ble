import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';

class MockPeripheralPlatform extends Fake implements UniversalBlePeripheralPlatform {
  final List<String> callLog = [];
  Completer<void>? notifyCompleter;

  @override
  bool get hasAddressDeviceIds => true;

  @override
  void dispose() {}

  @override
  Future<void> updateCharacteristicValue({
    required String characteristicId,
    String? instanceId,
    required Uint8List value,
    String? deviceId,
  }) async {
    callLog.add('update:$deviceId:${value.length}');
    if (notifyCompleter != null) {
      await notifyCompleter!.future;
    }
  }

  @override
  Future<void> addService(dynamic service, {Duration? timeout}) async {
    callLog.add('addService');
  }

  @override
  Future<void> startAdvertising({
    required List<String> services,
    String? localName,
    Duration? timeout,
    dynamic manufacturerData,
    dynamic platformConfig,
  }) async {
    callLog.add('startAdvertising');
  }

  @override
  Future<void> stopAdvertising() async {
    callLog.add('stopAdvertising');
  }
}

void main() {
  group('UniversalBlePeripheral Command Queue', () {
    late MockPeripheralPlatform mockPlatform;

    setUp(() {
      mockPlatform = MockPeripheralPlatform();
      UniversalBlePeripheral.setInstance(mockPlatform);
      UniversalBlePeripheral.queueType = QueueType.global;
      UniversalBlePeripheral.timeout = const Duration(seconds: 5);
    });

    tearDown(() {
      UniversalBlePeripheral.clearQueue();
      UniversalBlePeripheral.queueType = QueueType.global;
      // Restore the documented default so a test's short timeout cannot leak
      // into the next one.
      UniversalBlePeripheral.timeout = const Duration(seconds: 10);
    });

    test('serializes updateCharacteristicValue in global queue mode', () async {
      UniversalBlePeripheral.queueType = QueueType.global;
      final release = Completer<void>();
      mockPlatform.notifyCompleter = release;

      final first = UniversalBlePeripheral.updateCharacteristicValue(
        characteristicId: 'fa5a0003',
        value: Uint8List.fromList([1, 2, 3]),
        deviceId: 'device-1',
      );
      final second = UniversalBlePeripheral.updateCharacteristicValue(
        characteristicId: 'fa5a0003',
        value: Uint8List.fromList([4, 5, 6, 7]),
        deviceId: 'device-2',
      );

      await pumpEventQueue();
      // First is executing, second is queued
      expect(mockPlatform.callLog, equals(['update:device-1:3']));

      // Release first
      release.complete();
      await first;
      await second;

      expect(mockPlatform.callLog, equals(['update:device-1:3', 'update:device-2:4']));
    });

    test('isolates updateCharacteristicValue by deviceId in perDevice mode', () async {
      UniversalBlePeripheral.queueType = QueueType.perDevice;
      final releaseA = Completer<void>();
      mockPlatform.notifyCompleter = releaseA;

      final firstA = UniversalBlePeripheral.updateCharacteristicValue(
        characteristicId: 'fa5a0003',
        value: Uint8List.fromList([1]),
        deviceId: 'device-a',
      );
      final secondA = UniversalBlePeripheral.updateCharacteristicValue(
        characteristicId: 'fa5a0003',
        value: Uint8List.fromList([2]),
        deviceId: 'device-a',
      );

      await pumpEventQueue();
      expect(mockPlatform.callLog, equals(['update:device-a:1']));

      // Set completer to null so device-b completes immediately
      mockPlatform.notifyCompleter = null;
      final firstB = UniversalBlePeripheral.updateCharacteristicValue(
        characteristicId: 'fa5a0003',
        value: Uint8List.fromList([3]),
        deviceId: 'device-b',
      );

      await firstB;
      // device-b executed independently while device-a was blocked
      expect(mockPlatform.callLog, equals(['update:device-a:1', 'update:device-b:1']));

      releaseA.complete();
      await firstA;
      await secondA;

      expect(mockPlatform.callLog, equals([
        'update:device-a:1',
        'update:device-b:1',
        'update:device-a:1',
      ]));
    });

    test('clearQueue cancels pending peripheral commands', () async {
      UniversalBlePeripheral.queueType = QueueType.global;
      final release = Completer<void>();
      mockPlatform.notifyCompleter = release;

      final first = UniversalBlePeripheral.updateCharacteristicValue(
        characteristicId: 'fa5a0003',
        value: Uint8List.fromList([1]),
        deviceId: 'device-1',
      );
      final pending = UniversalBlePeripheral.updateCharacteristicValue(
        characteristicId: 'fa5a0003',
        value: Uint8List.fromList([2]),
        deviceId: 'device-1',
      );

      await pumpEventQueue();
      UniversalBlePeripheral.clearQueue();

      await expectLater(pending, throwsA(isA<Exception>()));

      release.complete();
      await first;
    });

    test(
        'updateCharacteristicValue times out when the native reply never arrives',
        () async {
      UniversalBlePeripheral.queueType = QueueType.perDevice;
      UniversalBlePeripheral.timeout = const Duration(milliseconds: 50);
      mockPlatform.notifyCompleter = Completer<void>();

      final update = UniversalBlePeripheral.updateCharacteristicValue(
        characteristicId: 'fa5a0003',
        value: Uint8List.fromList([1]),
        deviceId: 'device-1',
      );

      await expectLater(update, throwsA(isA<TimeoutException>()));
    });

    test('a timed-out update does not wedge the peripheral queue', () async {
      UniversalBlePeripheral.queueType = QueueType.perDevice;
      UniversalBlePeripheral.timeout = const Duration(milliseconds: 50);
      mockPlatform.notifyCompleter = Completer<void>();

      final stuck = UniversalBlePeripheral.updateCharacteristicValue(
        characteristicId: 'fa5a0003',
        value: Uint8List.fromList([1]),
        deviceId: 'device-1',
      );
      // Queued behind the update that will time out; the queue must run it once
      // the timeout settles the first command.
      final next = UniversalBlePeripheral.updateCharacteristicValue(
        characteristicId: 'fa5a0003',
        value: Uint8List.fromList([2, 3]),
        deviceId: 'device-1',
      );
      mockPlatform.notifyCompleter = null;

      await expectLater(stuck, throwsA(isA<TimeoutException>()));
      await next;

      expect(mockPlatform.callLog, ['update:device-1:1', 'update:device-1:2']);
    });

    test('a command without a queue is bounded by the same timeout', () async {
      UniversalBlePeripheral.queueType = QueueType.none;
      UniversalBlePeripheral.timeout = const Duration(milliseconds: 50);
      mockPlatform.notifyCompleter = Completer<void>();

      final update = UniversalBlePeripheral.updateCharacteristicValue(
        characteristicId: 'fa5a0003',
        value: Uint8List.fromList([1]),
        deviceId: 'device-1',
      );

      await expectLater(update, throwsA(isA<TimeoutException>()));
    });

    test('timeout = null disables the peripheral command timeout', () async {
      UniversalBlePeripheral.queueType = QueueType.perDevice;
      UniversalBlePeripheral.timeout = const Duration(milliseconds: 50);
      UniversalBlePeripheral.timeout = null;

      final release = Completer<void>();
      mockPlatform.notifyCompleter = release;
      var settled = false;
      final update = UniversalBlePeripheral.updateCharacteristicValue(
        characteristicId: 'fa5a0003',
        value: Uint8List.fromList([1]),
        deviceId: 'device-1',
      ).whenComplete(() => settled = true);

      // Longer than the 50 ms timeout the test configured first.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(settled, isFalse,
          reason: 'null must disable the timeout, not fall back to a default');

      release.complete();
      await update;
      expect(settled, isTrue);
    });
  });
}
