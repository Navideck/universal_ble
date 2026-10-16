// Drives the Dart filter util from the shared conformance fixture
// (test/fixtures/scan_filter_cases.tsv), so its semantics stay identical to the
// Kotlin, Swift and C++ implementations.
//
// Skipped on the web test run: the fixture is read from disk.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/src/utils/universal_ble_filter_util.dart';
import 'package:universal_ble/universal_ble.dart';

const _fixturePath = 'test/fixtures/scan_filter_cases.tsv';

final _filterUtil = UniversalBleFilterUtil();

/// The fixture is language-neutral, so its UUIDs are written the way the
/// platforms receive them (full 128-bit, lowercase). Short/`0x` forms are a
/// Dart-layer convenience covered by `test/scan_filter_test.dart`.
List<String> _values(String column) =>
    column.isEmpty ? const [] : column.split(';');

void main() {
  final file = File(_fixturePath);
  if (!file.existsSync()) {
    throw StateError(
      'Fixture not found at $_fixturePath (run tests from the package root)',
    );
  }

  final rows = file
      .readAsLinesSync()
      .where((line) => line.isNotEmpty && !line.startsWith('#'))
      .toList();
  rows.removeAt(0); // header

  for (final row in rows) {
    final columns = row.split('|');
    if (columns.length != 10) {
      throw StateError('Fixture row "$row" must have 10 columns');
    }

    final id = columns[0];
    final expected = columns[9] == '1';

    final filter = ScanFilter(
      withServices: _values(columns[1]),
      withServiceData: _values(columns[2]),
      withNamePrefix: _values(columns[3]),
      withManufacturerData: _values(columns[4])
          .map((id) => ManufacturerDataFilter(companyIdentifier: int.parse(id)))
          .toList(),
    );
    final device = BleDevice(
      deviceId: id,
      name: columns[5].isEmpty ? null : columns[5],
      services: _values(columns[6]),
      serviceData: {
        for (final uuid in _values(columns[7])) uuid: Uint8List.fromList([0]),
      },
      manufacturerDataList: _values(columns[8])
          .map((id) => ManufacturerData(int.parse(id), Uint8List(0)))
          .toList(),
    );

    test('fixture: $id', () {
      _filterUtil.scanFilter = filter;
      expect(_filterUtil.matchedScanFilter(device), expected);
    });
  }
}
