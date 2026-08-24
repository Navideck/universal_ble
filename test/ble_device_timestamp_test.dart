import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';

void main() {
  test('exposes a microsecond scan timestamp without rounding', () {
    const timestampMicroseconds = 1787597612345678;
    final device = BleDevice(
      deviceId: 'device',
      name: null,
      timestamp: timestampMicroseconds ~/ 1000,
      timestampMicroseconds: timestampMicroseconds,
    );

    expect(
      device.timestampMicrosecondsDateTime?.microsecondsSinceEpoch,
      timestampMicroseconds,
    );
    expect(
      device.timestampDateTime?.microsecondsSinceEpoch,
      1787597612345000,
    );
  });
}
