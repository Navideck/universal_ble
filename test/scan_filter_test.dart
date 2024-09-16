import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/src/universal_ble_filter_util.dart';
import 'package:universal_ble/universal_ble.dart';

void main() {
  final universalBleFilter = UniversalBleFilterUtil();
  var device1 = BleDevice(
    deviceId: '1',
    name: '1_device',
    services: ['1_ser'],
    manufacturerDataList: [
      ManufacturerData(0x01, Uint8List.fromList([1, 2, 3])),
    ],
  );
  var device2 = BleDevice(
    deviceId: '2',
    name: '2_device',
    services: ['2_ser'],
    manufacturerDataList: [
      ManufacturerData(0x02, Uint8List.fromList([1, 2, 3]))
    ],
  );
  var device3 = BleDevice(
    deviceId: '3',
    name: '3_device',
    services: ['3_ser'],
    manufacturerDataList: [
      ManufacturerData(0x03, Uint8List.fromList([1, 2, 3]))
    ],
  );

  group("Test Individual Filter", () {
    test('Test isNameMatchingFilters', () {
      var scanFilter = ScanFilter(
        withNamePrefix: ['1', '2'],
      );
      expect(
        universalBleFilter.isNameMatchingFilters(scanFilter, device1),
        isTrue,
      );
      expect(
        universalBleFilter.isNameMatchingFilters(scanFilter, device2),
        isTrue,
      );
      expect(
        universalBleFilter.isNameMatchingFilters(scanFilter, device3),
        isFalse,
      );
    });

    test('Test isServicesMatchingFilters', () {
      var scanFilter = ScanFilter(
        withServices: ['1_ser', 'random', '3_ser'],
      );
      expect(
        universalBleFilter.isServicesMatchingFilters(scanFilter, device1),
        isTrue,
      );
      expect(
        universalBleFilter.isServicesMatchingFilters(scanFilter, device2),
        isFalse,
      );
      expect(
        universalBleFilter.isNameMatchingFilters(scanFilter, device3),
        isTrue,
      );
    });

    test('Test isManufacturerDataMatchingFilters', () {
      var scanFilter = ScanFilter(withManufacturerData: [
        ManufacturerDataFilter(
          companyIdentifier: 0x01,
          payload: Uint8List.fromList([1, 2]),
        ),
        ManufacturerDataFilter(
          companyIdentifier: 0x02,
        ),
        ManufacturerDataFilter(
          companyIdentifier: 0x03,
          payload: Uint8List.fromList([3, 4]),
        )
      ]);
      expect(
        universalBleFilter.isManufacturerDataMatchingFilters(
          scanFilter,
          device1,
        ),
        isTrue,
      );
      expect(
        universalBleFilter.isManufacturerDataMatchingFilters(
          scanFilter,
          device2,
        ),
        isTrue,
      );
      expect(
        universalBleFilter.isManufacturerDataMatchingFilters(
          scanFilter,
          device3,
        ),
        isFalse,
      );
    });
  });

  group("Test Scan Filter", () {
    test('Test filterDevice: Have filter for all', () {
      universalBleFilter.scanFilter = ScanFilter(
        withNamePrefix: ['1'],
        withServices: ['3_ser'],
        withManufacturerData: [
          ManufacturerDataFilter(
            companyIdentifier: 0x02,
          )
        ],
      );
      expect(
        universalBleFilter.filterDevice(device1),
        isTrue,
      );
      expect(
        universalBleFilter.filterDevice(device2),
        isTrue,
      );
      expect(
        universalBleFilter.filterDevice(device3),
        isTrue,
      );
    });
    test('Test filterDevice: Filter for one', () {
      universalBleFilter.scanFilter = ScanFilter(
        withNamePrefix: ['1'],
      );
      expect(
        universalBleFilter.filterDevice(device1),
        isTrue,
      );
      expect(
        universalBleFilter.filterDevice(device2),
        isFalse,
      );
      expect(
        universalBleFilter.filterDevice(device3),
        isFalse,
      );
    });
    test('Test filterDevice: Filter for two', () {
      universalBleFilter.scanFilter = ScanFilter(
        withNamePrefix: ['1', '2'],
      );
      expect(
        universalBleFilter.filterDevice(device1),
        isTrue,
      );
      expect(
        universalBleFilter.filterDevice(device2),
        isTrue,
      );
      expect(
        universalBleFilter.filterDevice(device3),
        isFalse,
      );
    });
    test('Test filterDevice: Empty Filter', () {
      universalBleFilter.scanFilter = ScanFilter();
      expect(
        universalBleFilter.filterDevice(device1),
        isTrue,
      );
      expect(
        universalBleFilter.filterDevice(device2),
        isTrue,
      );
      expect(
        universalBleFilter.filterDevice(device3),
        isTrue,
      );
    });
    test('Test filterDevice: Null Filter', () {
      universalBleFilter.scanFilter = ScanFilter();
      expect(
        universalBleFilter.filterDevice(device1),
        isTrue,
      );
      expect(
        universalBleFilter.filterDevice(device2),
        isTrue,
      );
      expect(
        universalBleFilter.filterDevice(device3),
        isTrue,
      );
    });
  });
}
