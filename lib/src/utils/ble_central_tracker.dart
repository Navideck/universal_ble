import 'dart:async';

import 'package:universal_ble/src/models/ble_central.dart';
import 'package:universal_ble/src/models/ble_peripheral_event.dart';
import 'package:universal_ble/src/models/ble_uuid_parser.dart';
import 'package:universal_ble/src/utils/universal_ble_stream_controller.dart';

/// Tracks active BLE central devices subscribed to characteristics in peripheral mode.
class BleCentralTracker {
  final Map<String, BleCentral> _subscribedCentrals = <String, BleCentral>{};
  late final UniversalBleStreamController<List<BleCentral>> _controller =
      UniversalBleStreamController<List<BleCentral>>(
    initialEvent: () async => subscribedCentrals,
  );

  StreamSubscription<BlePeripheralCharacteristicSubscriptionChanged>?
      _subscriptionSub;
  StreamSubscription<BlePeripheralConnectionStateChanged>? _connectionSub;

  static String _key(String deviceId) => deviceId.toLowerCase();

  /// Returns an unmodifiable list of currently subscribed centrals.
  List<BleCentral> get subscribedCentrals =>
      List<BleCentral>.unmodifiable(_subscribedCentrals.values);

  /// Binds to peripheral event streams to track subscription and connection state changes.
  void bindStreams({
    required Stream<BlePeripheralCharacteristicSubscriptionChanged>
        characteristicSubscriptionStream,
    required Stream<BlePeripheralConnectionStateChanged> connectionStateStream,
  }) {
    _subscriptionSub?.cancel();
    _connectionSub?.cancel();

    _subscriptionSub =
        characteristicSubscriptionStream.listen(handleSubscriptionChange);
    _connectionSub = connectionStateStream.listen(handleConnectionChange);
  }

  /// Handles characteristic subscription events.
  void handleSubscriptionChange(
    BlePeripheralCharacteristicSubscriptionChanged event,
  ) {
    final key = _key(event.deviceId);
    final charId = BleUuidParser.string(event.characteristicId);

    if (event.isSubscribed) {
      final existing = _subscribedCentrals[key];
      final isAlreadySubscribed =
          existing != null && existing.subscribedCharacteristics.contains(charId);
      final hasSameName =
          existing != null && (event.name == null || event.name == existing.name);

      if (isAlreadySubscribed && hasSameName) {
        // No state change; suppress duplicate emission.
        return;
      }

      final chars = Set<String>.from(
        existing?.subscribedCharacteristics ?? const <String>{},
      )..add(charId);

      _subscribedCentrals[key] = BleCentral(
        id: existing?.id ?? event.deviceId,
        name: event.name ?? existing?.name,
        subscribedCharacteristics: chars,
      );
      _emit();
    } else {
      final existing = _subscribedCentrals[key];
      if (existing == null || !existing.subscribedCharacteristics.contains(charId)) {
        // Not tracked or characteristic wasn't subscribed; suppress duplicate emission.
        return;
      }

      final chars = Set<String>.from(existing.subscribedCharacteristics)
        ..remove(charId);
      if (chars.isEmpty) {
        _subscribedCentrals.remove(key);
      } else {
        _subscribedCentrals[key] = existing.copyWith(
          subscribedCharacteristics: chars,
          name: event.name ?? existing.name,
        );
      }
      _emit();
    }
  }

  /// Handles connection state change events.
  void handleConnectionChange(BlePeripheralConnectionStateChanged event) {
    if (!event.connected) {
      final key = _key(event.deviceId);
      if (_subscribedCentrals.remove(key) != null) {
        _emit();
      }
    }
  }

  /// Clears all tracked centrals and emits an empty list if any were present.
  void clear() {
    if (_subscribedCentrals.isNotEmpty) {
      _subscribedCentrals.clear();
      _emit();
    }
  }

  /// Cancels active stream subscriptions and clears tracked centrals.
  void reset() {
    _subscriptionSub?.cancel();
    _subscriptionSub = null;
    _connectionSub?.cancel();
    _connectionSub = null;
    clear();
  }

  /// Broadcast stream that emits the current list of subscribed centrals upon listening
  /// and any subsequent updates.
  Stream<List<BleCentral>> get stream => _controller.stream;

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(subscribedCentrals);
    }
  }

  void dispose() {
    _subscriptionSub?.cancel();
    _subscriptionSub = null;
    _connectionSub?.cancel();
    _connectionSub = null;
    _controller.close();
    _subscribedCentrals.clear();
  }
}
