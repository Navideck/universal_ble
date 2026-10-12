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

  test('exposes connectable property', () {
    final connectableDevice = BleDevice(
      deviceId: 'device-1',
      name: 'Connectable Device',
      connectable: true,
    );
    expect(connectableDevice.connectable, isTrue);

    final nonConnectableDevice = BleDevice(
      deviceId: 'device-2',
      name: 'Beacon',
      connectable: false,
    );
    expect(nonConnectableDevice.connectable, isFalse);

    final unknownDevice = BleDevice(
      deviceId: 'device-3',
      name: null,
    );
    expect(unknownDevice.connectable, isNull);
  });
}

