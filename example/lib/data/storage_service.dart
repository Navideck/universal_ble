import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  StorageService._();
  static StorageService? _instance;
  static StorageService get instance => _instance ??= StorageService._();

  late SharedPreferencesWithCache _preferences;

  Future<void> init() async {
    _preferences = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
  }

  Future<void> setFavoriteServices(List<String> services) async {
    await _preferences.setStringList('favorite_services', services);
  }

  List<String> getFavoriteServices() =>
      _preferences.getStringList('favorite_services') ?? [];

  // Monitored devices for background scanning
  static const String _monitoredDevicesKey = 'monitored_devices';

  Future<void> setMonitoredDevices(List<String> deviceIds) async {
    await _preferences.setStringList(_monitoredDevicesKey, deviceIds);
  }

  List<String> getMonitoredDevices() =>
      _preferences.getStringList(_monitoredDevicesKey) ?? [];

  Future<void> addMonitoredDevice(String deviceId) async {
    final devices = getMonitoredDevices();
    if (!devices.contains(deviceId)) {
      devices.add(deviceId);
      await setMonitoredDevices(devices);
    }
  }

  Future<void> removeMonitoredDevice(String deviceId) async {
    final devices = getMonitoredDevices();
    devices.remove(deviceId);
    await setMonitoredDevices(devices);
  }

  bool isDeviceMonitored(String deviceId) =>
      getMonitoredDevices().contains(deviceId);
}
