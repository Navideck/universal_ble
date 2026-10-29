import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:universal_ble/src/universal_ble.g.dart';
import 'package:universal_ble/src/utils/ble_central_tracker.dart';

class _MockPeripheralPlatform extends UniversalBlePeripheralPlatform {
  final List<String> callLog = [];

  @override
  void dispose() {}

  @override
  Future<PeripheralReadinessState> getAvailabilityState() async =>
      PeripheralReadinessState.ready;

  @override
  Future<PeripheralAdvertisingState> getAdvertisingState() async =>
      PeripheralAdvertisingState.idle;

  @override
  Future<BlePeripheralCapabilities> getCapabilities() async =>
      const BlePeripheralCapabilities(
        supportsPeripheralMode: true,
        supportsManufacturerDataInAdvertisement: true,
        supportsManufacturerDataInScanResponse: true,
        supportsServiceDataInAdvertisement: false,
        supportsServiceDataInScanResponse: false,
        supportsTargetedCharacteristicUpdate: true,
        supportsAdvertisingTimeout: true,
      );

  @override
  Future<void> addService(PeripheralService service, {Duration? timeout}) async {
    callLog.add('addService');
  }

  @override
  Future<void> removeService(String serviceId) async {
    callLog.add('removeService');
  }

  @override
  Future<void> clearServices() async {
    callLog.add('clearServices');
  }

  @override
  Future<List<String>> getServices() async => [];

  @override
  Future<void> startAdvertising({
    required List<String> services,
    String? localName,
    Duration? timeout,
    ManufacturerData? manufacturerData,
    PeripheralPlatformConfig? platformConfig,
  }) async {}

  @override
  Future<void> stopAdvertising() async {}

  @override
  Future<void> updateCharacteristicValue({
    required String characteristicId,
    String? instanceId,
    required dynamic value,
    String? deviceId,
  }) async {}

  @override
  Future<List<String>> getSubscribedClients(
    String characteristicId, {
    String? instanceId,
  }) async => [];

  @override
  Future<int?> getMaximumNotifyLength(String deviceId) async => null;

  @override
  void setReadRequestHandler(OnPeripheralReadRequest? handler) {}

  @override
  void setWriteRequestHandler(OnPeripheralWriteRequest? handler) {}

  @override
  void setDescriptorReadRequestHandler(
    OnPeripheralDescriptorReadRequest? handler,
  ) {}

  @override
  void setDescriptorWriteRequestHandler(
    OnPeripheralDescriptorWriteRequest? handler,
  ) {}

  // Expose helpers to simulate platform callbacks
  void emitSubscription({
    required String deviceId,
    required String characteristicId,
    String? instanceId,
    required bool isSubscribed,
    String? name,
  }) {
    updateCharacteristicSubscription(
      BlePeripheralCharacteristicSubscriptionChanged(
        deviceId: deviceId,
        characteristicId: characteristicId,
        instanceId: instanceId,
        isSubscribed: isSubscribed,
        name: name,
      ),
    );
  }

  void emitConnectionState({
    required String deviceId,
    required bool connected,
  }) {
    updateConnectionState(
      BlePeripheralConnectionStateChanged(deviceId, connected),
    );
  }
}

void main() {
  group('BleCentral Model', () {
    test('equality and hashCode', () {
      final central1 = BleCentral(
        id: 'central-1',
        name: 'Phone',
        subscribedCharacteristics: {'2a19', '2a18'},
      );
      final central2 = BleCentral(
        id: 'central-1',
        name: 'Phone',
        subscribedCharacteristics: {'2a18', '2a19'},
      );
      final central3 = BleCentral(
        id: 'central-2',
        name: 'Phone',
        subscribedCharacteristics: {'2a19'},
      );

      expect(central1, equals(central2));
      expect(central1.hashCode, equals(central2.hashCode));
      expect(central1, isNot(equals(central3)));
      expect(
        central1.toString(),
        contains('BleCentral(id: central-1, name: Phone'),
      );
    });

    test('copyWith updates properties', () {
      final central = BleCentral(
        id: 'central-1',
        name: 'Phone',
        subscribedCharacteristics: {'2a19'},
      );

      final updated = central.copyWith(
        name: 'Updated Phone',
        subscribedCharacteristics: {'2a19', '2a37'},
      );

      expect(updated.id, 'central-1');
      expect(updated.name, 'Updated Phone');
      expect(
        updated.subscribedCharacteristics,
        {
          BleUuidParser.string('2a19'),
          BleUuidParser.string('2a37'),
        },
      );
    });

    test('isSubscribedTo normalizes UUID format and case', () {
      final central = BleCentral(
        id: 'central-1',
        subscribedCharacteristics: {'00002a19-0000-1000-8000-00805f9b34fb'},
      );

      expect(central.isSubscribedTo('2a19'), isTrue);
      expect(central.isSubscribedTo('2A19'), isTrue);
      expect(
        central.isSubscribedTo('00002A19-0000-1000-8000-00805F9B34FB'),
        isTrue,
      );
      expect(central.isSubscribedTo('2a18'), isFalse);
    });

    test('isSubscribedTo matches short-form UUIDs passed at construction', () {
      final central = BleCentral(
        id: 'central-1',
        subscribedCharacteristics: {'2a19'},
      );

      expect(central.isSubscribedTo('2a19'), isTrue);
      expect(central.isSubscribedTo('2A19'), isTrue);
      expect(
        central.isSubscribedTo('00002a19-0000-1000-8000-00805f9b34fb'),
        isTrue,
      );
      expect(central.isSubscribedTo('2a18'), isFalse);
    });

    test('subscribedCharacteristics is unmodifiable', () {
      final central = BleCentral(
        id: 'central-1',
        subscribedCharacteristics: {'2a19'},
      );

      expect(
        () => central.subscribedCharacteristics.add('2a18'),
        throwsUnsupportedError,
      );
    });
  });

  group('BleCentralTracker unit tests', () {
    late BleCentralTracker tracker;
    late StreamController<BlePeripheralCharacteristicSubscriptionChanged>
        subController;
    late StreamController<BlePeripheralConnectionStateChanged>
        connController;

    setUp(() {
      tracker = BleCentralTracker();
      subController =
          StreamController<BlePeripheralCharacteristicSubscriptionChanged>.broadcast();
      connController =
          StreamController<BlePeripheralConnectionStateChanged>.broadcast();

      tracker.bindStreams(
        characteristicSubscriptionStream: subController.stream,
        connectionStateStream: connController.stream,
      );
    });

    tearDown(() {
      tracker.dispose();
      subController.close();
      connController.close();
    });

    test('emits empty list initially on stream listen', () async {
      final emitted = await tracker.stream.first;
      expect(emitted, isEmpty);
      expect(tracker.subscribedCentrals, isEmpty);
    });

    test('tracks subscription and normalizes characteristic uuid', () async {
      subController.add(
        BlePeripheralCharacteristicSubscriptionChanged(
          deviceId: 'device-01',
          characteristicId: '2a19',
          isSubscribed: true,
          name: 'Central 1',
        ),
      );

      await Future<void>.delayed(Duration.zero);

      expect(tracker.subscribedCentrals.length, 1);
      final central = tracker.subscribedCentrals.first;
      expect(central.id, 'device-01');
      expect(central.name, 'Central 1');
      expect(central.subscribedCharacteristics, {
        '00002a19-0000-1000-8000-00805f9b34fb',
      });
    });

    test('multi-characteristic subscription for same central', () async {
      subController.add(
        BlePeripheralCharacteristicSubscriptionChanged(
          deviceId: 'device-01',
          characteristicId: '2a19',
          isSubscribed: true,
          name: 'Central 1',
        ),
      );
      subController.add(
        BlePeripheralCharacteristicSubscriptionChanged(
          deviceId: 'device-01',
          characteristicId: '2a18',
          isSubscribed: true,
          name: 'Central 1',
        ),
      );

      await Future<void>.delayed(Duration.zero);

      expect(tracker.subscribedCentrals.length, 1);
      expect(tracker.subscribedCentrals.first.subscribedCharacteristics.length, 2);

      // Unsubscribe from only one characteristic
      subController.add(
        BlePeripheralCharacteristicSubscriptionChanged(
          deviceId: 'device-01',
          characteristicId: '2a19',
          isSubscribed: false,
          name: 'Central 1',
        ),
      );

      await Future<void>.delayed(Duration.zero);

      expect(tracker.subscribedCentrals.length, 1);
      expect(tracker.subscribedCentrals.first.subscribedCharacteristics, {
        '00002a18-0000-1000-8000-00805f9b34fb',
      });

      // Unsubscribe from last characteristic -> central pruned
      subController.add(
        BlePeripheralCharacteristicSubscriptionChanged(
          deviceId: 'device-01',
          characteristicId: '2a18',
          isSubscribed: false,
          name: 'Central 1',
        ),
      );

      await Future<void>.delayed(Duration.zero);

      expect(tracker.subscribedCentrals, isEmpty);
    });

    test('prunes central on disconnect event', () async {
      subController.add(
        BlePeripheralCharacteristicSubscriptionChanged(
          deviceId: 'device-01',
          characteristicId: '2a19',
          isSubscribed: true,
          name: 'Central 1',
        ),
      );

      await Future<void>.delayed(Duration.zero);
      expect(tracker.subscribedCentrals.length, 1);

      connController.add(
        BlePeripheralConnectionStateChanged('device-01', false),
      );

      await Future<void>.delayed(Duration.zero);
      expect(tracker.subscribedCentrals, isEmpty);
    });

    test('handles case-insensitive device IDs correctly', () async {
      subController.add(
        BlePeripheralCharacteristicSubscriptionChanged(
          deviceId: 'AA:BB:CC:DD:EE:FF',
          characteristicId: '2a19',
          isSubscribed: true,
          name: 'Central 1',
        ),
      );

      await Future<void>.delayed(Duration.zero);
      expect(tracker.subscribedCentrals.length, 1);

      // Disconnect with lower-case ID
      connController.add(
        BlePeripheralConnectionStateChanged('aa:bb:cc:dd:ee:ff', false),
      );

      await Future<void>.delayed(Duration.zero);
      expect(tracker.subscribedCentrals, isEmpty);
    });

    test('deduplicates identical subscription events', () async {
      final emittedEvents = <List<BleCentral>>[];
      final sub = tracker.stream.listen(emittedEvents.add);
      await Future<void>.delayed(Duration.zero);
      expect(emittedEvents.length, 1);

      // First subscription event
      subController.add(
        BlePeripheralCharacteristicSubscriptionChanged(
          deviceId: 'device-01',
          characteristicId: '2a19',
          isSubscribed: true,
          name: 'Device Alpha',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(emittedEvents.length, 2);

      // Redundant duplicate subscription event
      subController.add(
        BlePeripheralCharacteristicSubscriptionChanged(
          deviceId: 'device-01',
          characteristicId: '2a19',
          isSubscribed: true,
          name: 'Device Alpha',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(emittedEvents.length, 2); // Did not re-emit

      // Redundant unsubscription of a non-subscribed characteristic
      subController.add(
        BlePeripheralCharacteristicSubscriptionChanged(
          deviceId: 'device-01',
          characteristicId: '2a18',
          isSubscribed: false,
          name: 'Device Alpha',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(emittedEvents.length, 2); // Did not re-emit

      await sub.cancel();
    });

    test('reset clears map and cancels stream subscriptions', () async {
      subController.add(
        BlePeripheralCharacteristicSubscriptionChanged(
          deviceId: 'device-01',
          characteristicId: '2a19',
          isSubscribed: true,
          name: 'Central 1',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(tracker.subscribedCentrals.length, 1);

      tracker.reset();
      expect(tracker.subscribedCentrals, isEmpty);

      // Events on old streams are no longer processed after reset
      subController.add(
        BlePeripheralCharacteristicSubscriptionChanged(
          deviceId: 'device-02',
          characteristicId: '2a19',
          isSubscribed: true,
          name: 'Central 2',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(tracker.subscribedCentrals, isEmpty);
    });

    test('emits initial snapshot to concurrent listeners that attach later', () async {
      subController.add(
        BlePeripheralCharacteristicSubscriptionChanged(
          deviceId: 'device-01',
          characteristicId: '2a19',
          isSubscribed: true,
          name: 'Central 1',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(tracker.subscribedCentrals.length, 1);

      final events1 = <List<BleCentral>>[];
      final sub1 = tracker.stream.listen(events1.add);
      await Future<void>.delayed(Duration.zero);
      expect(events1.length, 1);
      expect(events1.first.length, 1);

      // Second listener attaches while first listener is still active
      final events2 = <List<BleCentral>>[];
      final sub2 = tracker.stream.listen(events2.add);
      await Future<void>.delayed(Duration.zero);
      expect(events2.length, 1);
      expect(events2.first.length, 1);
      expect(events2.first.first.id, 'device-01');

      await sub1.cancel();
      await sub2.cancel();
    });

    test('removeService prunes subscriptions and removes central if empty', () async {
      tracker.registerService('180D', ['2a37', '2a38']);
      tracker.registerService('180F', ['2a19']);

      subController.add(
        BlePeripheralCharacteristicSubscriptionChanged(
          deviceId: 'device-01',
          characteristicId: '2a37',
          isSubscribed: true,
          name: 'Heart Rate Monitor',
        ),
      );
      subController.add(
        BlePeripheralCharacteristicSubscriptionChanged(
          deviceId: 'device-01',
          characteristicId: '2a19',
          isSubscribed: true,
          name: 'Heart Rate Monitor',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(tracker.subscribedCentrals.first.subscribedCharacteristics.length, 2);

      // Removing 180F removes 2a19, but central still has 2a37
      tracker.removeService('180F');
      expect(tracker.subscribedCentrals.length, 1);
      expect(tracker.subscribedCentrals.first.subscribedCharacteristics.length, 1);
      expect(tracker.subscribedCentrals.first.isSubscribedTo('2a37'), isTrue);
      expect(tracker.subscribedCentrals.first.isSubscribedTo('2a19'), isFalse);

      // Removing 180D removes 2a37; central has 0 characteristics left -> removed
      tracker.removeService('180D');
      expect(tracker.subscribedCentrals, isEmpty);
    });
  });

  group('UniversalBlePeripheral subscribedCentrals integration', () {
    late _MockPeripheralPlatform mockPlatform;

    setUp(() {
      mockPlatform = _MockPeripheralPlatform();
      UniversalBlePeripheral.setInstance(mockPlatform);
    });

    test('tracks subscribed centrals via UniversalBlePeripheral streams', () async {
      expect(UniversalBlePeripheral.subscribedCentrals, isEmpty);

      final events = <List<BleCentral>>[];
      final sub = UniversalBlePeripheral.subscribedCentralsStream.listen(events.add);

      await Future<void>.delayed(Duration.zero);
      expect(events.length, 1);
      expect(events.first, isEmpty);

      mockPlatform.emitSubscription(
        deviceId: 'central-alpha',
        characteristicId: '2a19',
        isSubscribed: true,
        name: 'Device Alpha',
      );

      await Future<void>.delayed(Duration.zero);
      expect(events.length, 2);
      expect(events.last.length, 1);
      expect(events.last.first.id, 'central-alpha');
      expect(UniversalBlePeripheral.subscribedCentrals.length, 1);

      // Clear services resets tracker
      await UniversalBlePeripheral.clearServices();
      expect(mockPlatform.callLog, contains('clearServices'));
      expect(UniversalBlePeripheral.subscribedCentrals, isEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(events.last, isEmpty);

      await sub.cancel();
    });

    test('removeService drops characteristic subscriptions and removes empty centrals', () async {
      await UniversalBlePeripheral.addService(
        BlePeripheralService(
          uuid: '180D',
          characteristics: [
            BlePeripheralCharacteristic(
              uuid: '2a37',
              properties: [CharacteristicProperty.notify],
              permissions: [PeripheralAttributePermission.readable],
            ),
          ],
        ),
      );

      mockPlatform.emitSubscription(
        deviceId: 'central-alpha',
        characteristicId: '2a37',
        isSubscribed: true,
        name: 'Device Alpha',
      );
      await Future<void>.delayed(Duration.zero);
      expect(UniversalBlePeripheral.subscribedCentrals.length, 1);

      await UniversalBlePeripheral.removeService('180D');
      expect(mockPlatform.callLog, contains('removeService'));
      expect(UniversalBlePeripheral.subscribedCentrals, isEmpty);
    });
  });
}
