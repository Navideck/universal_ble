import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/src/universal_ble_stream.dart';

void main() {
  group("Test UniversalBleStreamController", () {
    test('Auto Dispose Stream', () {
      var streamController = UniversalBleStreamController<int>();
      expect(true, streamController.isClosed);

      // Stream should auto initialize on first subscription
      var subscription = streamController.stream.listen((data) {});
      expect(false, streamController.isClosed);

      streamController.add(1);

      // Should auto close on cancelling last subscription
      subscription.cancel();
      expect(true, streamController.isClosed);
    });

    test('Get InitialEvent on listen', () async {
      var streamController = UniversalBleStreamController<int>(
        initialEvent: () async => 1,
      );
      expect(true, streamController.isClosed);

      var firstValue = await streamController.stream.first;
      expect(true, streamController.isClosed);
      expect(1, firstValue);
    });
  });
}
