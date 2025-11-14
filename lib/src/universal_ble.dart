import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/src/utils/ble_command_queue.dart';
import 'package:universal_ble/src/universal_ble_linux/universal_ble_linux.dart';
import 'package:universal_ble/src/universal_ble_pigeon/universal_ble_pigeon_channel.dart';
import 'package:universal_ble/src/universal_ble_web/universal_ble_web.dart';
import 'package:universal_ble/src/utils/universal_logger.dart';
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
    UniversalLogger.logInfo('Queue ${queueType.name}');
  }

  /// Scan Stream
  static Stream<BleDevice> get scanStream => _platform.scanStream;

  /// Bluetooth availability state stream
  static Stream<AvailabilityState> get availabilityStream =>
      _platform.availabilityStream;

  /// Connection stream of a device
  static Stream<bool> connectionStream(String deviceId) =>
      _platform.connectionStream(deviceId);

  /// Characteristic value stream
  static Stream<Uint8List> characteristicValueStream(
          String deviceId, String characteristicId) =>
      _platform.characteristicValueStream(deviceId, characteristicId);

  /// Pairing state stream
  static Stream<bool> pairingStateStream(String deviceId) =>
      _platform.pairingStateStream(deviceId);

  /// Get Bluetooth availability state.
  /// To be notified of updates, set [onAvailabilityChange] listener.
  static Future<AvailabilityState> getBluetoothAvailabilityState() async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.getBluetoothAvailabilityState(),
    );
  }

  /// Request permissions.
  /// if all permissions are already granted or granted by user, this method will succeed.
  /// it will throw exception if permissions are denied by user.
  /// [withAndroidFineLocation] is used to request fine location permission on Android 12+ (API 31+).
  /// on Android lower than 12, this method will request location permission regardless of the [withAndroidFineLocation] value.
  /// `Windows`, `Linux` and `Web` will always succeed.
  static Future<void> requestPermissions({
    bool withAndroidFineLocation = false,
  }) async {
    return _platform.requestPermissions(
      withAndroidFineLocation: withAndroidFineLocation,
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
    return await _bleCommandQueue.queueCommandWithoutTimeout(
      () => _platform.startScan(
        scanFilter: scanFilter,
        platformConfig: platformConfig,
      ),
    );
  }

  /// Stop scan.
  /// Set [onScanResult] listener to `null` if you don't need it anymore.
  /// It might throw errors if Bluetooth is not available.
  static Future<void> stopScan() async {
    return await _bleCommandQueue.queueCommandWithoutTimeout(
      () => _platform.stopScan(),
    );
  }

  /// Check if currently scanning for devices.
  /// Returns `true` if scanning is active, `false` otherwise.
  static Future<bool> isScanning() async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.isScanning(),
    );
  }

  /// Connect to a device.
  /// It is advised to stop scanning before connecting.
  /// It throws error if device connection fails.
  /// Default connection timeout is 60 sec.
  /// Can throw `ConnectionException` or `PlatformException`.
  static Future<void> connect(
    String deviceId, {
    Duration? timeout,
  }) async {
    timeout ??= const Duration(seconds: 60);
    Completer<bool> completer =
        _connectionEventCompleter(deviceId, timeout: timeout);

    _platform.connect(deviceId, connectionTimeout: timeout).catchError(
      (error) {
        if (completer.isCompleted) return;
        completer.completeError(ConnectionException(error));
      },
    );

    if (!await completer.future.timeout(timeout)) {
      throw ConnectionException("Failed to connect");
    }
  }

  /// Disconnect from a device.
  /// Get notified of connection state changes in [onConnectionChange] listener.
  static Future<void> disconnect(
    String deviceId, {
    Duration? timeout,
  }) async {
    timeout ??= const Duration(seconds: 60);
    BleConnectionState? connectionState;
    try {
      connectionState = await _platform.getConnectionState(deviceId);
    } catch (e) {
      UniversalLogger.logError("Get connection state failed: $e");
    }

    if (connectionState == BleConnectionState.disconnected ||
        connectionState == BleConnectionState.disconnecting) {
      _platform.updateConnection(deviceId, false);
      UniversalLogger.logInfo(
        "Device $deviceId already disconnected: $connectionState",
      );
      return;
    }

    try {
      Completer<bool> completer =
          _connectionEventCompleter(deviceId, timeout: timeout);

      await _bleCommandQueue
          .queueCommand(() => _platform.disconnect(deviceId),
              timeout: timeout, deviceId: deviceId)
          .catchError(
        (error) {
          if (completer.isCompleted) return;
          completer.completeError(ConnectionException(error));
        },
      );

      if (await completer.future.timeout(timeout)) {
        UniversalLogger.logError("Disconnect verification failed: $deviceId");
      }
    } catch (e) {
      UniversalLogger.logError("Disconnect failed: $e");
    }
  }

  /// Discover services of a device.
  static Future<List<BleService>> discoverServices(
    String deviceId, {
    Duration? timeout,
  }) async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.discoverServices(deviceId),
      timeout: timeout,
      deviceId: deviceId,
    );
  }

  /// Set a characteristic notifiable.
  /// Updates will arrive in [onValueChange] listener and [characteristicValueStream]
  /// call [unsubscribe] to stop updates
  static Future<void> subscribeNotifications(
    String deviceId,
    String service,
    String characteristic, {
    Duration? timeout,
  }) async {
    return _sendBleInputPropertyCommand(
      deviceId,
      service,
      characteristic,
      BleInputProperty.notification,
      timeout: timeout,
    );
  }

  /// Set a characteristic notifiable.
  /// Updates will arrive in [onValueChange] listener and [characteristicValueStream]
  /// call [unsubscribe] to stop updates
  static Future<void> subscribeIndications(
    String deviceId,
    String service,
    String characteristic, {
    Duration? timeout,
  }) async {
    return _sendBleInputPropertyCommand(
      deviceId,
      service,
      characteristic,
      BleInputProperty.indication,
      timeout: timeout,
    );
  }

  /// Stop characteristic notifications/indication updates
  static Future<void> unsubscribe(
    String deviceId,
    String service,
    String characteristic, {
    Duration? timeout,
  }) async {
    return _sendBleInputPropertyCommand(
      deviceId,
      service,
      characteristic,
      BleInputProperty.disabled,
      timeout: timeout,
    );
  }

  /// Read a characteristic value.
  /// On iOS and MacOS this command will also trigger [onValueChange] listener.
  static Future<Uint8List> read(
    String deviceId,
    String service,
    String characteristic, {
    final Duration? timeout,
  }) async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.readValue(
        deviceId,
        BleUuidParser.string(service),
        BleUuidParser.string(characteristic),
        timeout: timeout ?? _bleCommandQueue.timeout,
      ),
      timeout: timeout,
      deviceId: deviceId,
    );
  }

  /// Write a characteristic value.
  /// To write a characteristic value without response, set [withoutResponse] to `true`.
  static Future<void> write(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value, {
    bool withoutResponse = false,
    Duration? timeout,
  }) async {
    await _bleCommandQueue.queueCommand(
      () => _platform.writeValue(
        deviceId,
        BleUuidParser.string(service),
        BleUuidParser.string(characteristic),
        value,
        withoutResponse
            ? BleOutputProperty.withoutResponse
            : BleOutputProperty.withResponse,
      ),
      timeout: timeout,
      deviceId: deviceId,
    );
  }

  /// Request MTU value.
  /// It will **attempt** to set the MTU (Maximum Transmission Unit) but it is not guaranteed to succeed due to platform limitations.
  /// It will always return the current MTU.
  static Future<int> requestMtu(
    String deviceId,
    int expectedMtu, {
    Duration? timeout,
  }) async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.requestMtu(deviceId, expectedMtu),
      timeout: timeout,
      deviceId: deviceId,
    );
  }

  /// Check if a device is paired.
  ///
  /// For `Apple` and `Web`, you have to pass a "pairingCommand" with an encrypted read or write characteristic.
  /// Returns true/false if it manages to execute the command.
  /// Returns null when no `pairingCommand` is passed.
  /// Note that it will trigger pairing if the device is not already paired.
  static Future<bool?> isPaired(
    String deviceId, {
    BleCommand? pairingCommand,
    Duration? timeout,
  }) async {
    if (BleCapabilities.hasSystemPairingApi) {
      return _bleCommandQueue.queueCommand(
        () => _platform.isPaired(deviceId),
        deviceId: deviceId,
        timeout: timeout,
      );
    }

    if (pairingCommand == null) {
      UniversalLogger.logWarning("PairingCommand required to get result");
      return null;
    }

    try {
      await _connectAndExecuteBleCommand(
        deviceId,
        pairingCommand,
        updateCallbackValue: false,
        timeout: timeout,
      );

      // Because pairingCommand will be never null, so we wont get Unknown result here
      return true;
    } catch (e) {
      UniversalLogger.logError("ExecuteBleCommandFailed: $e");
      return false;
    }
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
  static Future<void> pair(
    String deviceId, {
    BleCommand? pairingCommand,
    Duration? timeout,
  }) async {
    if (BleCapabilities.hasSystemPairingApi) {
      bool paired = await _bleCommandQueue.queueCommand(
        () => _platform.pair(deviceId),
        deviceId: deviceId,
        timeout: timeout,
      );
      if (!paired) throw PairingException();
    } else {
      if (pairingCommand == null) {
        UniversalLogger.logWarning("PairingCommand required to get result");
      }
      await _connectAndExecuteBleCommand(
        deviceId,
        pairingCommand,
        timeout: timeout,
      );
    }
  }

  /// Unpair a device.
  /// It might throw an error if device is not paired.
  static Future<void> unpair(
    String deviceId, {
    Duration? timeout,
  }) async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.unpair(deviceId),
      deviceId: deviceId,
      timeout: timeout,
    );
  }

  /// Get connected devices to the system (connected by any app).
  /// Use [withServices] to filter devices by services.
  /// On `Apple`, [withServices] is required to get any connected devices. If not passed, several 18XX generic services will be set by default.
  /// On `Android`, `Linux` and `Windows`, if [withServices] is used, then internally all services will be discovered for each device first (either by connecting or by using cached services).
  /// Not supported on `Web`.
  static Future<List<BleDevice>> getSystemDevices({
    List<String>? withServices,
    Duration? timeout,
  }) async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.getSystemDevices(withServices?.toValidUUIDList()),
      timeout: timeout,
    );
  }

  /// Returns connection state of the device.
  /// All platforms will return `Connected/Disconnected` states.
  /// `Android` and `Apple` can also return `Connecting/Disconnecting` states.
  static Future<BleConnectionState> getConnectionState(
    String deviceId, {
    Duration? timeout,
  }) async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.getConnectionState(deviceId),
      timeout: timeout,
    );
  }

  /// Enable Bluetooth.
  /// It might throw errors if Bluetooth is not available.
  /// Not supported on `Web` and `Apple`.
  static Future<bool> enableBluetooth({
    Duration? timeout,
  }) async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.enableBluetooth(),
      timeout: timeout,
    );
  }

  /// Disable Bluetooth.
  /// It might throw errors if Bluetooth is not available.
  /// Not supported on `Web` and `Apple`.
  static Future<bool> disableBluetooth({
    Duration? timeout,
  }) async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.disableBluetooth(),
      timeout: timeout,
    );
  }

  /// Clear a queue.
  /// Use [BleCommandQueue.globalQueueId] to clear the global queue.
  /// To clear the queue of a specific device, use `deviceId` as [id].
  /// If no [id] is provided, all queues will be cleared.
  static void clearQueue([String? id]) => _bleCommandQueue.clearQueue(id);

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

  @Deprecated(
      "Use [subscribeNotifications] or [subscribeIndications] or [unsubscribe] instead")
  static Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) async {
    return _sendBleInputPropertyCommand(
      deviceId,
      service,
      characteristic,
      bleInputProperty,
    );
  }

  @Deprecated("Use [write] instead")
  static Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  ) async {
    await write(
      deviceId,
      service,
      characteristic,
      value,
      withoutResponse: bleOutputProperty == BleOutputProperty.withoutResponse,
    );
  }

  @Deprecated("Use [read] instead")
  static Future<Uint8List> readValue(
    String deviceId,
    String service,
    String characteristic, {
    final Duration? timeout,
  }) {
    return read(deviceId, service, characteristic, timeout: timeout);
  }

  static Completer<bool> _connectionEventCompleter(
    String deviceId, {
    Duration? timeout,
  }) {
    timeout ??= const Duration(seconds: 60);
    StreamSubscription? connectionSubscription;
    Completer<bool> completer = Completer();

    void cancelSubscription() {
      connectionSubscription?.cancel();
      connectionSubscription = null;
    }

    void handleError(dynamic error) {
      cancelSubscription();
      if (completer.isCompleted) return;
      completer.completeError(ConnectionException(error));
    }

    connectionSubscription = _platform
        .bleConnectionUpdateStreamController.stream
        .where((e) => e.deviceId == deviceId)
        .listen(
      (e) {
        cancelSubscription();
        if (e.error != null) {
          handleError(e.error);
        } else {
          if (!completer.isCompleted) {
            completer.complete(e.isConnected);
          }
        }
      },
      onError: handleError,
      cancelOnError: true,
    );

    completer.future.timeout(timeout).then((_) {
      cancelSubscription();
    }).catchError((_) {
      cancelSubscription();
    });

    return completer;
  }

  static Future<void> _sendBleInputPropertyCommand(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty, {
    Duration? timeout,
  }) async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.setNotifiable(
        deviceId,
        BleUuidParser.string(service),
        BleUuidParser.string(characteristic),
        bleInputProperty,
      ),
      deviceId: deviceId,
      timeout: timeout,
    );
  }

  static Future<void> _connectAndExecuteBleCommand(
    String deviceId,
    BleCommand? bleCommand, {
    bool updateCallbackValue = false,
    Duration? timeout,
  }) async {
    var connectionState = await getConnectionState(deviceId, timeout: timeout);
    // Try to connect first
    if (connectionState != BleConnectionState.connected) {
      UniversalLogger.logInfo("Connecting to $deviceId");
      await connect(
        deviceId,
        timeout: timeout,
      );
    }

    List<BleService> services = await discoverServices(
      deviceId,
      timeout: timeout,
    );
    UniversalLogger.logInfo("Discovered services: ${services.length}");

    if (bleCommand == null) {
      // Just attempt pairing
      await _attemptPairingReadingAll(deviceId, services, timeout: timeout);
      return;
    }

    await _executeBleCommand(deviceId, services, bleCommand, timeout: timeout);
    if (updateCallbackValue) _platform.updatePairingState(deviceId, true);
  }

  // Fire and forget, and do not rely on result
  static Future<void> _attemptPairingReadingAll(
    String deviceId,
    List<BleService> services, {
    Duration? timeout,
  }) async {
    bool containsReadCharacteristics = false;
    try {
      // If BleCommand not given, fallback to reading all characteristics
      for (BleService service in services) {
        for (BleCharacteristic characteristic in service.characteristics) {
          if (characteristic.properties.contains(CharacteristicProperty.read)) {
            containsReadCharacteristics = true;
            await read(
              deviceId,
              service.uuid,
              characteristic.uuid,
              timeout: timeout ?? const Duration(seconds: 30),
            );
          }
        }
      }
    } catch (_) {}

    if (!containsReadCharacteristics) {
      throw PairingException("No readable characteristic found");
    }
  }

  static Future<void> _executeBleCommand(
    String deviceId,
    List<BleService> services,
    BleCommand bleCommand, {
    Duration? timeout,
  }) async {
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
      throw PairingException("BleCommand not found in discovered services");
    }

    // Check if BleCommand Supports Read or Write
    bool? withoutResponse;
    if (characteristic.properties.contains(CharacteristicProperty.write)) {
      withoutResponse = false;
    } else if (characteristic.properties
        .contains(CharacteristicProperty.writeWithoutResponse)) {
      withoutResponse = true;
    } else if (!characteristic.properties
        .contains(CharacteristicProperty.read)) {
      throw PairingException(
        "BleCommand does not support read or write operation",
      );
    }

    Uint8List? value = bleCommand.writeValue;

    try {
      if (value != null && withoutResponse != null) {
        await write(
          deviceId,
          bleCommand.service,
          bleCommand.characteristic,
          value,
          withoutResponse: withoutResponse,
          timeout: timeout,
        );
      } else {
        // Fallback to read if supported
        await read(
          deviceId,
          bleCommand.service,
          bleCommand.characteristic,
          timeout: timeout ?? const Duration(seconds: 30),
        );
      }
    } catch (e) {
      throw PairingException(e.toString());
    }
  }

  /// Get updates of remaining items of a queue.
  static set onQueueUpdate(OnQueueUpdate? onQueueUpdate) =>
      _bleCommandQueue.onQueueUpdate = onQueueUpdate;

  /// Get scan results.
  static set onScanResult(OnScanResult? onScanResult) =>
      _platform.onScanResult = onScanResult;

  /// Get connection state changes.
  static set onConnectionChange(OnConnectionChange? onConnectionChange) =>
      _platform.onConnectionChange = onConnectionChange;

  /// Get characteristic value updates, after calling [subscribeNotifications] or [subscribeIndications]
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
