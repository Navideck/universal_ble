import 'dart:async';

import 'package:universal_ble/src/models/ble_central.dart';
import 'package:universal_ble/src/models/ble_peripheral_event.dart';
import 'package:universal_ble/src/models/ble_uuid_parser.dart';

/// Tracks active BLE central devices subscribed to characteristics in peripheral mode.
class BleCentralTracker {
  final Map<String, BleCentral> _subscribedCentrals = <String, BleCentral>{};
  final Map<String, Set<String>> _serviceCharacteristics =
      <String, Set<String>>{};
  final StreamController<List<BleCentral>> _controller =
      StreamController<List<BleCentral>>.broadcast();

  StreamSubscription<BlePeripheralCharacteristicSubscriptionChanged>?
      _subscriptionSub;
  StreamSubscription<BlePeripheralConnectionStateChanged>? _connectionSub;

  static String _key(String deviceId) => deviceId.toLowerCase();

  /// Returns an unmodifiable list of currently subscribed centrals.
  List<BleCentral> get subscribedCentrals =>
      List<BleCentral>.unmodifiable(_subscribedCentrals.values);

  /// Registers the characteristics associated with a service.
  void registerService(String serviceId, Iterable<String> characteristicIds) {
    final sId = BleUuidParser.string(serviceId);
    _serviceCharacteristics[sId] =
        characteristicIds.map(BleUuidParser.string).toSet();
  }

  /// Handles removal of a service, pruning subscriptions for any characteristic
  /// belonging to the removed service.
  void removeService(String serviceId) {
    final sId = BleUuidParser.string(serviceId);
    final charsToRemove = _serviceCharacteristics.remove(sId);
    if (charsToRemove == null || charsToRemove.isEmpty) {
      return;
    }

    bool changed = false;
    final keys = _subscribedCentrals.keys.toList();
    for (final key in keys) {
      final central = _subscribedCentrals[key]!;
      final remainingChars = central.subscribedCharacteristics
          .where((char) => !charsToRemove.contains(char))
          .toSet();
      if (remainingChars.length != central.subscribedCharacteristics.length) {
        changed = true;
        if (remainingChars.isEmpty) {
          _subscribedCentrals.remove(key);
        } else {
          _subscribedCentrals[key] = central.copyWith(
            subscribedCharacteristics: remainingChars,
          );
        }
      }
    }
    if (changed) {
      _emit();
    }
  }

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

  /// Clears all tracked centrals and registered services, and emits an empty list if any were present.
  void clear() {
    _serviceCharacteristics.clear();
    if (_subscribedCentrals.isNotEmpty) {
      _subscribedCentrals.clear();
      _emit();
    }
  }

  /// Cancels active stream subscriptions and clears tracked centrals and services.
  void reset() {
    _subscriptionSub?.cancel();
    _subscriptionSub = null;
    _connectionSub?.cancel();
    _connectionSub = null;
    clear();
  }

  /// Broadcast stream that emits the current list of subscribed centrals upon listening
  /// and any subsequent updates.
  Stream<List<BleCentral>> get stream => Stream<List<BleCentral>>.multi(
        (multiController) {
          multiController.add(subscribedCentrals);
          final sub = _controller.stream.listen(
            multiController.add,
            onError: multiController.addError,
            onDone: multiController.close,
          );
          multiController.onCancel = () => sub.cancel();
        },
        isBroadcast: true,
      );

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
    _serviceCharacteristics.clear();
    _subscribedCentrals.clear();
  }
}
