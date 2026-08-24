import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';

class MockPeripheralPlatform extends Fake implements UniversalBlePeripheralPlatform {
  final List<String> callLog = [];
  Completer<void>? notifyCompleter;

  @override
  void dispose() {}

  @override
  Future<void> updateCharacteristicValue({
    required String characteristicId,
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

      await Future<void>.delayed(const Duration(milliseconds: 10));
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

      await Future<void>.delayed(const Duration(milliseconds: 10));
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

      await Future<void>.delayed(const Duration(milliseconds: 10));
      UniversalBlePeripheral.clearQueue();

      await expectLater(pending, throwsA(isA<Exception>()));

      release.complete();
      await first;
    });
  });
}
