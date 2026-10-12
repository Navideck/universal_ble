import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/src/universal_ble_pigeon/universal_ble_pigeon_channel.dart';
import 'package:universal_ble/universal_ble.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BleConnectionParametersChangeX', () {
    test('intervalMs and supervisionTimeoutMs', () {
      final update = BleConnectionParametersChange(
        deviceId: 'aa:bb:cc:dd:ee:ff',
        interval: 12,
        latency: 0,
        supervisionTimeout: 500,
        status: 0,
      );
      expect(update.intervalMs, 15.0);
      expect(update.supervisionTimeoutMs, 5000.0);
      expect(update.isSuccess, isTrue);
    });

    test('estimatedPriority heuristic', () {
      expect(
        _update(interval: 12).estimatedPriority,
        BleConnectionPriority.highPerformance,
      );
      expect(
        _update(interval: 40).estimatedPriority,
        BleConnectionPriority.balanced,
      );
      expect(
        _update(interval: 420).estimatedPriority,
        BleConnectionPriority.lowPower,
      );
    });
  });

  group('updateConnectionParameters dedupe', () {
    late UniversalBlePigeonChannel platform;

    setUp(() {
      platform = UniversalBlePigeonChannel.instance;
    });

    test('skips consecutive identical updates', () async {
      final events = <BleConnectionParametersChange>[];
      platform.onConnectionParametersChange = events.add;

      final update = BleConnectionParametersChange(
        deviceId: 'aa:bb:cc:dd:ee:ff',
        interval: 12,
        latency: 0,
        supervisionTimeout: 500,
        status: 0,
      );
      platform.updateConnectionParameters(update);
      platform.updateConnectionParameters(update);
      platform.updateConnectionParameters(
        BleConnectionParametersChange(
          deviceId: update.deviceId,
          interval: 420,
          latency: update.latency,
          supervisionTimeout: update.supervisionTimeout,
          status: update.status,
        ),
      );

      expect(events, hasLength(2));
      expect(events.first.interval, 12);
      expect(events.last.interval, 420);
    });

    test('dedup treats the two cases as one device', () async {
      final events = <String>[];
      platform.onConnectionParametersChange = (u) => events.add(u.deviceId);
      const lower = 'aa:bb:cc:dd:ee:01';
      const upper = 'AA:BB:CC:DD:EE:01';
      BleConnectionParametersChange params(String id) => BleConnectionParametersChange(
            deviceId: id,
            interval: 12,
            latency: 0,
            supervisionTimeout: 500,
            status: 0,
          );

      platform.updateConnectionParameters(params(lower)); // first -> emits
      platform.updateConnectionParameters(params(upper)); // identical params, other case -> deduped

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(events, [lower]);
    });
  });
}

BleConnectionParametersChange _update({required int interval}) {
  return BleConnectionParametersChange(
    deviceId: 'aa:bb:cc:dd:ee:ff',
    interval: interval,
    latency: 0,
    supervisionTimeout: 500,
    status: 0,
  );
}
