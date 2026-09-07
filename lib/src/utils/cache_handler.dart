import 'package:universal_ble/src/models/model_exports.dart';

/// Manages an in-memory cache for Bluetooth devices
class CacheHandler {
  static CacheHandler? _instance;
  static CacheHandler get instance => _instance ??= CacheHandler._();
  CacheHandler._();

  /// Internal cache to store discovered services for each device.
  final Map<String, List<BleService>> _servicesCache = {};

  // A device id is a case-insensitive identifier reported in different cases by different platforms (Android
  // upper-cases MACs, Windows lower-cases them). Key the cache by a canonical lower-case id so services saved
  // when subscribing with one case are still found/cleared when the platform reports another (e.g. on the
  // disconnect cleanup) — otherwise stale services linger and a reconnect reuses them.
  static String _key(String deviceId) => deviceId.toLowerCase();

  /// Saves the discovered Bluetooth services for a specific device in the cache.
  void saveServices(String deviceId, List<BleService>? services) {
    if (services == null) {
      _servicesCache.remove(_key(deviceId));
    } else {
      _servicesCache[_key(deviceId)] = services;
    }
  }

  /// Retrieves the cached Bluetooth services for a specific device.
  List<BleService>? getServices(String deviceId) => _servicesCache[_key(deviceId)];

  /// Internal cache to store subscribed characteristic UUIDs for each device.
  final Map<String, Set<String>> _subscriptionsCache = {};

  /// Updates the subscription state of a characteristic for a specific device.
  void updateSubscription(
    String deviceId,
    String characteristicId,
    bool isSubscribed,
  ) {
    final key = _key(deviceId);
    final normalizedCharId = BleUuidParser.string(characteristicId);
    if (isSubscribed) {
      (_subscriptionsCache[key] ??= {}).add(normalizedCharId);
    } else {
      _subscriptionsCache[key]?.remove(normalizedCharId);
      if (_subscriptionsCache[key]?.isEmpty ?? false) {
        _subscriptionsCache.remove(key);
      }
    }
  }

  /// Checks if a characteristic is subscribed to on a specific device.
  bool isSubscribed(String deviceId, String characteristicId) {
    try {
      final normalizedCharId = BleUuidParser.string(characteristicId);
      return _subscriptionsCache[_key(deviceId)]?.contains(normalizedCharId) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Retrieves the list of subscribed characteristic UUIDs for a specific device.
  List<String> getSubscribedCharacteristics(String deviceId) =>
      _subscriptionsCache[_key(deviceId)]?.toList() ?? [];

  /// Resets the cache for a specific device, removing all stored services and subscriptions.
  void resetDeviceCache(String deviceId) {
    _servicesCache.remove(_key(deviceId));
    _subscriptionsCache.remove(_key(deviceId));
  }
}
