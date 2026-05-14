import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/src/universal_ble.g.dart';

void main() {
  group('AndroidOptions', () {
    test('stores the new ScanSettings knobs', () {
      final options = AndroidOptions(
        scanMode: AndroidScanMode.lowLatency,
        reportDelayMillis: 0,
        callbackType: AndroidScanCallbackType.allMatches,
        matchMode: AndroidScanMatchMode.aggressive,
        numOfMatches: AndroidScanNumOfMatches.max,
      );

      expect(options.callbackType, AndroidScanCallbackType.allMatches);
      expect(options.matchMode, AndroidScanMatchMode.aggressive);
      expect(options.numOfMatches, AndroidScanNumOfMatches.max);
    });

    test('round-trips the new fields through the pigeon codec', () {
      final original = AndroidOptions(
        requestLocationPermission: true,
        scanMode: AndroidScanMode.lowLatency,
        reportDelayMillis: 0,
        callbackType: AndroidScanCallbackType.firstMatch,
        matchMode: AndroidScanMatchMode.sticky,
        numOfMatches: AndroidScanNumOfMatches.few,
      );

      final decoded = AndroidOptions.decode(original.encode());

      expect(decoded, equals(original));
      expect(decoded.callbackType, AndroidScanCallbackType.firstMatch);
      expect(decoded.matchMode, AndroidScanMatchMode.sticky);
      expect(decoded.numOfMatches, AndroidScanNumOfMatches.few);
    });

    test('leaves the new fields null by default', () {
      final options = AndroidOptions();

      expect(options.callbackType, isNull);
      expect(options.matchMode, isNull);
      expect(options.numOfMatches, isNull);
    });
  });
}
