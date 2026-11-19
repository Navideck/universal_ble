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

  /// Device ids (canonical) for which [discoverServices] has completed at least
  /// once since the current connection. Unlike [_servicesCache] this is set by
  /// the public `UniversalBle.discoverServices`, not only by the `BleDevice`
  /// extension, so capabilities that depend on discovery (see
  /// `BleCapabilities.mtuRequiresServiceDiscovery`) can rely on it.
  final Set<String> _servicesDiscovered = {};

  /// Records that services have been discovered for [deviceId].
  void markServicesDiscovered(String deviceId) =>
      _servicesDiscovered.add(deviceId);

  /// Whether [discoverServices] has run for [deviceId] since it connected.
  bool hasDiscoveredServices(String deviceId) =>
      _servicesDiscovered.contains(deviceId);

  /// Internal cache of subscribed characteristics, grouped by service, for each device.
  ///
  /// Keyed deviceId -> serviceId -> characteristicId. A GATT database may expose the same
  /// characteristic UUID in several services (one Battery Service per battery), and each
  /// instance has its own CCC descriptor, so the service has to be part of the key: without it,
  /// unsubscribing one instance clears the state that describes another.
  final Map<String, Map<String, Set<String>>> _subscriptionsCache = {};

  /// Updates the subscription state of a characteristic instance for a specific device.
  void updateSubscription(
    String deviceId,
    String serviceId,
    String characteristicId,
    bool isSubscribed,
  ) {
    final normalizedServiceId = BleUuidParser.string(serviceId);
    final normalizedCharId = BleUuidParser.string(characteristicId);
    if (isSubscribed) {
      ((_subscriptionsCache[deviceId] ??= {})[normalizedServiceId] ??= {})
          .add(normalizedCharId);
      return;
    }
    final services = _subscriptionsCache[deviceId];
    final characteristics = services?[normalizedServiceId];
    if (services == null || characteristics == null) return;
    characteristics.remove(normalizedCharId);
    if (characteristics.isEmpty) services.remove(normalizedServiceId);
    if (services.isEmpty) _subscriptionsCache.remove(deviceId);
  }

  /// Checks if a characteristic is subscribed to on a specific device.
  ///
  /// Without [serviceId] any service that exposes this characteristic counts, which is the
  /// answer a caller that only knows the UUID gets. Pass [serviceId] to ask about one instance.
  bool isSubscribed(
    String deviceId,
    String characteristicId, {
    String? serviceId,
  }) {
    try {
      final normalizedCharId = BleUuidParser.string(characteristicId);
      final services = _subscriptionsCache[deviceId];
      if (services == null) return false;
      if (serviceId != null) {
        return services[BleUuidParser.string(serviceId)]
                ?.contains(normalizedCharId) ??
            false;
      }
      return services.values.any((e) => e.contains(normalizedCharId));
    } catch (_) {
      return false;
    }
  }

  /// Retrieves the subscribed characteristic UUIDs for a specific device.
  ///
  /// Each UUID is reported once even when several services expose it, unless [serviceId]
  /// narrows the answer to one service. The list is sorted, so the order does not depend on
  /// which service a characteristic was subscribed through first.
  List<String> getSubscribedCharacteristics(
    String deviceId, {
    String? serviceId,
  }) {
    final services = _subscriptionsCache[deviceId];
    if (services == null) return [];
    if (serviceId != null) {
      try {
        final characteristics = services[BleUuidParser.string(serviceId)];
        return characteristics == null
            ? []
            : (characteristics.toList()..sort());
      } catch (_) {
        return [];
      }
    }
    return {
      for (final characteristics in services.values) ...characteristics,
    }.toList()
      ..sort();
  }

  /// Resets the cache for a specific device, removing all stored services and subscriptions.
  void resetDeviceCache(String deviceId) {
    _servicesCache.remove(deviceId);
    _subscriptionsCache.remove(deviceId);
    _servicesDiscovered.remove(deviceId);
  }
}
