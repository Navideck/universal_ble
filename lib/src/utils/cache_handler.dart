import 'package:universal_ble/src/models/model_exports.dart';

/// Manage InMemory Cache
class CacheHandler {
  static CacheHandler? _instance;
  static CacheHandler get instance => _instance ??= CacheHandler._();
  CacheHandler._();

  final Map<String, List<BleService>> _servicesCache = {};

  void saveServices(String deviceId, List<BleService>? services) {
    if (services == null) {
      _servicesCache.remove(deviceId);
    } else {
      _servicesCache[deviceId] = services;
    }
  }

  List<BleService>? getServices(String deviceId) => _servicesCache[deviceId];

  void resetDeviceCache(String deviceId) {
    _servicesCache.remove(deviceId);
  }
}
