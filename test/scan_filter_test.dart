import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/src/utils/universal_ble_filter_util.dart';
import 'package:universal_ble/universal_ble.dart';

void main() {
  // A fresh util per test: the filter is mutable state, so sharing one instance
  // makes a test's outcome depend on the tests before it.
  late UniversalBleFilterUtil universalBleFilter;

  setUp(() {
    universalBleFilter = UniversalBleFilterUtil();
  });

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
      // A services-only filter constrains nothing in the name dimension.
      expect(
        universalBleFilter.nameMatches(scanFilter, device3),
        isFalse,
      );
      expect(
        universalBleFilter.nameMatches(
            ScanFilter(withNamePrefix: ['3']), device3),
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

    test('Test connectableOnly filter', () {
      final connectableDevice = BleDevice(
        deviceId: 'c1',
        name: 'connectable',
        connectable: true,
      );
      final nonConnectableDevice = BleDevice(
        deviceId: 'c2',
        name: 'beacon',
        connectable: false,
      );
      final unknownDevice = BleDevice(
        deviceId: 'c3',
        name: 'unknown',
        connectable: null,
      );

      // When connectableOnly is true, non-connectable is rejected
      universalBleFilter.scanFilter = ScanFilter(connectableOnly: true);
      expect(universalBleFilter.matchedScanFilter(connectableDevice), isTrue);
      expect(
          universalBleFilter.matchedScanFilter(nonConnectableDevice), isFalse);
      expect(universalBleFilter.matchedScanFilter(unknownDevice), isTrue);
      expect(universalBleFilter.matchesConnectableFilter(connectableDevice),
          isTrue);
      expect(universalBleFilter.matchesConnectableFilter(nonConnectableDevice),
          isFalse);
      expect(
          universalBleFilter.matchesConnectableFilter(unknownDevice), isTrue);

      // When connectableOnly is null or false, non-connectable is allowed
      universalBleFilter.scanFilter = ScanFilter(connectableOnly: null);
      expect(universalBleFilter.matchedScanFilter(connectableDevice), isTrue);
      expect(
          universalBleFilter.matchedScanFilter(nonConnectableDevice), isTrue);
      expect(universalBleFilter.matchedScanFilter(unknownDevice), isTrue);
      expect(universalBleFilter.matchesConnectableFilter(nonConnectableDevice),
          isTrue);

      universalBleFilter.scanFilter = ScanFilter(connectableOnly: false);
      expect(universalBleFilter.matchedScanFilter(connectableDevice), isTrue);
      expect(
          universalBleFilter.matchedScanFilter(nonConnectableDevice), isTrue);
      expect(universalBleFilter.matchedScanFilter(unknownDevice), isTrue);
      expect(universalBleFilter.matchesConnectableFilter(nonConnectableDevice),
          isTrue);
    });
  });

  group("Test Service Data Filter", () {
    // A beacon that carries 0x181A only in its advertising Service Data, without
    // listing it among its advertised services (#57).
    final serviceDataBeacon = BleDevice(
      deviceId: 'sd1',
      name: 'ATC_DD7A81',
      services: [],
      serviceData: {
        '181a': Uint8List.fromList([0x81, 0x7a, 0xdd]),
      },
    );
    // Advertises the service UUID the old way, and carries full-form service
    // data for another UUID.
    final advertisedDevice = BleDevice(
      deviceId: 'sd2',
      name: 'other',
      services: ['20a2'],
      serviceData: {
        '0000feaa-0000-1000-8000-00805f9b34fb': Uint8List.fromList([1]),
      },
    );
    // Neither advertised services nor service data.
    final emptyDevice = BleDevice(
      deviceId: 'sd3',
      name: 'empty',
      services: [],
      serviceData: {},
    );

    test('Test serviceDataMatch: short, case-insensitive and full form', () {
      for (final filterValue in [
        '181a',
        '181A',
        '0x181a',
        '0000181a-0000-1000-8000-00805f9b34fb',
        '0000181A-0000-1000-8000-00805F9B34FB',
      ]) {
        expect(
          universalBleFilter.serviceDataMatch(
            ScanFilter(withServiceData: [filterValue]),
            serviceDataBeacon,
          ),
          isTrue,
          reason: '$filterValue should match the advertised Service Data UUID',
        );
      }
    });

    test('Test serviceDataMatch: non-matching and empty service data', () {
      final scanFilter = ScanFilter(withServiceData: ['2a6e']);
      expect(universalBleFilter.serviceDataMatch(scanFilter, advertisedDevice),
          isFalse);
      expect(universalBleFilter.serviceDataMatch(scanFilter, emptyDevice),
          isFalse);
      expect(universalBleFilter.serviceDataMatch(scanFilter, serviceDataBeacon),
          isFalse);
    });

    test('Test serviceDataMatch: unset service data filter does not narrow',
        () {
      expect(
        universalBleFilter.serviceDataMatch(ScanFilter(), serviceDataBeacon),
        isFalse,
      );
    });

    test('Test matchedScanFilter: Service Data only device is discovered', () {
      // withServices alone does not see the beacon...
      universalBleFilter.scanFilter = ScanFilter(withServices: ['181a']);
      expect(universalBleFilter.matchedScanFilter(serviceDataBeacon), isFalse);

      // ...but withServiceData does.
      universalBleFilter.scanFilter = ScanFilter(withServiceData: ['181a']);
      expect(universalBleFilter.matchedScanFilter(serviceDataBeacon), isTrue);
      expect(universalBleFilter.matchedScanFilter(advertisedDevice), isFalse);
      expect(universalBleFilter.matchedScanFilter(emptyDevice), isFalse);
    });

    test('Test matchedScanFilter: conditions stay in OR relation', () {
      universalBleFilter.scanFilter = ScanFilter(
        withServices: ['20a2'],
        withServiceData: ['181a'],
      );
      expect(universalBleFilter.matchedScanFilter(serviceDataBeacon), isTrue);
      expect(universalBleFilter.matchedScanFilter(advertisedDevice), isTrue);
      expect(universalBleFilter.matchedScanFilter(emptyDevice), isFalse);
    });

    test('Test matchedScanFilter: unset withServiceData keeps old behaviour',
        () {
      universalBleFilter.scanFilter = ScanFilter(withServices: ['181a']);
      expect(universalBleFilter.matchedScanFilter(serviceDataBeacon), isFalse);

      universalBleFilter.scanFilter = ScanFilter();
      expect(universalBleFilter.matchedScanFilter(serviceDataBeacon), isTrue);
    });

    test('Test matchedScanFilter: malformed device keys do not throw', () {
      final malformed = BleDevice(
        deviceId: 'sd4',
        name: 'malformed',
        serviceData: {
          'not-a-uuid': Uint8List.fromList([1])
        },
      );
      universalBleFilter.scanFilter = ScanFilter(withServiceData: ['181a']);
      expect(universalBleFilter.matchedScanFilter(malformed), isFalse);
    });
  });
}
