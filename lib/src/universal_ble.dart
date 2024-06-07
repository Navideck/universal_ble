import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/src/ble_command_queue.dart';
import 'package:universal_ble/src/universal_ble_linux/universal_ble_linux.dart';
import 'package:universal_ble/src/universal_ble_pigeon/universal_ble_pigeon_channel.dart';
import 'package:universal_ble/src/universal_ble_platform_interface.dart';
import 'package:universal_ble/src/universal_ble_web/universal_ble_web.dart';
import 'package:universal_ble/universal_ble.dart';

class UniversalBle {
  /// Get platform specific implementation
  static UniversalBlePlatform _platform = _defaultPlatform();
  static final BleCommandQueue _bleCommandQueue = BleCommandQueue();

  /// Set custom platform specific implementation (e.g. for testing)
  static void setInstance(UniversalBlePlatform instance) =>
      _platform = instance;

  /// Set global timeout for all commands, default timeout is 10 seconds
  static set timeout(Duration? duration) {
    _bleCommandQueue.timeout = duration;
  }

  /// Setup global queue for all commands, by default queue is global
  /// [QueueType.none] will not execute commands in queue
  /// [QueueType.global] will execute commands of all devices in a single queue
  /// [QueueType.perDevice] will execute command of each device in a separate queue
  static set queuesCommands(QueueType queueType) {
    _bleCommandQueue.queueType = queueType;
    UniversalBlePlatform.logInfo('Queue ${queueType.name}');
  }

  /// To get Bluetooth state availability
  /// To get updates, set [onAvailabilityChange] listener
  static Future<AvailabilityState> getBluetoothAvailabilityState() async {
    return await _bleCommandQueue.executeCommand(
      () => _platform.getBluetoothAvailabilityState(),
    );
  }

  /// To Start scan, get scan results in [onScanResult] listener
  /// might throw errors if Bluetooth is not available
  /// `webRequestOptions` supported on Web only
  static Future<void> startScan({
    ScanFilter? scanFilter,
  }) async {
    return await _bleCommandQueue.executeCommand(
      () => _platform.startScan(scanFilter: scanFilter),
      withTimeout: false,
    );
  }

  /// To Stop scan, set [onScanResult] listener to `null` if you don't need it anymore
  /// might throw errors if Bluetooth is not available
  static Future<void> stopScan() async {
    return await _bleCommandQueue.executeCommand(
      () => _platform.stopScan(),
      withTimeout: false,
    );
  }

  /// To connect to a device, get connection state in [onConnectionChanged] listener
  /// preferred to stop scan before connecting
  /// might throw errors if device is not connectable
  /// `connectionTimeout` supported on Web only
  static Future<void> connect(
    String deviceId, {
    Duration? connectionTimeout,
  }) async {
    return await _bleCommandQueue.executeCommand(
      () => _platform.connect(deviceId, connectionTimeout: connectionTimeout),
      deviceId: deviceId,
    );
  }

  /// To disconnect from a device, get connection state in [onConnectionChanged] listener
  static Future<void> disconnect(String deviceId) async {
    return await _bleCommandQueue.executeCommand(
      () => _platform.disconnect(deviceId),
      deviceId: deviceId,
    );
  }

  /// To discover services of a device
  static Future<List<BleService>> discoverServices(String deviceId) async {
    return await _bleCommandQueue.executeCommand(
      () => _platform.discoverServices(deviceId),
      deviceId: deviceId,
    );
  }

  /// To set a characteristic notifiable, set `bleInputProperty` to [BleInputProperty.notification] or [BleInputProperty.indication], get updates in [onValueChanged] listener
  /// To stop listening to a characteristic, set `bleInputProperty` to [BleInputProperty.disabled]
  static Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) async {
    return await _bleCommandQueue.executeCommand(
      () => _platform.setNotifiable(
        deviceId,
        service,
        characteristic,
        bleInputProperty,
      ),
      deviceId: deviceId,
    );
  }

  /// To read a characteristic value
  /// on iOS and MacOS, this command will also trigger [onValueChanged] listener
  static Future<Uint8List> readValue(
    String deviceId,
    String service,
    String characteristic,
  ) async {
    return await _bleCommandQueue.executeCommand(
      () => _platform.readValue(deviceId, service, characteristic),
      deviceId: deviceId,
    );
  }

  /// To write a characteristic value
  /// To write a characteristic value with response, set `bleOutputProperty` to [BleOutputProperty.withResponse]
  static Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  ) async {
    await _bleCommandQueue.executeCommand(
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

  /// `requestMtu` not supported on `Linux` and `Web
  static Future<int> requestMtu(String deviceId, int expectedMtu) async {
    return await _bleCommandQueue.executeCommand(
      () => _platform.requestMtu(deviceId, expectedMtu),
      deviceId: deviceId,
    );
  }

  /// Pair commands are not supported on `iOS`, `MacOS` and `Web`
  static Future<bool> isPaired(String deviceId) async {
    return await _bleCommandQueue.executeCommand(
      () => _platform.isPaired(deviceId),
      deviceId: deviceId,
    );
  }

  /// To trigger pair request
  /// might throw errors if device is already paired
  static Future<void> pair(String deviceId) async {
    return await _bleCommandQueue.executeCommand(
      () => _platform.pair(deviceId),
      deviceId: deviceId,
    );
  }

  /// To trigger unPair request
  /// might throw errors if device is not paired
  static Future<void> unPair(String deviceId) async {
    return await _bleCommandQueue.executeCommand(
      () => _platform.unPair(deviceId),
      deviceId: deviceId,
    );
  }

  /// To get connected devices to the system (connected by any app)
  /// use [withServices] to filter devices by services
  /// on `iOS`, `MacOS` [withServices] is required to get connected devices, else [1800] service will be used as default filter
  /// on `Android`, `Linux` and `Windows`, if [withServices] is used, then internally all services will be discovered for each device first (either by connecting or by using cached services)
  /// Not supported on `Web`
  static Future<List<BleScanResult>> getConnectedDevices({
    List<String>? withServices,
  }) async {
    return await _bleCommandQueue.executeCommand(
      () => _platform.getConnectedDevices(withServices),
    );
  }

  /// Enabling Bluetooth, might throw errors if Bluetooth is not available
  /// Not supported on `Web` and `Apple`
  static Future<bool> enableBluetooth() async {
    return await _bleCommandQueue.executeCommand(
      () => _platform.enableBluetooth(),
    );
  }

  /// To get Bluetooth state availability
  static set onAvailabilityChange(OnAvailabilityChange? onAvailabilityChange) {
    _platform.onAvailabilityChange = onAvailabilityChange;
    if (onAvailabilityChange != null) {
      getBluetoothAvailabilityState().then((value) {
        onAvailabilityChange(value);
      }).onError((error, stackTrace) => null);
    }
  }

  /// To get updates of remaining items of a queue
  static set onQueueUpdate(OnQueueUpdate? onQueueUpdate) =>
      _bleCommandQueue.onQueueUpdate = onQueueUpdate;

  /// To get scan results
  static set onScanResult(OnScanResult? onScanResult) =>
      _platform.onScanResult = onScanResult;

  /// To get connection state changes
  static set onConnectionChanged(OnConnectionChanged? onConnectionChanged) =>
      _platform.onConnectionChanged = onConnectionChanged;

  /// To get characteristic value updates, set `bleInputProperty` in [setNotifiable] to [BleInputProperty.notification] or [BleInputProperty.indication]
  static set onValueChanged(OnValueChanged? onValueChanged) =>
      _platform.onValueChanged = onValueChanged;

  /// To get pair state changes,
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
