import 'package:universal_ble/src/universal_ble_pigeon/universal_ble.g.dart';
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

  /// Requests an MTU (Maximum Transmission Unit) value for the connection.
  ///
  /// **⚠️ Note:** Requesting an MTU is a *best-effort* operation. The final MTU is
  /// often controlled by the OS and remote device. Returns the negotiated MTU value,
  /// which may differ from `expectedMtu`.
  ///
  /// See [UniversalBle.requestMtu] for platform limitations and best practices.
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
    Duration? timeout,
  }) {
    return UniversalBle.isPaired(
      deviceId,
      pairingCommand: pairingCommand,
      timeout: timeout,
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
    Duration? timeout,
  }) {
    return UniversalBle.pair(
      deviceId,
      pairingCommand: pairingCommand,
      timeout: timeout,
    );
  }

  /// Unpair a device.
  ///
  /// It might throw an error if device is not paired.
  Future<void> unpair({
    Duration? timeout,
  }) =>
      UniversalBle.unpair(deviceId, timeout: timeout);

  /// Discovers the services offered by the device.
  ///
  /// Returns cached services if already discovered after connection.
  Future<List<BleService>> discoverServices({
    Duration? timeout,
    bool withDescriptors = false,
  }) async {
    List<BleService> servicesCache = await UniversalBle.discoverServices(
      deviceId,
      withDescriptors: withDescriptors,
      timeout: timeout,
    );
    CacheHandler.instance.saveServices(deviceId, servicesCache);
    return servicesCache;
  }

  /// Retrieves a specific service.
  ///
  /// [service] is the UUID of the service.
  /// [preferCached] indicates whether to use cached services. If cache is empty, discoverServices() will be called.
  /// might throw [UniversalBleException]
  Future<BleService> getService(
    String service, {
    bool preferCached = true,
    Duration? timeout,
  }) async {
    List<BleService> discoveredServices = [];
    if (preferCached) {
      discoveredServices = CacheHandler.instance.getServices(deviceId) ?? [];
    }
    if (discoveredServices.isEmpty) {
      discoveredServices = await discoverServices(timeout: timeout);
    }

    if (discoveredServices.isEmpty) {
      throw UniversalBleException(
        code: UniversalBleErrorCode.serviceNotFound,
        message: 'No services found',
      );
    }

    return discoveredServices.firstWhere(
      (s) => BleUuidParser.compareStrings(s.uuid, service),
      orElse: () => throw UniversalBleException(
        code: UniversalBleErrorCode.serviceNotFound,
        message: 'Service "$service" not available',
      ),
    );
  }

  /// Retrieves a specific characteristic from a service.
  ///
  /// [service] is the UUID of the service.
  /// [characteristic] is the UUID of the characteristic.
  /// [preferCached] indicates whether to use cached services. If cache is empty, discoverServices() will be called.
  /// might throw [UniversalBleException]
  Future<BleCharacteristic> getCharacteristic(
    String characteristic, {
    required String service,
    bool preferCached = true,
    Duration? timeout,
  }) async {
    BleService bluetoothService = await getService(
      service,
      preferCached: preferCached,
      timeout: timeout,
    );
    return bluetoothService.getCharacteristic(characteristic);
  }
}
