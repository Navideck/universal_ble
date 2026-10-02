import 'package:universal_ble/src/models/model_exports.dart';

/// Manages an in-memory cache for Bluetooth devices.
///
/// Every entry is keyed by a CANONICAL device id: a device id is case-insensitive on platforms
/// that report addresses (Android upper-cases MACs, Windows lower-cases them), so services saved
/// when subscribing with one case must still be found and cleared when the platform reports
/// another (e.g. on the disconnect cleanup) — otherwise stale services linger and a reconnect
/// reuses them. Canonicalising is the caller's job, at the boundary where the platform's id kind
/// is known (`UniversalBle.canonicalDeviceId`), so ids that are NOT case-insensitive — Web's
/// opaque tokens — are never folded together here.
class CacheHandler {
  static CacheHandler? _instance;
  static CacheHandler get instance => _instance ??= CacheHandler._();
  CacheHandler._();

  /// Internal cache to store discovered services for each device.
  final Map<String, List<BleService>> _servicesCache = {};

  /// Saves the discovered Bluetooth services for a specific device in the cache.
  void saveServices(String deviceId, List<BleService>? services) {
    if (services == null) {
      _servicesCache.remove(deviceId);
    } else {
      _servicesCache[deviceId] = services;
    }
  }

  /// Retrieves the cached Bluetooth services for a specific device.
  List<BleService>? getServices(String deviceId) => _servicesCache[deviceId];

  /// Internal cache to store subscribed characteristic UUIDs for each device.
  final Map<String, Set<String>> _subscriptionsCache = {};

  /// Updates the subscription state of a characteristic for a specific device.
  void updateSubscription(
    String deviceId,
    String characteristicId,
    bool isSubscribed,
  ) {
    final normalizedCharId = BleUuidParser.string(characteristicId);
    if (isSubscribed) {
      (_subscriptionsCache[deviceId] ??= {}).add(normalizedCharId);
    } else {
      _subscriptionsCache[deviceId]?.remove(normalizedCharId);
      if (_subscriptionsCache[deviceId]?.isEmpty ?? false) {
        _subscriptionsCache.remove(deviceId);
      }
    }
  }

  /// Checks if a characteristic is subscribed to on a specific device.
  bool isSubscribed(String deviceId, String characteristicId) {
    try {
      final normalizedCharId = BleUuidParser.string(characteristicId);
      return _subscriptionsCache[deviceId]?.contains(normalizedCharId) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Retrieves the list of subscribed characteristic UUIDs for a specific device.
  List<String> getSubscribedCharacteristics(String deviceId) =>
      _subscriptionsCache[deviceId]?.toList() ?? [];

  /// Resets the cache for a specific device, removing all stored services and subscriptions.
  void resetDeviceCache(String deviceId) {
    _servicesCache.remove(deviceId);
    _subscriptionsCache.remove(deviceId);
  }
}
