// Drives the Dart ATT error mapping from the shared conformance fixture
// (test/fixtures/att_error_cases.tsv), so its semantics stay identical to the
// Android and Windows implementations.
//
// Skipped on the web test run: the fixture is read from disk.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/src/utils/universal_ble_error_parser.dart';

const _fixturePath = 'test/fixtures/att_error_cases.tsv';

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

  test('maps every shared ATT error code like the other platforms', () {
    expect(rows, isNotEmpty);

    for (final row in rows) {
      final columns = row.split('|');
      expect(
        columns.length,
        3,
        reason: 'Fixture row "$row" must have 3 columns',
      );

      final attCode = int.parse(columns[0].replaceFirst('0x', ''), radix: 16);
      final expected = int.parse(columns[1]);

      final code = UniversalBleErrorParser.getCode(attCode);
      expect(
        code.index,
        expected,
        reason: 'ATT ${columns[0]} (${columns[2]})',
      );
    }
  });
}
