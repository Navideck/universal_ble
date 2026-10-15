import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/src/utils/universal_ble_filter_util.dart';
import 'package:universal_ble/universal_ble.dart';

void main() {
  const full = '0000180d-0000-1000-8000-00805f9b34fb';

  BleDevice deviceWith(List<String> services) =>
      BleDevice(deviceId: '1', name: 'device', services: services);

  group('BleDevice.services normalization', () {
    test('expands a short UUID', () {
      expect(deviceWith(['180d']).services, [full]);
    });

    test('accepts the 0x-prefixed form', () {
      expect(deviceWith(['0x180d']).services, [full]);
    });

    test('lower-cases and keeps the full form', () {
      expect(
        deviceWith(['0000180D-0000-1000-8000-00805F9B34FB']).services,
        [full],
      );
    });

    test('keeps already normalised UUIDs unchanged', () {
      expect(deviceWith([full]).services, [full]);
    });

    test('expands a 32-bit UUID', () {
      expect(
        deviceWith(['0000180d']).services,
        ['0000180d-0000-1000-8000-00805f9b34fb'],
      );
    });

    test('normalises every entry of a list', () {
      expect(
        deviceWith(['180d', '181a']).services,
        const [
          full,
          '0000181a-0000-1000-8000-00805f9b34fb',
        ],
      );
    });

    test('keeps entries that are not UUIDs verbatim', () {
      expect(deviceWith(['not-a-uuid']).services, ['not-a-uuid']);
    });

    test('leaves an empty list empty', () {
      expect(deviceWith(const []).services, isEmpty);
    });

    test('survives copyWith', () {
      expect(
        deviceWith(['180d']).copyWith(deviceId: '2').services,
        [full],
      );
    });

    test('normalises serviceData keys the same way', () {
      final device = BleDevice(
        deviceId: '1',
        name: 'device',
        serviceData: {'181a': Uint8List.fromList([1])},
      );

      expect(device.serviceData.keys, ['0000181a-0000-1000-8000-00805f9b34fb']);
    });
  });

  group('filter matching across UUID forms', () {
    final filterUtil = UniversalBleFilterUtil();

    test('a short advertised service matches a full filter', () {
      filterUtil.scanFilter = ScanFilter(withServices: [full]);
      expect(filterUtil.matchedScanFilter(deviceWith(['180d'])), isTrue);
    });

    test('a full advertised service matches a short filter', () {
      filterUtil.scanFilter = ScanFilter(withServices: ['180d']);
      expect(filterUtil.matchedScanFilter(deviceWith([full])), isTrue);
    });

    test('a malformed advertised service does not throw', () {
      filterUtil.scanFilter = ScanFilter(withServices: [full]);
      expect(filterUtil.matchedScanFilter(deviceWith(['not-a-uuid'])), isFalse);
    });
  });
}
