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
}
