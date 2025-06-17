import 'package:universal_ble/src/utils/cache_handler.dart';
import 'package:universal_ble/universal_ble.dart';

/// Extension methods for [BleDevice] to simplify common operations.
extension BleDeviceExtension on BleDevice {
  /// A stream of [bool] that emits connection status changes for the device.
  Stream<bool> get connectionStream => UniversalBle.connectionStream(deviceId);

  /// A stream of [bool] that emits pairing status changes for the device.
  Stream<bool> get pairingStateStream =>
      UniversalBle.pairingStateStream(deviceId);

  /// Checks if the device is currently connected.
  Future<bool> get isConnected async =>
      await UniversalBle.getConnectionState(deviceId) ==
      BleConnectionState.connected;

  /// Connects to the device.
  Future<void> connect() => UniversalBle.connect(deviceId);

  /// Disconnects from the device.
  Future<void> disconnect() => UniversalBle.disconnect(deviceId);

  /// Requests a specific MTU (Maximum Transmission Unit) size for the connection.
  Future<int> requestMtu(int expectedMtu) =>
      UniversalBle.requestMtu(deviceId, expectedMtu);

  /// Check if a device is paired.
  ///
  /// For `Apple` and `Web`, you have to pass a "pairingCommand" with an encrypted read or write characteristic.
  /// Returns true/false if it manages to execute the command.
  /// Returns null when no `pairingCommand` is passed.
  /// Note that it will trigger pairing if the device is not already paired.
  Future<bool?> isPaired({
    BleCommand? pairingCommand,
    Duration? connectionTimeout,
  }) {
    return UniversalBle.isPaired(
      deviceId,
      pairingCommand: pairingCommand,
      connectionTimeout: connectionTimeout,
    );
  }

  /// Pair a device.
  ///
  /// It throws error if pairing fails.
  ///
  /// On `Apple` and `Web`, it only works on devices with encrypted characteristics.
  /// It is advised to pass a pairingCommand with an encrypted read or write characteristic.
  /// When not passing a pairingCommand, you should afterwards use [isPaired] with a pairingCommand
  /// to verify the pairing state.
  ///
  /// On `Web/Windows` and `Web/Linux`, it does not work for devices that use `ConfirmOnly` pairing.
  /// Can throw `PairingException`, `ConnectionException` or `PlatformException`.
  Future<void> pair({
    BleCommand? pairingCommand,
    Duration? connectionTimeout,
  }) {
    return UniversalBle.pair(
      deviceId,
      pairingCommand: pairingCommand,
      connectionTimeout: connectionTimeout,
    );
  }

  /// Unpair a device.
  ///
  /// It might throw an error if device is not paired.
  Future<void> unpair() => UniversalBle.unpair(deviceId);

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
    String characteristic, {
    required String service,
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
