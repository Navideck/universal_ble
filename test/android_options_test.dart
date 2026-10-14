import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/src/universal_ble.g.dart';

void main() {
  group('AndroidOptions', () {
    test('stores the new ScanSettings knobs', () {
      final options = AndroidOptions(
        scanMode: AndroidScanMode.lowLatency,
        reportDelayMillis: 0,
        callbackType: [AndroidScanCallbackType.allMatches],
        matchMode: AndroidScanMatchMode.aggressive,
        numOfMatches: AndroidScanNumOfMatches.max,
        legacy: false,
      );

      expect(options.callbackType, [AndroidScanCallbackType.allMatches]);
      expect(options.matchMode, AndroidScanMatchMode.aggressive);
      expect(options.numOfMatches, AndroidScanNumOfMatches.max);
      expect(options.legacy, false);
    });

    test('round-trips a multi-value callbackType through the pigeon codec', () {
      final original = AndroidOptions(
        requestLocationPermission: true,
        scanMode: AndroidScanMode.lowLatency,
        reportDelayMillis: 0,
        callbackType: [
          AndroidScanCallbackType.firstMatch,
          AndroidScanCallbackType.matchLost,
        ],
        matchMode: AndroidScanMatchMode.sticky,
        numOfMatches: AndroidScanNumOfMatches.few,
        legacy: true,
      );

      final decoded = AndroidOptions.decode(original.encode());

      expect(decoded.callbackType, [
        AndroidScanCallbackType.firstMatch,
        AndroidScanCallbackType.matchLost,
      ]);
      expect(decoded.matchMode, AndroidScanMatchMode.sticky);
      expect(decoded.numOfMatches, AndroidScanNumOfMatches.few);
      expect(decoded.scanMode, AndroidScanMode.lowLatency);
      expect(decoded.reportDelayMillis, 0);
      expect(decoded.requestLocationPermission, true);
      expect(decoded.legacy, true);
    });

    test('leaves the new fields null by default', () {
      final options = AndroidOptions();

      expect(options.callbackType, isNull);
      expect(options.matchMode, isNull);
      expect(options.numOfMatches, isNull);
      expect(options.legacy, isNull);
    });
  });
}
