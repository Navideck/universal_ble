import 'package:universal_ble/src/models/model_exports.dart';

/// Manages an in-memory cache for Bluetooth devices
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

  /// Resets the cache for a specific device, removing all stored services.
  void resetDeviceCache(String deviceId) {
    _servicesCache.remove(deviceId);
  }
}
