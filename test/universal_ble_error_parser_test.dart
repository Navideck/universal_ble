import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/src/universal_ble.g.dart';
import 'package:universal_ble/src/utils/universal_ble_error_parser.dart';

void main() {
  group(UniversalBleErrorParser, () {
    group('getCode', () {
      test('classifies a Windows unreachable callback as connection failed',
          () {
        expect(
          UniversalBleErrorParser.getCode(
            'Failed to get services: Unreachable',
          ),
          UniversalBleErrorCode.connectionFailed,
        );
      });

      test('classifies a Windows access callback as unauthorized', () {
        expect(
          UniversalBleErrorParser.getCode(
            'Failed to get services: AccessDenied',
          ),
          UniversalBleErrorCode.bluetoothUnauthorized,
        );
      });

      test('classifies a missing Windows device as connection failed', () {
        expect(
          UniversalBleErrorParser.getCode('Failed to get device'),
          UniversalBleErrorCode.connectionFailed,
        );
      });

      test('classifies a Windows protocol callback as failed', () {
        expect(
          UniversalBleErrorParser.getCode(
            'Failed to get services: ProtocolError',
          ),
          UniversalBleErrorCode.failed,
        );
      });

      test('does not classify unrelated messages by substring', () {
        expect(
          UniversalBleErrorParser.getCode(
            'Request failed after the service became unreachable',
          ),
          UniversalBleErrorCode.unknownError,
        );
      });
    });
  });
}
