import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/src/ble_command_queue.dart';
import 'package:universal_ble/src/universal_ble_linux/universal_ble_linux.dart';
import 'package:universal_ble/src/universal_ble_pigeon/universal_ble_pigeon_channel.dart';
import 'package:universal_ble/src/universal_ble_web/universal_ble_web.dart';
import 'package:universal_ble/universal_ble.dart';

class UniversalBle {
  /// Get platform specific implementation.
  static UniversalBlePlatform _platform = _defaultPlatform();
  static final BleCommandQueue _bleCommandQueue = BleCommandQueue();

  /// Set custom platform specific implementation (e.g. for testing).
  static void setInstance(UniversalBlePlatform instance) =>
      _platform = instance;

  /// Set global timeout for all commands.
  /// Default timeout is 10 seconds.
  /// Set to null to disable.
  static set timeout(Duration? duration) {
    _bleCommandQueue.timeout = duration;
  }

  /// Set how commands will be executed. By default, all commands are executed in a global queue (`QueueType.global`),
  /// with each command waiting for the previous one to finish.
  ///
  /// [QueueType.global] will execute commands of all devices in a single queue.
  /// [QueueType.perDevice] will execute command of each device in separate queues.
  /// [QueueType.none] will execute all commands in parallel.
  static set queueType(QueueType queueType) {
    _bleCommandQueue.queueType = queueType;
    UniversalBlePlatform.logInfo('Queue ${queueType.name}');
  }

  /// Get Bluetooth availability state.
  /// To be notified of updates, set [onAvailabilityChange] listener.
  static Future<AvailabilityState> getBluetoothAvailabilityState() async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.getBluetoothAvailabilityState(),
    );
  }

  /// Start scan.
  /// Scan results will arrive in [onScanResult] listener.
  /// It might throw errors if Bluetooth is not available.
  /// `webRequestOptions` is supported on Web only.
  static Future<void> startScan({
    ScanFilter? scanFilter,
    PlatformConfig? platformConfig,
  }) async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.startScan(
        scanFilter: scanFilter,
        platformConfig: platformConfig,
      ),
      withTimeout: false,
    );
  }

  /// Stop scan.
  /// Set [onScanResult] listener to `null` if you don't need it anymore.
  /// It might throw errors if Bluetooth is not available.
  static Future<void> stopScan() async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.stopScan(),
      withTimeout: false,
    );
  }

  /// Connection stream of a device
  Stream<bool> connectionStream(String deviceId) =>
      _platform.connectionStream(deviceId);

  /// Connect to a device.
  /// It is advised to stop scanning before connecting.
  /// It might throw errors if device is not connectable.
  /// `connectionTimeout` is supported on Web only.
  static Future<bool> connect(
    String deviceId, {
    Duration? connectionTimeout,
  }) async {
    StreamSubscription? connectionSubscription;
    try {
      Completer<bool> completer = Completer();

      connectionSubscription =
          _platform.connectionStream(deviceId).listen((bool event) {
        connectionSubscription?.cancel();
        if (!completer.isCompleted) {
          completer.complete(event);
        }
      });

      _platform
          .connect(deviceId, connectionTimeout: connectionTimeout)
          .catchError(
        (error) {
          if (completer.isCompleted == false) {
            connectionSubscription?.cancel();
            completer.completeError(error);
          }
        },
      );

      if (connectionTimeout != null) {
        return await completer.future.timeout(connectionTimeout);
      }
      return await completer.future;
    } finally {
      connectionSubscription?.cancel();
    }
  }

  /// Disconnect from a device.
  /// Get notified of connection state changes in [onConnectionChange] listener.
  static Future<void> disconnect(String deviceId) async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.disconnect(deviceId),
      deviceId: deviceId,
    );
  }

  /// Discover services of a device.
  static Future<List<BleService>> discoverServices(String deviceId) async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.discoverServices(deviceId),
      deviceId: deviceId,
    );
  }

  /// Set a characteristic notifiable.
  /// Set `bleInputProperty` to [BleInputProperty.notification] or [BleInputProperty.indication].
  /// Updates will arrive in [onValueChange] listener.
  /// To stop listening to a characteristic, set `bleInputProperty` to [BleInputProperty.disabled].
  static Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.setNotifiable(
        deviceId,
        BleUuidParser.string(service),
        BleUuidParser.string(characteristic),
        bleInputProperty,
      ),
      deviceId: deviceId,
    );
  }

  /// Read a characteristic value.
  /// On iOS and MacOS this command will also trigger [onValueChange] listener.
  static Future<Uint8List> readValue(
    String deviceId,
    String service,
    String characteristic,
  ) async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.readValue(
        deviceId,
        BleUuidParser.string(service),
        BleUuidParser.string(characteristic),
      ),
      deviceId: deviceId,
    );
  }

  /// Write a characteristic value.
  /// To write a characteristic value with response, set `bleOutputProperty` to [BleOutputProperty.withResponse].
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
        BleUuidParser.string(service),
        BleUuidParser.string(characteristic),
        value,
        bleOutputProperty,
      ),
      deviceId: deviceId,
    );
  }

  /// Request MTU value.
  /// `requestMtu` is not supported on `Linux` and `Web.
  static Future<int> requestMtu(String deviceId, int expectedMtu) async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.requestMtu(deviceId, expectedMtu),
      deviceId: deviceId,
    );
  }

  /// Check if a device is paired.
  ///
  /// For Apple and Web, you can optionally pass a pairingCommand if you know an encrypted read or write characteristic.
  /// It will return true/false if it manages to execute the command.
  /// Note that it will trigger pairing if the device is not already paired.
  ///
  /// Returns null on `Apple` and `Web` when no `bleCommand` is passed.
  static Future<bool?> isPaired(
    String deviceId, {
    BleCommand? pairingCommand,
  }) async {
    if (!BleCapabilities.hasSystemPairingApi && pairingCommand == null) {
      return null;
    }

    return BleCapabilities.hasSystemPairingApi
        ? await _bleCommandQueue.queueCommand(
            () => _platform.isPaired(deviceId),
            deviceId: deviceId,
          )
        : await _connectAndExecuteBleCommand(deviceId, pairingCommand);
  }

  /// Pair a device.
  /// It might throw an error if device is already paired.
  ///
  /// On `Apple` and `Web`, it only works on devices with encrypted characteristics.
  /// It returns null if there is no readable characteristic.
  ///
  /// You can optionally pass a pairingCommand if you know an encrypted read or write characteristic.
  /// If you do, it returns true if it can successfully execute the command after pairing.
  ///
  /// Throws UnsupportedError on `Web/Windows`

  static Future<bool?> pair(
    String deviceId, {
    BleCommand? pairingCommand,
  }) async {
    if (BleCapabilities.hasSystemPairingApi) {
      // TODO Maybe return pairing result from system API
      await _platform.pair(deviceId); // Not sure if we could keep queuing
      // TODO Currently, only Apple and Linux await until pairing is finished
    } else if (!BleCapabilities.supportsInAppPairing) {
      throw UnsupportedError("Not supported");
    }
    if (pairingCommand == null) return null;
    return await _connectAndExecuteBleCommand(deviceId, pairingCommand);
  }

  /// Unpair a device.
  /// It might throw an error if device is not paired.
  static Future<void> unpair(String deviceId) async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.unpair(deviceId),
      deviceId: deviceId,
    );
  }

  /// Get connected devices to the system (connected by any app).
  /// Use [withServices] to filter devices by services.
  /// On `Apple`, [withServices] is required to get connected devices, else [1800] service will be used as default filter.
  /// On `Android`, `Linux` and `Windows`, if [withServices] is used, then internally all services will be discovered for each device first (either by connecting or by using cached services).
  /// Not supported on `Web`.
  static Future<List<BleDevice>> getSystemDevices({
    List<String>? withServices,
  }) async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.getSystemDevices(withServices),
    );
  }

  /// Returns connection state of the device.
  /// All platforms will return `Connected/Disconnected` states.
  /// `Android` and `Apple` can also return `Connecting/Disconnecting` states.
  static Future<BleConnectionState> getConnectionState(String deviceId) async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.getConnectionState(deviceId),
    );
  }

  /// Enable Bluetooth.
  /// It might throw errors if Bluetooth is not available.
  /// Not supported on `Web` and `Apple`.
  static Future<bool> enableBluetooth() async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.enableBluetooth(),
    );
  }

  /// [receivesAdvertisements] returns true on web if the browser supports receiving advertisements from a certain `deviceId`.
  /// The rest of the platforms will always return true.
  /// If true, then you will be getting scanResult updates for this device.
  ///
  /// For this feature to work, you need to enable the `chrome://flags/#enable-experimental-web-platform-features` flag.
  /// Not every browser supports this API yet.
  /// Even if the browser supports it, sometimes it won't fire any advertisement events even though the device may be sending them.
  static bool receivesAdvertisements(String deviceId) =>
      _platform.receivesAdvertisements(deviceId);

  /// Get Bluetooth state availability.
  static set onAvailabilityChange(OnAvailabilityChange? onAvailabilityChange) {
    _platform.onAvailabilityChange = onAvailabilityChange;
    if (onAvailabilityChange != null) {
      getBluetoothAvailabilityState().then((value) {
        onAvailabilityChange(value);
      }).onError((error, stackTrace) => null);
    }
  }

  static Future<bool?> _connectAndExecuteBleCommand(
    String deviceId,
    BleCommand? bleCommand,
  ) async {
    try {
      if (await getConnectionState(deviceId) != BleConnectionState.connected) {
        await connect(deviceId);
      }

      List<BleService> services = await discoverServices(deviceId);

      if (bleCommand == null) {
        await _attemptPairingReadingAll(deviceId, services);
        return null;
      } else {
        bool commandResult =
            await _executeBleCommand(deviceId, services, bleCommand);
        _platform.updatePairingState(deviceId, commandResult, null);
        return commandResult;
      }
    } catch (e) {
      UniversalBlePlatform.logInfo(
        "FailedToPerform EncryptedCharOperation: $e",
      );
      // Probably failed to pair, Notify callback
      _platform.updatePairingState(deviceId, false, e.toString());
      return false;
    }
  }

  // Fire and forget, and do not rely on result
  static _attemptPairingReadingAll(
    String deviceId,
    List<BleService> services,
  ) async {
    bool containsReadCharacteristics = false;
    try {
      // If BleCommand not given, fallback to reading all characteristics
      for (BleService service in services) {
        for (BleCharacteristic characteristic in service.characteristics) {
          if (characteristic.properties.contains(CharacteristicProperty.read)) {
            containsReadCharacteristics = true;
            await readValue(deviceId, service.uuid, characteristic.uuid);
          }
        }
      }
    } catch (_) {}
    if (!containsReadCharacteristics) {
      throw "No readable characteristic found";
    }
  }

  static Future<bool> _executeBleCommand(
    String deviceId,
    List<BleService> services,
    BleCommand bleCommand,
  ) async {
    // First find BleCommand's characteristic
    BleCharacteristic? characteristic;
    for (BleService service in services) {
      if (BleUuidParser.compareStrings(service.uuid, bleCommand.service)) {
        for (BleCharacteristic char in service.characteristics) {
          if (BleUuidParser.compareStrings(
              char.uuid, bleCommand.characteristic)) {
            characteristic = char;
            break;
          }
        }
      }
    }

    if (characteristic == null) {
      return false;
    }

    // Check if BleCommand Supports Read or Write
    BleOutputProperty? bleOutputProperty;
    if (characteristic.properties.contains(CharacteristicProperty.write)) {
      bleOutputProperty = BleOutputProperty.withResponse;
    } else if (characteristic.properties
        .contains(CharacteristicProperty.writeWithoutResponse)) {
      bleOutputProperty = BleOutputProperty.withoutResponse;
    } else if (!characteristic.properties
        .contains(CharacteristicProperty.read)) {
      return false;
    }

    Uint8List? value = bleCommand.writeValue;
    if (value != null && bleOutputProperty != null) {
      await writeValue(
        deviceId,
        bleCommand.service,
        bleCommand.characteristic,
        value,
        bleOutputProperty,
      );
    } else {
      // Fallback to read if supported
      await readValue(
        deviceId,
        bleCommand.service,
        bleCommand.characteristic,
      );
    }
    return true;
  }

  /// Get updates of remaining items of a queue.
  static set onQueueUpdate(OnQueueUpdate? onQueueUpdate) =>
      _bleCommandQueue.onQueueUpdate = onQueueUpdate;

  /// Get scan results.
  static set onScanResult(OnScanResult? bleDevice) =>
      _platform.onScanResult = bleDevice;

  /// Get connection state changes.
  static set onConnectionChange(OnConnectionChange? onConnectionChange) =>
      _platform.onConnectionChange = onConnectionChange;

  /// Get characteristic value updates, set `bleInputProperty` in [setNotifiable] to [BleInputProperty.notification] or [BleInputProperty.indication].
  static set onValueChange(OnValueChange? onValueChange) =>
      _platform.onValueChange = onValueChange;

  /// Get pair state changes.
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
