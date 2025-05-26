import 'package:universal_ble/src/utils/cache_handler.dart';
import 'package:universal_ble/universal_ble.dart';

extension BleDeviceExtension on BleDevice {
  Stream<bool> get connectionStream => UniversalBle.connectionStream(deviceId);

  Future<bool> get isConnected async =>
      await UniversalBle.getConnectionState(deviceId) ==
      BleConnectionState.connected;

  Future<void> connect() => UniversalBle.connect(deviceId);

  Future<void> disconnect() => UniversalBle.disconnect(deviceId);

  Future<int> requestMtu(expectedMtu) =>
      UniversalBle.requestMtu(deviceId, expectedMtu);

  /// Returns cached services if already discovered after connection
  /// cache will reset on disconnect, to always get fresh services set [cached] false
  Future<List<BleService>> discoverServices({
    bool cached = true,
  }) async {
    List<BleService> servicesCache;
    if (cached) {
      servicesCache = CacheHandler.instance.getServices(deviceId) ?? [];
      if (servicesCache.isNotEmpty) return servicesCache;
    }
    var services = await UniversalBle.discoverServices(deviceId);
    servicesCache = services.toList();
    CacheHandler.instance.saveServices(deviceId, servicesCache);
    return servicesCache;
  }

  Future<BleCharacteristic> getCharacteristic(
    String service,
    String characteristic, {
    bool cached = true,
  }) async {
    BleService bluetoothService = await getService(service, cached: cached);
    if (bluetoothService.characteristics.isEmpty) {
      throw 'No characteristics found';
    }
    return bluetoothService.characteristics.firstWhere(
      (c) => BleUuidParser.compareStrings(c.uuid, characteristic),
      orElse: () => throw 'Characteristic "$characteristic" not available',
    );
  }

  Future<BleService> getService(
    String service, {
    bool cached = true,
  }) async {
    List<BleService> services = await discoverServices(cached: cached);
    if (services.isEmpty) throw 'No services found';
    return services.firstWhere(
      (s) => BleUuidParser.compareStrings(s.uuid, service),
      orElse: () => throw 'Service "$service" not available',
    );
  }
}
