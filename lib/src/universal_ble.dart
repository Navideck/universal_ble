import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/src/universal_ble_linux/universal_ble_linux_instance.dart';
import 'package:universal_ble/src/universal_ble_pigeon/universal_ble_pigeon_channel.dart';
import 'package:universal_ble/src/universal_ble_web/universal_ble_web.dart';
import 'package:universal_ble/src/utils/ble_command_queue.dart';
import 'package:universal_ble/src/utils/cache_handler.dart';
import 'package:universal_ble/src/utils/device_id.dart';
import 'package:universal_ble/src/utils/universal_logger.dart';
import 'package:universal_ble/universal_ble.dart';

class UniversalBle {
  /// Get platform specific implementation.
  static UniversalBlePlatform _platform = _defaultPlatform();
  static final BleCommandQueue _bleCommandQueue = BleCommandQueue(
    isAddressSupplier: () => _platform.hasAddressDeviceIds,
  );

  /// In-flight [discoverServices] calls per canonical device id.
  ///
  /// Concurrent callers that ask for the same thing share one platform command
  /// (mirroring the in-progress de-duplication CoreBluetooth already does)
  /// instead of each enqueuing their own discovery. [requestMtu] shares *any*
  /// in-flight discovery for the device because it only needs the side effect,
  /// not the result.
  static final Map<String, _PendingDiscovery> _pendingDiscoveries = {};

  /// Set custom platform specific implementation (e.g. for testing).
  static void setInstance(UniversalBlePlatform instance) =>
      _platform = instance;

  /// Set global timeout for all commands.
  /// Default timeout is 10 seconds.
  /// Set to null to disable.
  static set timeout(Duration? duration) {
    _bleCommandQueue.timeout = duration;
  }

  /// Set log level for both Dart and native implementations.
  /// Only effective in debug builds.
  static Future<void> setLogLevel(BleLogLevel logLevel) async {
    if (!kDebugMode) return;
    UniversalLogger.setLogLevel(logLevel);
    await _platform.setLogLevel(logLevel);
  }

  /// Set how commands will be executed. By default, [QueueType.auto] is used,
  /// which automatically picks the best strategy for the current platform: Android, Web
  /// and Linux use a per-device queue (their BLE stacks reject or misbehave on overlapping
  /// operations), while all other platforms run commands in parallel (they pipeline natively).
  ///
  /// [QueueType.global] will execute commands of all devices in a single queue.
  /// [QueueType.perDevice] will execute command of each device in separate queues.
  /// [QueueType.none] will execute all commands in parallel.
  static set queueType(QueueType queueType) {
    _bleCommandQueue.queueType = queueType;
    UniversalLogger.logInfo('Queue ${queueType.name}');
  }

  /// Scan Stream.
  ///
  /// When [startScan] is called with `skipDuplicates: true`, each device is
  /// reported at most once per scan session.
  static Stream<BleDevice> get scanStream => _platform.scanStream;

  /// Bluetooth availability state stream
  static Stream<AvailabilityState> get availabilityStream =>
      _platform.availabilityStream;

  /// Connection stream of a device
  static Stream<bool> connectionStream(String deviceId) =>
      _platform.connectionStream(deviceId);

  /// Connection stream of a device with the platform's error details.
  ///
  /// Emits the same events as [connectionStream], each carrying the native
  /// error message, a unified [BleConnectionChange.errorCode] and the raw
  /// [BleConnectionChange.nativeErrorCode] so the app can tell a link loss
  /// from a disconnect initiated by the peripheral.
  static Stream<BleConnectionChange> connectionChangeStream(String deviceId) =>
      _platform.connectionChangeStream(deviceId);

  /// Characteristic value stream.
  ///
  /// Emits the raw characteristic bytes for each update. The platform
  /// timestamp is not surfaced here; set [onValueChange] to receive a
  /// [BleCharacteristicValue] that also carries it.
  static Stream<Uint8List> characteristicValueStream(
    String deviceId,
    String characteristicId,
  ) =>
      _platform.characteristicValueStream(deviceId, characteristicId);

  /// Pairing state stream
  static Stream<bool> pairingStateStream(String deviceId) =>
      _platform.pairingStateStream(deviceId);

  /// Get Bluetooth availability state.
  /// To be notified of updates, set [onAvailabilityChange] listener.
  static Future<AvailabilityState> getBluetoothAvailabilityState({
    String? queueId,
  }) async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.getBluetoothAvailabilityState(),
      queueId: queueId,
    );
  }

  /// Check if has permissions.
  /// [withAndroidFineLocation] is used to check fine location permission on Android 12+ (API 31+).
  /// On Android lower than 12, this method will check location permission regardless of the [withAndroidFineLocation] value.
  /// `Windows`, `Linux` and `Web` will always return true.
  static Future<bool> hasPermissions({
    bool withAndroidFineLocation = false,
  }) async {
    return _platform.hasPermissions(
      withAndroidFineLocation: withAndroidFineLocation,
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
  ///
  /// When [skipDuplicates] is `true`, each device is reported only once per
  /// scan session: later sightings are suppressed until [stopScan] or the next
  /// [startScan], including ones whose advertisement payload changed. Where the
  /// platform has a native lever — iOS/macOS, Linux, and Android on controllers
  /// that support offloaded first-match filtering when an `AndroidOptions` is
  /// supplied — it is applied to save radio/CPU, and the
  /// Dart layer de-duplicates on every platform so the behavior is consistent
  /// everywhere. Defaults to `false`: every advertisement is reported, exactly
  /// as before.
  static Future<void> startScan({
    ScanFilter? scanFilter,
    PlatformConfig? platformConfig,
    String? queueId,
    bool skipDuplicates = false,
  }) async {
    return await _bleCommandQueue.queueCommandWithoutTimeout(
      () {
        _platform.setSkipDuplicates(skipDuplicates);
        _platform.resetScanDeduplication();
        return _platform.startScan(
          scanFilter: scanFilter,
          platformConfig: platformConfig,
        );
      },
      queueId: queueId,
    );
  }

  /// Stop scan.
  /// Set [onScanResult] listener to `null` if you don't need it anymore.
  /// It might throw errors if Bluetooth is not available.
  static Future<void> stopScan({String? queueId}) async {
    return await _bleCommandQueue.queueCommandWithoutTimeout(
      () {
        _platform.setSkipDuplicates(false);
        _platform.resetScanDeduplication();
        return _platform.stopScan();
      },
      queueId: queueId,
    );
  }

  /// Check if currently scanning for devices.
  /// Returns `true` if scanning is active, `false` otherwise.
  static Future<bool> isScanning({String? queueId}) async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.isScanning(),
      queueId: queueId,
    );
  }

  /// Presents the platform's native device picker and returns the device the
  /// user selected. Pass its `deviceId` to [connect].
  ///
  /// - **Web:** opens the browser's Bluetooth device chooser, honoring
  ///   [scanFilter] and [PickerPlatformConfig.web].
  /// - **iOS 18+:** shows the AccessorySetupKit picker, configured through
  ///   [PickerPlatformConfig.apple] ([AppleAccessorySetupOptions]). The host app
  ///   must declare matching values in `Info.plist`, and each item's image asset
  ///   must exist in the iOS asset catalog. Unlike [startScan], this flow does
  ///   not require broad Bluetooth permission.
  ///
  /// [scanFilter] only applies to Web and is ignored on iOS, where discovery is
  /// described by [AppleAccessoryPickerItem]. On Apple platforms
  /// [PickerPlatformConfig.apple] is required; omitting it throws
  /// [UniversalBleException] with code [UniversalBleErrorCode.notSupported].
  ///
  /// The picker is user-driven UI rather than a BLE command, so it runs outside
  /// the command queue and is unaffected by [timeout] or [clearQueue].
  ///
  /// On platforms without a native picker this throws [UniversalBleException]
  /// with code [UniversalBleErrorCode.notSupported].
  static Future<BleDevice> requestDevice({
    ScanFilter? scanFilter,
    PickerPlatformConfig? platformConfig,
  }) {
    return _platform.requestDevice(
      scanFilter: scanFilter,
      platformConfig: platformConfig,
    );
  }

  /// Connect to a device.
  /// It is advised to stop scanning before connecting.
  /// It throws error if device connection fails.
  /// Default connection timeout is 60 sec.
  ///
  /// [autoConnect] enables automatic reconnection when the device becomes available.
  /// Default value is `false`.
  /// Ignored on `Windows`, `Linux` and `Web`.
  ///
  /// Call [disconnect] to prevent auto-reconnect even while a device is disconnected.
  ///
  /// [platformConfig] sets platform specific connection options,
  /// e.g. [AppleConnectionOptions] to get notified of connection events
  /// while the app is suspended. Ignored on other platforms.
  ///
  /// Can throw `ConnectionException` or `PlatformException`.
  static Future<void> connect(
    String deviceId, {
    Duration? timeout,
    bool autoConnect = false,
    ConnectionPlatformConfig? platformConfig,
  }) async {
    timeout ??= const Duration(seconds: 60);
    Completer<bool> completer = _connectionEventCompleter(
      deviceId,
      timeout: timeout,
    );

    _platform
        .connect(
      deviceId,
      connectionTimeout: timeout,
      autoConnect: autoConnect,
      platformConfig: platformConfig,
    )
        .catchError((error) {
      if (completer.isCompleted) return;
      completer.completeError(ConnectionException(error));
    });

    if (!await completer.future.timeout(timeout)) {
      throw ConnectionException("Failed to connect");
    }
  }

  /// Disconnect from a device.
  /// Get notified of connection state changes in [onConnectionChange] listener.
  static Future<void> disconnect(
    String deviceId, {
    Duration? timeout,
    String? queueId,
  }) async {
    timeout ??= const Duration(seconds: 60);
    BleConnectionState? connectionState;
    try {
      connectionState = await _platform.getConnectionState(deviceId);
    } catch (e) {
      UniversalLogger.logError("Get connection state failed: $e");
    }

    try {
      Completer<bool> completer = _connectionEventCompleter(
        deviceId,
        timeout: timeout,
      );

      await _bleCommandQueue
          .queueCommand(
        () => _platform.disconnect(deviceId),
        timeout: timeout,
        deviceId: deviceId,
        queueId: queueId,
      )
          .catchError((error) {
        if (completer.isCompleted) return;
        completer.completeError(ConnectionException(error));
      });

      if (connectionState == BleConnectionState.disconnected ||
          connectionState == BleConnectionState.disconnecting) {
        // Device was already disconnected, but we still called platform disconnect
        // to prevent auto-reconnect. Update connection state and return.
        _platform.updateConnection(deviceId, false);
        UniversalLogger.logInfo(
          "Device $deviceId already disconnected: $connectionState. Cleanup performed to prevent auto-reconnect.",
        );
        return;
      }

      if (await completer.future.timeout(timeout)) {
        UniversalLogger.logError(
          "Device $deviceId is still connected after disconnect attempt",
        );
      }
    } catch (e) {
      UniversalLogger.logError("Disconnect failed: $e");
    }
  }

  /// Discover services of a device.
  /// Set [withDescriptors] to `true` to discover characteristics with descriptors.
  /// [platformConfig] carries platform-specific options, e.g.
  /// `AndroidDiscoverServicesOptions(clearGattCache: true)` to drop Android's
  /// GATT cache before discovering. Ignored where not applicable.
  ///
  /// Concurrent calls for the same device that request the same result share a
  /// single discovery and resolve together. A call that asks for something
  /// different (other [withDescriptors]/[platformConfig]) still runs its own.
  static Future<List<BleService>> discoverServices(
    String deviceId, {
    bool withDescriptors = false,
    Duration? timeout,
    String? queueId,
    DiscoverServicesPlatformConfig? platformConfig,
  }) {
    final key = canonicalDeviceId(deviceId);
    final pending = _pendingDiscoveries[key];
    if (pending != null &&
        pending.withDescriptors == withDescriptors &&
        pending.platformConfig == platformConfig) {
      return pending.future;
    }
    final future = _runDiscovery(
      deviceId,
      withDescriptors: withDescriptors,
      timeout: timeout,
      queueId: queueId,
      platformConfig: platformConfig,
    );
    _pendingDiscoveries[key] = _PendingDiscovery(
      future: future,
      withDescriptors: withDescriptors,
      platformConfig: platformConfig,
    );
    unawaited(_releaseDiscovery(key, future));
    return future;
  }

  static Future<List<BleService>> _runDiscovery(
    String deviceId, {
    required bool withDescriptors,
    Duration? timeout,
    String? queueId,
    DiscoverServicesPlatformConfig? platformConfig,
  }) async {
    final services = await _bleCommandQueue.queueCommand(
      () => _platform.discoverServices(
        deviceId,
        withDescriptors,
        platformConfig: platformConfig,
      ),
      timeout: timeout,
      deviceId: deviceId,
      queueId: queueId,
    );
    // Remember that discovery has run for this connection so requestMtu skips
    // the on-demand discovery it would otherwise perform. Cleared on disconnect.
    CacheHandler.instance.markServicesDiscovered(canonicalDeviceId(deviceId));
    return services;
  }

  /// Releases the in-flight slot for [key] once [future] settles, so a later
  /// call starts a fresh discovery. Only removes the entry if it is still the
  /// one this future registered (a newer call may have replaced it).
  static Future<void> _releaseDiscovery(
    String key,
    Future<List<BleService>> future,
  ) async {
    try {
      await future;
    } catch (_) {
      // The original caller observes the error; here we only free the slot.
    }
    if (identical(_pendingDiscoveries[key]?.future, future)) {
      _pendingDiscoveries.remove(key);
    }
  }

  /// Set a characteristic notifiable.
  /// Updates will arrive in [onValueChange] listener and [characteristicValueStream]
  /// call [unsubscribe] to stop updates
  static Future<void> subscribeNotifications(
    String deviceId,
    String service,
    String characteristic, {
    Duration? timeout,
    String? queueId,
  }) async {
    return _sendBleInputPropertyCommand(
      deviceId,
      service,
      characteristic,
      BleInputProperty.notification,
      timeout: timeout,
      queueId: queueId,
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
    String? queueId,
  }) async {
    return _sendBleInputPropertyCommand(
      deviceId,
      service,
      characteristic,
      BleInputProperty.indication,
      timeout: timeout,
      queueId: queueId,
    );
  }

  /// Stop characteristic notifications/indication updates
  static Future<void> unsubscribe(
    String deviceId,
    String service,
    String characteristic, {
    Duration? timeout,
    String? queueId,
  }) async {
    return _sendBleInputPropertyCommand(
      deviceId,
      service,
      characteristic,
      BleInputProperty.disabled,
      timeout: timeout,
      queueId: queueId,
    );
  }

  /// Returns [deviceId] in the form used for comparison and per-device state on the current
  /// platform, so device IDs can be compared with plain string equality.
  ///
  /// On native platforms (Android, iOS, macOS, Windows, Linux) a device ID is a case-insensitive
  /// Bluetooth address (a MAC, or an Apple UUID), so it is returned in lower-case. On Web a
  /// device ID is an opaque, case-sensitive browser token, so it is returned verbatim.
  ///
  /// Every API already accepts a `deviceId` in any case; use this only when you compare device
  /// IDs yourself or use one as a map key.
  static String canonicalDeviceId(String deviceId) =>
      DeviceId.of(deviceId, isAddress: _platform.hasAddressDeviceIds).canonical;

  /// Returns whether this app is currently subscribed to notifications/indications for [characteristic].
  ///
  /// Subscription state is updated when [subscribeNotifications], [subscribeIndications],
  /// or [unsubscribe] completes, and is automatically cleared when the device disconnects.
  static bool isSubscribed(String deviceId, String characteristic) =>
      CacheHandler.instance.isSubscribed(
        canonicalDeviceId(deviceId),
        characteristic,
      );

  /// Returns the list of characteristic UUIDs currently subscribed to on [deviceId].
  static List<String> getSubscribedCharacteristics(String deviceId) =>
      CacheHandler.instance.getSubscribedCharacteristics(
        canonicalDeviceId(deviceId),
      );

  /// Read a characteristic value.
  /// On iOS and MacOS this command will also trigger [onValueChange] listener.
  static Future<Uint8List> read(
    String deviceId,
    String service,
    String characteristic, {
    Duration? timeout,
    String? queueId,
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
      queueId: queueId,
    );
  }

  /// Read a characteristic descriptor value.
  static Future<Uint8List> readDescriptor(
    String deviceId,
    String service,
    String characteristic,
    String descriptor, {
    Duration? timeout,
    String? queueId,
  }) async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.readDescriptorValue(
        deviceId,
        BleUuidParser.string(service),
        BleUuidParser.string(characteristic),
        BleUuidParser.string(descriptor),
        timeout: timeout ?? _bleCommandQueue.timeout,
      ),
      timeout: timeout,
      deviceId: deviceId,
      queueId: queueId,
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
    String? queueId,
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
      queueId: queueId,
    );
  }

  /// Write a characteristic descriptor value.
  static Future<void> writeDescriptor(
    String deviceId,
    String service,
    String characteristic,
    String descriptor,
    Uint8List value, {
    Duration? timeout,
    String? queueId,
  }) async {
    await _bleCommandQueue.queueCommand(
      () => _platform.writeDescriptorValue(
        deviceId,
        BleUuidParser.string(service),
        BleUuidParser.string(characteristic),
        BleUuidParser.string(descriptor),
        value,
      ),
      timeout: timeout,
      deviceId: deviceId,
      queueId: queueId,
    );
  }

  /// Requests an MTU (Maximum Transmission Unit) value for the connection.
  ///
  /// **⚠️ Note:** Requesting an MTU is a *best-effort* operation. On many platforms
  /// the final MTU is fully controlled by the OS and remote device. This method
  /// returns the current/negotiated MTU value, which may differ from `expectedMtu`.
  ///
  /// **Platform Limitations:**
  /// * **iOS/macOS**: MTU is OS-managed; apps cannot request it (~185-517 bytes auto-negotiated)
  /// * **Android ≤13**: May request once per connection (up to 517), default is 23
  /// * **Android 14+**: First GATT client drives MTU to 517; subsequent requests ignored
  /// * **Windows/Linux**: MTU is automatically negotiated; apps can only query it
  /// * **Web**: Not supported (no API available)
  ///
  /// **Service discovery:** On iOS/macOS and Linux the reported MTU is only
  /// meaningful once the device's services have been discovered (on iOS/macOS
  /// CoreBluetooth otherwise reports the default ATT MTU, 23, as if it were the
  /// negotiated value). This method discovers them on demand, so an explicit
  /// [discoverServices] call is not required; it is a no-op when they were
  /// already discovered. The on-demand discovery is best effort: if it fails,
  /// the MTU request is still attempted.
  ///
  /// **Best Practices:** Design for default ATT MTU (23 bytes), treat requests as
  /// opportunistic, and implement fragmentation for larger payloads.
  ///
  /// **Timeout:** [timeout] bounds each step separately, so on iOS/macOS and
  /// Linux a call that has to discover the services first can take up to roughly
  /// twice [timeout] before it settles. Pass a [timeout] that accounts for both.
  ///
  /// **Concurrency:** Concurrent requests for the same device share a single
  /// negotiation. Every pending call resolves to the same negotiated value,
  /// which may differ from each caller's `expectedMtu`. Their on-demand service
  /// discovery is shared too.
  static Future<int> requestMtu(
    String deviceId,
    int expectedMtu, {
    Duration? timeout,
    String? queueId,
  }) async {
    // Discover on demand where the MTU is only meaningful once the services are
    // known (see [BleCapabilities.mtuRequiresServiceDiscovery]). This runs
    // before queueing the MTU command: discovering from inside a queued command
    // would deadlock a per-device queue. It is best effort — a discovery failure
    // must not turn a call that used to succeed into an error. Any discovery
    // already in flight for the device is shared, so concurrent callers do not
    // each trigger one.
    if (BleCapabilities.mtuRequiresServiceDiscovery &&
        !CacheHandler.instance.hasDiscoveredServices(
          canonicalDeviceId(deviceId),
        )) {
      try {
        await (_pendingDiscoveries[canonicalDeviceId(deviceId)]?.future ??
            discoverServices(deviceId, timeout: timeout, queueId: queueId));
      } catch (e) {
        UniversalLogger.logError(
          'requestMtu: on-demand discoverServices failed for $deviceId: $e',
        );
      }
    }
    return await _bleCommandQueue.queueCommand(
      () => _platform.requestMtu(deviceId, expectedMtu),
      timeout: timeout,
      deviceId: deviceId,
      queueId: queueId,
    );
  }

  /// Requests a connection parameter update for [deviceId].
  ///
  /// [priority] controls the BLE connection interval:
  /// - [BleConnectionPriority.balanced] - default OS behaviour (~30-50 ms interval).
  /// - [BleConnectionPriority.highPerformance] - low latency, higher power (~7.5-15 ms interval).
  /// - [BleConnectionPriority.lowPower] - power-optimised (~100-125 ms interval).
  ///
  /// Only supported on Android. On all other platforms this throws
  /// [UniversalBleException] with code [UniversalBleErrorCode.notSupported].
  ///
  /// Should be called after a successful connection and MTU negotiation, before
  /// beginning high-throughput data transfer.
  static Future<void> requestConnectionPriority(
    String deviceId,
    BleConnectionPriority priority, {
    Duration? timeout,
    String? queueId,
  }) async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.requestConnectionPriority(deviceId, priority),
      timeout: timeout,
      deviceId: deviceId,
      queueId: queueId,
    );
  }

  /// Read the RSSI value of a connected device.
  ///
  /// Returns the current RSSI value in dBm. This value indicates the signal strength
  /// between the device and the connected peripheral. Lower (more negative) values
  /// indicate weaker signal, while higher (less negative) values indicate stronger signal.
  ///
  /// **Note**: The device must be connected before reading RSSI.
  ///
  /// Throws [UniversalBleException] if:
  /// - The device is not connected
  /// - Reading RSSI fails
  static Future<int> readRssi(
    String deviceId, {
    Duration? timeout,
  }) =>
      _runWithTimeout(
        () => _platform.readRssi(deviceId),
        timeout: timeout,
      );

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
    String? queueId,
  }) async {
    if (BleCapabilities.hasSystemPairingApi) {
      return _bleCommandQueue.queueCommand(
        () => _platform.isPaired(deviceId),
        deviceId: deviceId,
        timeout: timeout,
        queueId: queueId,
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
        queueId: queueId,
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
  /// When not passing a pairingCommand, it reads every readable characteristic and fails if none
  /// can be read; afterwards use [isPaired] with a pairingCommand to verify the pairing state.
  ///
  /// On `Web/Windows` and `Web/Linux`, it does not work for devices that use `ConfirmOnly` pairing.
  /// Can throw `PairingException`, `ConnectionException` or `PlatformException`.
  ///
  /// On `Apple` and `Web` the outcome is also reported through [pairingStateStream] /
  /// [onPairingStateChange]: `true` when the encrypted-characteristic probe succeeds,
  /// `false` when it fails.
  static Future<void> pair(
    String deviceId, {
    BleCommand? pairingCommand,
    Duration? timeout,
    String? queueId,
  }) async {
    if (BleCapabilities.hasSystemPairingApi) {
      bool paired = await _bleCommandQueue.queueCommand(
        () => _platform.pair(deviceId),
        deviceId: deviceId,
        timeout: timeout,
        queueId: queueId,
      );
      if (!paired) throw PairingException();
    } else {
      if (pairingCommand == null) {
        UniversalLogger.logWarning("PairingCommand required to get result");
      }
      await _connectAndExecuteBleCommand(
        deviceId,
        pairingCommand,
        updateCallbackValue: true,
        timeout: timeout,
        queueId: queueId,
      );
    }
  }

  /// Unpair a device.
  /// It might throw an error if device is not paired.
  ///
  /// On `iOS 18+`, removes an accessory authorized through AccessorySetupKit;
  /// [deviceId] is the accessory's Bluetooth identifier returned by
  /// [requestDevice] (or system devices). Devices not managed by
  /// AccessorySetupKit fail with [UniversalBleErrorCode.deviceNotFound].
  static Future<void> unpair(
    String deviceId, {
    Duration? timeout,
    String? queueId,
  }) async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.unpair(deviceId),
      deviceId: deviceId,
      timeout: timeout,
      queueId: queueId,
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
    String? queueId,
  }) async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.getSystemDevices(withServices?.toValidUUIDList()),
      timeout: timeout,
      queueId: queueId,
    );
  }

  /// Returns connection state of the device.
  /// All platforms will return `Connected/Disconnected` states.
  /// `Android` and `Apple` can also return `Connecting/Disconnecting` states.
  static Future<BleConnectionState> getConnectionState(
    String deviceId, {
    Duration? timeout,
    String? queueId,
  }) async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.getConnectionState(deviceId),
      timeout: timeout,
      queueId: queueId,
    );
  }

  /// Enable Bluetooth.
  /// It might throw errors if Bluetooth is not available.
  /// Not supported on `Web` and `Apple`.
  static Future<bool> enableBluetooth({
    Duration? timeout,
    String? queueId,
  }) async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.enableBluetooth(),
      timeout: timeout,
      queueId: queueId,
    );
  }

  /// Disable Bluetooth.
  /// It might throw errors if Bluetooth is not available.
  /// Not supported on `Web` and `Apple`.
  static Future<bool> disableBluetooth({
    Duration? timeout,
    String? queueId,
  }) async {
    return await _bleCommandQueue.queueCommand(
      () => _platform.disableBluetooth(),
      timeout: timeout,
      queueId: queueId,
    );
  }

  /// Clear a queue.
  /// Use [BleCommandQueue.globalQueueId] to clear the global queue.
  /// To clear the queue of a specific device, use `deviceId` as [id] (handled case-insensitively on native platforms).
  /// To clear a custom queue, pass the same `queueId` string used when enqueueing commands (matched exactly, unless the id is a device address, which is matched case-insensitively).
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
    "Use [subscribeNotifications] or [subscribeIndications] or [unsubscribe] instead",
  )
  static Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty, {
    String? queueId,
  }) async {
    return _sendBleInputPropertyCommand(
      deviceId,
      service,
      characteristic,
      bleInputProperty,
      queueId: queueId,
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
    Duration? timeout,
  }) {
    return read(deviceId, service, characteristic, timeout: timeout);
  }

  static Completer<bool> _connectionEventCompleter(
    String deviceId, {
    Duration? timeout,
  }) {
    timeout ??= const Duration(seconds: 60);
    final target = canonicalDeviceId(deviceId);
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
        .bleConnectionChangeStreamController.stream
        .where((e) => e.deviceId == target)
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
    String? queueId,
  }) async {
    await _bleCommandQueue.queueCommand(
      () => _platform.setNotifiable(
        deviceId,
        BleUuidParser.string(service),
        BleUuidParser.string(characteristic),
        bleInputProperty,
      ),
      deviceId: deviceId,
      timeout: timeout,
      queueId: queueId,
    );
    CacheHandler.instance.updateSubscription(
      canonicalDeviceId(deviceId),
      characteristic,
      bleInputProperty != BleInputProperty.disabled,
    );
  }

  /// Connects (if needed), discovers services and runs a pairing probe: either
  /// [bleCommand] on an encrypted characteristic, or a read of every readable
  /// characteristic when none is given.
  ///
  /// [updateCallbackValue] reports the probe outcome as a pairing state change:
  /// [UniversalBlePlatform.updatePairingState] on success,
  /// [UniversalBlePlatform.updatePairingFailure] on failure. [pair] enables it on
  /// the platforms without a system pairing API (Apple/Web), where this probe is
  /// the only signal that the OS paired the device. [isPaired] runs the same probe
  /// as a query and leaves it `false`, so checking the state does not emit.
  ///
  /// Only the probe itself is reported; a failure to connect or discover services
  /// happens before it and propagates without emitting a pairing state.
  static Future<void> _connectAndExecuteBleCommand(
    String deviceId,
    BleCommand? bleCommand, {
    bool updateCallbackValue = false,
    Duration? timeout,
    String? queueId,
  }) async {
    var connectionState = await getConnectionState(
      deviceId,
      timeout: timeout,
      queueId: queueId,
    );
    // Try to connect first
    if (connectionState != BleConnectionState.connected) {
      UniversalLogger.logInfo("Connecting to $deviceId");
      await connect(deviceId, timeout: timeout);
    }

    List<BleService> services = await discoverServices(
      deviceId,
      timeout: timeout,
      queueId: queueId,
    );
    UniversalLogger.logInfo("Discovered services: ${services.length}");

    try {
      if (bleCommand == null) {
        // Just attempt pairing
        final probeSucceeded = await _attemptPairingReadingAll(
          deviceId,
          services,
          timeout: timeout,
          queueId: queueId,
        );
        if (!probeSucceeded) {
          throw PairingException("No readable characteristic could be read");
        }
      } else {
        await _executeBleCommand(
          deviceId,
          services,
          bleCommand,
          timeout: timeout,
          queueId: queueId,
        );
      }
    } catch (_) {
      // A failed bond is an event, not a state: report it before surfacing the
      // error, matching the native platforms' onPairStateChange(isFailure: true).
      if (updateCallbackValue) _platform.updatePairingFailure(deviceId);
      rethrow;
    }

    // The probe completed, so the OS paired the device. Apple/Web have no native
    // bond-state API, which is why this is the only pairing-state signal there.
    if (updateCallbackValue) _platform.updatePairingState(deviceId, true);
  }

  /// Reads every readable characteristic to trigger pairing, since Apple/Web pair
  /// the device when an encrypted characteristic is accessed.
  ///
  /// Returns `true` when at least one read succeeded and `false` when reads were
  /// attempted but all failed, so a probe can be reported as a pairing outcome.
  /// Individual read failures are ignored, so one unreachable characteristic does
  /// not stop the others from being tried. Throws [PairingException] when the
  /// device exposes no readable characteristic to probe.
  static Future<bool> _attemptPairingReadingAll(
    String deviceId,
    List<BleService> services, {
    Duration? timeout,
    String? queueId,
  }) async {
    bool containsReadCharacteristics = false;
    bool readSucceeded = false;

    // If BleCommand not given, fallback to reading all characteristics
    for (BleService service in services) {
      for (BleCharacteristic characteristic in service.characteristics) {
        if (characteristic.properties.contains(CharacteristicProperty.read)) {
          containsReadCharacteristics = true;
          try {
            await read(
              deviceId,
              service.uuid,
              characteristic.uuid,
              timeout: timeout ?? const Duration(seconds: 30),
              queueId: queueId,
            );
            readSucceeded = true;
          } catch (_) {}
        }
      }
    }

    if (!containsReadCharacteristics) {
      throw PairingException("No readable characteristic found");
    }

    return readSucceeded;
  }

  static Future<void> _executeBleCommand(
    String deviceId,
    List<BleService> services,
    BleCommand bleCommand, {
    Duration? timeout,
    String? queueId,
  }) async {
    // First find BleCommand's characteristic
    BleCharacteristic? characteristic;
    for (BleService service in services) {
      if (BleUuidParser.compareStrings(service.uuid, bleCommand.service)) {
        for (BleCharacteristic char in service.characteristics) {
          if (BleUuidParser.compareStrings(
            char.uuid,
            bleCommand.characteristic,
          )) {
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
    } else if (characteristic.properties.contains(
      CharacteristicProperty.writeWithoutResponse,
    )) {
      withoutResponse = true;
    } else if (!characteristic.properties.contains(
      CharacteristicProperty.read,
    )) {
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
          queueId: queueId,
        );
      } else {
        // Fallback to read if supported
        await read(
          deviceId,
          bleCommand.service,
          bleCommand.characteristic,
          timeout: timeout ?? const Duration(seconds: 30),
          queueId: queueId,
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
  ///
  /// When [startScan] is called with `skipDuplicates: true`, each device is
  /// reported at most once per scan session.
  static set onScanResult(OnScanResult? onScanResult) =>
      _platform.onScanResultUpdate = onScanResult;

  /// Get connection state changes of all devices as [BleConnectionChange],
  /// with the platform's error message, a unified
  /// [BleConnectionChange.errorCode] and the raw
  /// [BleConnectionChange.nativeErrorCode].
  static set onConnectionChange(OnConnectionChange? onConnectionChange) =>
      _platform.onConnectionChange = onConnectionChange;

  /// Get characteristic value updates, after calling [subscribeNotifications] or [subscribeIndications]
  static set onValueChange(OnValueChange? onValueChange) =>
      _platform.onValueChange = onValueChange;

  /// Get pair state changes.
  static set onPairingStateChange(OnPairingStateChange pairingStateChange) =>
      _platform.onPairingStateChange = pairingStateChange;

  /// Connection parameter updates (Android API 26+).
  static set onConnectionParametersChange(
    OnConnectionParametersChange? onConnectionParametersChange,
  ) =>
      _platform.onConnectionParametersChange = onConnectionParametersChange;

  static UniversalBlePlatform _defaultPlatform() {
    if (kIsWeb) return UniversalBleWeb.instance;
    if (defaultTargetPlatform == TargetPlatform.linux) {
      return universalBleLinuxInstance;
    }
    return UniversalBlePigeonChannel.instance;
  }

  static Future<T> _runWithTimeout<T>(
    Future<T> Function() action, {
    Duration? timeout,
  }) {
    final timeoutDuration = timeout ?? _bleCommandQueue.timeout;
    return timeoutDuration != null
        ? action().timeout(timeoutDuration)
        : action();
  }
}

/// A [UniversalBle.discoverServices] call currently in flight, plus the
/// parameters it was started with so later concurrent callers can decide
/// whether they can share its result.
class _PendingDiscovery {
  _PendingDiscovery({
    required this.future,
    required this.withDescriptors,
    required this.platformConfig,
  });

  final Future<List<BleService>> future;
  final bool withDescriptors;
  final DiscoverServicesPlatformConfig? platformConfig;
}
