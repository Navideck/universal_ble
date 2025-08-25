import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/src/utils/universal_ble_filter_util.dart';
import 'package:universal_ble/universal_ble.dart';

void main() {
  final universalBleFilter = UniversalBleFilterUtil();
  var device1 = BleDevice(
    deviceId: '1',
    name: '1_device',
    services: ['20a1'],
    manufacturerDataList: [
      ManufacturerData(0x01, Uint8List.fromList([1, 2, 3])),
    ],
  );
  var device2 = BleDevice(
    deviceId: '2',
    name: '2_device',
    services: ['20a2'],
    manufacturerDataList: [
      ManufacturerData(0x02, Uint8List.fromList([1, 2, 3]))
    ],
  );
  var device3 = BleDevice(
    deviceId: '3',
    name: '3_device',
    services: ['20a3'],
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
        universalBleFilter.nameMatches(scanFilter, device1),
        isTrue,
      );
      expect(
        universalBleFilter.nameMatches(scanFilter, device2),
        isTrue,
      );
      expect(
        universalBleFilter.nameMatches(scanFilter, device3),
        isFalse,
      );
    });

    test('Test isServicesMatchingFilters', () {
      var scanFilter = ScanFilter(
        withServices: ['20a1', '20a6', '20a3'],
      );
      expect(
        universalBleFilter.servicesMatch(scanFilter, device1),
        isTrue,
      );
      expect(
        universalBleFilter.servicesMatch(scanFilter, device2),
        isFalse,
      );
      expect(
        universalBleFilter.nameMatches(scanFilter, device3),
        isTrue,
      );
    });

    test('Test isManufacturerDataMatchingFilters', () {
      var scanFilter = ScanFilter(withManufacturerData: [
        ManufacturerDataFilter(
          companyIdentifier: 0x01,
          payloadPrefix: Uint8List.fromList([1, 2]),
        ),
        ManufacturerDataFilter(
          companyIdentifier: 0x02,
        ),
        ManufacturerDataFilter(
          companyIdentifier: 0x03,
          payloadPrefix: Uint8List.fromList([3, 4]),
        )
      ]);
      expect(
        universalBleFilter.manufacturerDataMatches(
          scanFilter.withManufacturerData,
          device1,
        ),
        isTrue,
      );
      expect(
        universalBleFilter.manufacturerDataMatches(
          scanFilter.withManufacturerData,
          device2,
        ),
        isTrue,
      );
      expect(
        universalBleFilter.manufacturerDataMatches(
          scanFilter.withManufacturerData,
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
        withServices: ['20a3'],
        withManufacturerData: [
          ManufacturerDataFilter(
            companyIdentifier: 0x02,
          )
        ],
      );
      expect(
        universalBleFilter.matchedScanFilter(device1),
        isTrue,
      );
      expect(
        universalBleFilter.matchedScanFilter(device2),
        isTrue,
      );
      expect(
        universalBleFilter.matchedScanFilter(device3),
        isTrue,
      );
    });
    test('Test filterDevice: Filter for one', () {
      universalBleFilter.scanFilter = ScanFilter(
        withNamePrefix: ['1'],
      );
      expect(
        universalBleFilter.matchedScanFilter(device1),
        isTrue,
      );
      expect(
        universalBleFilter.matchedScanFilter(device2),
        isFalse,
      );
      expect(
        universalBleFilter.matchedScanFilter(device3),
        isFalse,
      );
    });
    test('Test filterDevice: Filter for two', () {
      universalBleFilter.scanFilter = ScanFilter(
        withNamePrefix: ['1', '2'],
      );
      expect(
        universalBleFilter.matchedScanFilter(device1),
        isTrue,
      );
      expect(
        universalBleFilter.matchedScanFilter(device2),
        isTrue,
      );
      expect(
        universalBleFilter.matchedScanFilter(device3),
        isFalse,
      );
    });
    test('Test filterDevice: Empty Filter', () {
      universalBleFilter.scanFilter = ScanFilter();
      expect(
        universalBleFilter.matchedScanFilter(device1),
        isTrue,
      );
      expect(
        universalBleFilter.matchedScanFilter(device2),
        isTrue,
      );
      expect(
        universalBleFilter.matchedScanFilter(device3),
        isTrue,
      );
    });
    test('Test filterDevice: Null Filter', () {
      universalBleFilter.scanFilter = ScanFilter();
      expect(
        universalBleFilter.matchedScanFilter(device1),
        isTrue,
      );
      expect(
        universalBleFilter.matchedScanFilter(device2),
        isTrue,
      );
      expect(
        universalBleFilter.matchedScanFilter(device3),
        isTrue,
      );
    });
  });

  group("Test Exclusion Filter", () {
    test('Test exclusionFilter: Have filter for 1', () {
      universalBleFilter.scanFilter = ScanFilter(exclusionFilters: [
        ExclusionFilter(
          namePrefix: '1',
          services: ['20a1'],
          manufacturerDataFilter: [
            ManufacturerDataFilter(
              companyIdentifier: 0x01,
            )
          ],
        )
      ]);
      expect(
        universalBleFilter.matchesExclusionFilter(device1),
        isTrue,
      );
      expect(
        universalBleFilter.matchesExclusionFilter(device2),
        isFalse,
      );
      expect(
        universalBleFilter.matchesExclusionFilter(device3),
        isFalse,
      );
    });

    test('Test exclusionFilter: Filter for two', () {
      universalBleFilter.scanFilter = ScanFilter(exclusionFilters: [
        ExclusionFilter(
          namePrefix: '1',
          services: ['20a1'],
          manufacturerDataFilter: [
            ManufacturerDataFilter(
              companyIdentifier: 0x01,
            )
          ],
        ),
        ExclusionFilter(
          namePrefix: '2',
          services: ['20a2'],
          manufacturerDataFilter: [
            ManufacturerDataFilter(
              companyIdentifier: 0x02,
            )
          ],
        ),
      ]);
      expect(
        universalBleFilter.matchesExclusionFilter(device1),
        isTrue,
      );
      expect(
        universalBleFilter.matchesExclusionFilter(device2),
        isTrue,
      );
      expect(
        universalBleFilter.matchesExclusionFilter(device3),
        isFalse,
      );
    });

    test('Test exclusionFilter: Invalid filter for last', () {
      universalBleFilter.scanFilter = ScanFilter(exclusionFilters: [
        ExclusionFilter(
          namePrefix: '3',
          services: ['20a2'],
          manufacturerDataFilter: [
            ManufacturerDataFilter(
              companyIdentifier: 0x01,
            )
          ],
        ),
      ]);
      expect(
        universalBleFilter.matchesExclusionFilter(device1),
        isFalse,
      );
      expect(
        universalBleFilter.matchesExclusionFilter(device2),
        isFalse,
      );
      expect(
        universalBleFilter.matchesExclusionFilter(device3),
        isFalse,
      );
    });

    test('Test exclusionFilter: Empty Filter', () {
      universalBleFilter.scanFilter = ScanFilter();
      expect(
        universalBleFilter.matchesExclusionFilter(device1),
        isFalse,
      );
    });
  });
}
