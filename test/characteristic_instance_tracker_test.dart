import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/src/utils/ble_central_tracker.dart';
import 'package:universal_ble/universal_ble.dart';

void main() {
  test('unsubscribing one Report instance keeps the other subscription', () {
    final tracker = BleCentralTracker();
    addTearDown(tracker.dispose);
    void subscription(String instanceId, bool subscribed) {
      tracker.handleSubscriptionChange(
          BlePeripheralCharacteristicSubscriptionChanged(
        deviceId: 'aa:bb:cc:dd:ee:ff',
        characteristicId: '2a4d',
        instanceId: instanceId,
        isSubscribed: subscribed,
        name: null,
      ));
    }

    subscription('consumerInput', true);
    subscription('keyboardInput', true);
    subscription('consumerInput', false);
    expect(tracker.subscribedCentrals, hasLength(1));
    expect(tracker.subscribedCentrals.single.isSubscribedTo('2a4d'), isTrue);
    subscription(
        'consumerInput', false); // Repeated events must not remove keyboard.
    expect(tracker.subscribedCentrals, hasLength(1));
    subscription('keyboardInput', false);
    expect(tracker.subscribedCentrals, isEmpty);
  });
}
