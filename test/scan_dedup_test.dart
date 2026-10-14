import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:universal_ble/src/utils/scan_deduplicator.dart';

import 'universal_ble_test_mock.dart';

/// Minimal concrete platform that records every scan result the shared layer
/// forwards. All other operations stay unimplemented (we only exercise the
/// de-duplication path).
class _FakePlatform extends UniversalBlePlatformMock {
  final List<BleDevice> emitted = [];

  _FakePlatform() {
    onScanResultUpdate = emitted.add;
  }
}

BleDevice _device({
  String deviceId = 'AA:BB:CC:DD:EE:FF',
  String? name = 'device',
  int? rssi = -60,
  List<String> services = const [],
  List<ManufacturerData> manufacturerDataList = const [],
  Map<String, Uint8List> serviceData = const {},
  bool? connectable,
}) {
  return BleDevice(
    deviceId: deviceId,
    name: name,
    rssi: rssi,
    services: services,
    manufacturerDataList: manufacturerDataList,
    serviceData: serviceData,
    connectable: connectable,
  );
}

void main() {
  group('ScanDeduplicator', () {
    test('disabled by default: every result is emitted', () {
      final dedup = ScanDeduplicator();

      expect(dedup.shouldEmit(_device()), isTrue);
      expect(dedup.shouldEmit(_device()), isTrue);
      expect(dedup.shouldEmit(_device()), isTrue);
    });

    test('enabled: first sight emitted, identical repeats dropped', () {
      final dedup = ScanDeduplicator()..setEnabled(true);

      expect(dedup.shouldEmit(_device()), isTrue);
      expect(dedup.shouldEmit(_device()), isFalse);
      expect(dedup.shouldEmit(_device()), isFalse);
    });

    test('enabled: payload changes are still treated as duplicates', () {
      final dedup = ScanDeduplicator()..setEnabled(true);

      expect(dedup.shouldEmit(_device(name: 'device')), isTrue);
      expect(dedup.shouldEmit(_device(name: 'device-renamed')), isFalse);
      expect(dedup.shouldEmit(_device(services: ['180d'])), isFalse);
      expect(
        dedup.shouldEmit(_device(
          manufacturerDataList: [
            ManufacturerData(76, Uint8List.fromList([1, 2, 3])),
          ],
        )),
        isFalse,
      );
      expect(
        dedup.shouldEmit(
          _device(serviceData: {'180f': Uint8List.fromList([9])}),
        ),
        isFalse,
      );
      expect(dedup.shouldEmit(_device(connectable: true)), isFalse);
    });

    test('enabled: RSSI-only changes are dropped', () {
      final dedup = ScanDeduplicator()..setEnabled(true);

      expect(dedup.shouldEmit(_device(rssi: -60)), isTrue);
      expect(dedup.shouldEmit(_device(rssi: -55)), isFalse);
      expect(dedup.shouldEmit(_device(rssi: -75)), isFalse);
    });

    test('enabled: device id is matched case-insensitively', () {
      final dedup = ScanDeduplicator()..setEnabled(true);

      expect(dedup.shouldEmit(_device(deviceId: 'AA:BB:CC')), isTrue);
      expect(dedup.shouldEmit(_device(deviceId: 'aa:bb:cc')), isFalse);
    });

    test('reset forgets remembered results', () {
      final dedup = ScanDeduplicator()..setEnabled(true);

      expect(dedup.shouldEmit(_device()), isTrue);
      expect(dedup.shouldEmit(_device()), isFalse);

      dedup.reset();
      expect(dedup.shouldEmit(_device()), isTrue);
    });

    test('disabling emits everything again', () {
      final dedup = ScanDeduplicator()..setEnabled(true);

      expect(dedup.shouldEmit(_device()), isTrue);
      expect(dedup.shouldEmit(_device()), isFalse);

      dedup.setEnabled(false);
      expect(dedup.shouldEmit(_device()), isTrue);
    });
  });

  group('skipDuplicates wiring', () {
    test('disabled by default: every result is forwarded', () {
      final platform = _FakePlatform();
      expect(platform.skipDuplicatesEnabled, isFalse);

      platform.updateScanResult(_device());
      platform.updateScanResult(_device());
      platform.updateScanResult(_device());

      expect(platform.emitted.length, 3);
    });

    test('enabled: identical repeats are dropped until reset', () {
      final platform = _FakePlatform()
        ..setSkipDuplicates(true)
        ..resetScanDeduplication();

      platform.updateScanResult(_device());
      platform.updateScanResult(_device());
      expect(platform.emitted.length, 1);

      // As startScan does between sessions.
      platform.resetScanDeduplication();
      platform.updateScanResult(_device());
      expect(platform.emitted.length, 2);
    });

    test('stopping the scan forwards results again', () {
      final platform = _FakePlatform()
        ..setSkipDuplicates(true)
        ..resetScanDeduplication();

      platform.updateScanResult(_device());
      platform.updateScanResult(_device());
      expect(platform.emitted.length, 1);

      // As stopScan does.
      platform.setSkipDuplicates(false);
      platform.resetScanDeduplication();
      platform.updateScanResult(_device());
      expect(platform.emitted.length, 2);
    });

    test('scanStream is gated as well as the callback', () async {
      final platform = _FakePlatform()
        ..setSkipDuplicates(true)
        ..resetScanDeduplication();
      final received = <BleDevice>[];
      final subscription = platform.scanStream.listen(received.add);

      platform.updateScanResult(_device());
      platform.updateScanResult(_device());
      await Future<void>.delayed(Duration.zero);

      expect(received.length, 1);
      await subscription.cancel();
    });
  });
}
