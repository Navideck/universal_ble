import 'package:universal_ble/src/utils/cache_handler.dart';
import 'package:universal_ble/universal_ble.dart';

/// Extension methods for [BleDevice] to simplify common operations.
extension BleDeviceExtension on BleDevice {
  /// A stream of [bool] that emits connection status changes for the device.
  Stream<bool> get connectionStream => UniversalBle.connectionStream(deviceId);

  /// Checks if the device is currently connected.
  Future<bool> get isConnected async =>
      await UniversalBle.getConnectionState(deviceId) ==
      BleConnectionState.connected;

  /// Connects to the device.
  Future<void> connect() => UniversalBle.connect(deviceId);

  /// Disconnects from the device.
  Future<void> disconnect() => UniversalBle.disconnect(deviceId);

  /// Requests a specific MTU (Maximum Transmission Unit) size for the connection.
  Future<int> requestMtu(expectedMtu) =>
      UniversalBle.requestMtu(deviceId, expectedMtu);

  /// Discovers the services offered by the device.
  ///
  /// Returns cached services if already discovered after connection.
  /// The cache will reset on disconnect. Set [cached] to false to always get fresh services.
  Future<List<BleService>> discoverServices({
    bool cached = true,
  }) async {
    List<BleService> servicesCache;
    if (cached) {
      servicesCache = CacheHandler.instance.getServices(deviceId) ?? [];
      if (servicesCache.isNotEmpty) return servicesCache;
    }
    servicesCache = await UniversalBle.discoverServices(deviceId);
    CacheHandler.instance.saveServices(deviceId, servicesCache);
    return servicesCache;
  }

  /// Retrieves a specific characteristic from a service.
  ///
  /// [service] is the UUID of the service.
  /// [characteristic] is the UUID of the characteristic.
  /// [cached] indicates whether to use cached services.
  Future<BleCharacteristic> getCharacteristic(
    String service,
    String characteristic, {
    bool cached = true,
  }) async {
    BleService bluetoothService = await getService(service, cached: cached);
    return bluetoothService.getCharacteristic(characteristic);
  }

  /// Retrieves a specific service.
  ///
  /// [service] is the UUID of the service.
  /// [cached] indicates whether to use cached services.
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
