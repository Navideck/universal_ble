import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/src/ble_command_queue.dart';
import 'package:universal_ble/src/universal_ble_linux/universal_ble_linux.dart';
import 'package:universal_ble/src/universal_ble_pigeon/universal_ble_pigeon_channel.dart';
import 'package:universal_ble/src/universal_ble_web/universal_ble_web.dart';
import 'package:universal_ble/universal_ble.dart';

class UniversalBle {
  /// Get platform specific implementation
  static UniversalBlePlatform _platform = _defaultPlatform();
  static final BleCommandQueue _bleCommandQueue = BleCommandQueue();

  /// Set custom platform specific implementation (e.g. for testing)
  static void setInstance(UniversalBlePlatform instance) =>
      _platform = instance;

  /// Set global timeout for all commands.
  /// Default timeout is 10 seconds
  /// Set to null to disable
  static set timeout(Duration? duration) {
    _bleCommandQueue.timeout = duration;
  }

  /// Set how commands will be executed. By default, all commands are executed in a global queue (`QueueType.global`),
  /// with each command waiting for the previous one to finish.
  ///
  /// [QueueType.global] will execute commands of all devices in a single queue
  /// [QueueType.perDevice] will execute command of each device in separate queues
  /// [QueueType.none] will execute all commands in parallel
  static set queueType(QueueType queueType) {
    _bleCommandQueue.queueType = queueType;
    UniversalBlePlatform.logInfo('Queue ${queueType.name}');
  }

  /// Get Bluetooth availability state
  /// To be notified of updates, set [onAvailabilityChange] listener
  static Future<AvailabilityState> getBluetoothAvailabilityState() async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.getBluetoothAvailabilityState(),
    );
  }

  /// Start scan.
  /// Scan results will arrive in [onScanResult] listener
  /// It might throw errors if Bluetooth is not available
  /// `webRequestOptions` is supported on Web only
  static Future<void> startScan({
    ScanFilter? scanFilter,
  }) async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.startScan(scanFilter: scanFilter),
      withTimeout: false,
    );
  }

  /// Stop scan.
  /// Set [onScanResult] listener to `null` if you don't need it anymore
  /// It might throw errors if Bluetooth is not available
  static Future<void> stopScan() async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.stopScan(),
      withTimeout: false,
    );
  }

  /// Connect to a device.
  /// Get notified of connection state changes in [onConnectionChange] listener
  /// It is advised to stop scanning before connecting
  /// It might throw errors if device is not connectable
  /// `connectionTimeout` is supported on Web only
  static Future<void> connect(
    String deviceId, {
    Duration? connectionTimeout,
  }) async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.connect(deviceId, connectionTimeout: connectionTimeout),
      deviceId: deviceId,
    );
  }

  /// Disconnect from a device.
  /// Get notified of connection state changes in [onConnectionChange] listener
  static Future<void> disconnect(String deviceId) async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.disconnect(deviceId),
      deviceId: deviceId,
    );
  }

  /// Discover services of a device
  static Future<List<BleService>> discoverServices(String deviceId) async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.discoverServices(deviceId),
      deviceId: deviceId,
    );
  }

  /// Set a characteristic notifiable.
  /// Set `bleInputProperty` to [BleInputProperty.notification] or [BleInputProperty.indication]
  /// Updates will arrive in [onValueChange] listener
  /// To stop listening to a characteristic, set `bleInputProperty` to [BleInputProperty.disabled]
  static Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.setNotifiable(
        deviceId,
        service,
        characteristic,
        bleInputProperty,
      ),
      deviceId: deviceId,
    );
  }

  /// Read a characteristic value
  /// On iOS and MacOS this command will also trigger [onValueChange] listener
  static Future<Uint8List> readValue(
    String deviceId,
    String service,
    String characteristic,
  ) async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.readValue(deviceId, service, characteristic),
      deviceId: deviceId,
    );
  }

  /// Write a characteristic value
  /// To write a characteristic value with response, set `bleOutputProperty` to [BleOutputProperty.withResponse]
  static Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  ) async {
    await _bleCommandQueue.queueCommand(
      () => _platform.writeValue(
        deviceId,
        service,
        characteristic,
        value,
        bleOutputProperty,
      ),
      deviceId: deviceId,
    );
  }

  /// Request MTU value
  /// `requestMtu` is not supported on `Linux` and `Web
  static Future<int> requestMtu(String deviceId, int expectedMtu) async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.requestMtu(deviceId, expectedMtu),
      deviceId: deviceId,
    );
  }

  /// Check if a device is paired
  /// Returns null on `Apple` and `Web`
  static Future<bool?> isPaired(String deviceId) async {
    if (kIsWeb || Platform.isIOS || Platform.isMacOS) return null;
    return await _bleCommandQueue.queueCommand(
      () => _platform.isPaired(deviceId),
      deviceId: deviceId,
    );
  }

  /// Trigger pair request
  /// It might throw an error if device is already paired
  static Future<void> pair(String deviceId) async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.pair(deviceId),
      deviceId: deviceId,
    );
  }

  /// Unpair a device
  /// It might throw an error if device is not paired
  static Future<void> unPair(String deviceId) async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.unPair(deviceId),
      deviceId: deviceId,
    );
  }

  /// Get connected devices to the system (connected by any app)
  /// Use [withServices] to filter devices by services
  /// On `Apple`, [withServices] is required to get connected devices, else [1800] service will be used as default filter
  /// On `Android`, `Linux` and `Windows`, if [withServices] is used, then internally all services will be discovered for each device first (either by connecting or by using cached services)
  /// Not supported on `Web`
  static Future<List<BleDevice>> getSystemDevices({
    List<String>? withServices,
  }) async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.getSystemDevices(withServices),
    );
  }

  /// Returns connection state of device,
  /// All platforms will return `Connected/Disconnected` states
  /// `Android` and `Apple` can also return `Connecting/Disconnecting` states
  static Future<BleConnectionState> getConnectionState(String deviceId) async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.getConnectionState(deviceId),
    );
  }

  /// Enable Bluetooth
  /// It might throw errors if Bluetooth is not available
  /// Not supported on `Web` and `Apple`
  static Future<bool> enableBluetooth() async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.enableBluetooth(),
    );
  }

  /// Get Bluetooth state availability
  static set onAvailabilityChange(OnAvailabilityChange? onAvailabilityChange) {
    _platform.onAvailabilityChange = onAvailabilityChange;
    if (onAvailabilityChange != null) {
      getBluetoothAvailabilityState().then((value) {
        onAvailabilityChange(value);
      }).onError((error, stackTrace) => null);
    }
  }

  /// Get updates of remaining items of a queue
  static set onQueueUpdate(OnQueueUpdate? onQueueUpdate) =>
      _bleCommandQueue.onQueueUpdate = onQueueUpdate;

  /// Get scan results
  static set onScanResult(OnScanResult? bleDevice) =>
      _platform.onScanResult = bleDevice;

  /// Get connection state changes
  static set onConnectionChange(OnConnectionChange? onConnectionChange) =>
      _platform.onConnectionChange = onConnectionChange;

  /// Get characteristic value updates, set `bleInputProperty` in [setNotifiable] to [BleInputProperty.notification] or [BleInputProperty.indication]
  static set onValueChange(OnValueChange? onValueChange) =>
      _platform.onValueChange = onValueChange;

  /// Get pair state changes,
  static set onPairingStateChange(OnPairingStateChange pairingStateChange) =>
      _platform.onPairingStateChange = pairingStateChange;

  static UniversalBlePlatform _defaultPlatform() {
    if (kIsWeb) return UniversalBleWeb.instance;
    if (defaultTargetPlatform == TargetPlatform.linux) {
      return UniversalBleLinux.instance;
    }
    return UniversalBlePigeonChannel.instance;
  }
}
