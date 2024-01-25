import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/src/universal_ble_linux/universal_ble_linux.dart';
import 'package:universal_ble/src/universal_ble_pigeon/universal_ble_pigeon_channel.dart';
import 'package:universal_ble/src/universal_ble_web/universal_ble_web.dart';
import 'package:universal_ble/universal_ble.dart';

class UniversalBle {
  /// Get platform specific implementation
  static UniversalBlePlatform _platform = _defaultPlatform();

  /// Set custom platform specific implementation (e.g. for testing)
  static void setInstance(UniversalBlePlatform instance) =>
      _platform = instance;

  /// To get Bluetooth state availability
  /// To get updates, set [onAvailabilityChange] listener
  static Future<AvailabilityState> getBluetoothAvailabilityState() async {
    return await _platform.getBluetoothAvailabilityState();
  }

  /// To Start scan, get scan results in [onScanResult] listener
  /// might throw errors if Bluetooth is not available
  /// `webRequestOptions` supported on Web only
  static Future<void> startScan({
    WebRequestOptionsBuilder? webRequestOptions,
  }) async {
    await _platform.startScan(webRequestOptions: webRequestOptions);
  }

  /// To Stop scan, set [onScanResult] listener to `null` if you don't need it anymore
  /// might throw errors if Bluetooth is not available
  static Future<void> stopScan() async {
    await _platform.stopScan();
  }

  /// To connect to a device, get connection state in [onConnectionChanged] listener
  /// preferred to stop scan before connecting
  /// might throw errors if device is not connectable
  /// `connectionTimeout` supported on Web only
  static Future<void> connect(
    String deviceId, {
    Duration? connectionTimeout,
  }) async {
    await _platform.connect(deviceId, connectionTimeout: connectionTimeout);
  }

  /// To disconnect from a device, get connection state in [onConnectionChanged] listener
  static Future<void> disconnect(String deviceId) async {
    await _platform.disconnect(deviceId);
  }

  /// To discover services of a device
  static Future<List<BleService>> discoverServices(String deviceId) async {
    return await _platform.discoverServices(deviceId);
  }

  /// To set a characteristic notifiable, set `bleInputProperty` to [BleInputProperty.notification] or [BleInputProperty.indication], get updates in [onValueChanged] listener
  /// To stop listening to a characteristic, set `bleInputProperty` to [BleInputProperty.disabled]
  static Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) async {
    await _platform.setNotifiable(
      deviceId,
      service,
      characteristic,
      bleInputProperty,
    );
  }

  /// To read a characteristic value
  /// on iOS and MacOS, this method will also trigger [onValueChanged] listener
  static Future<Uint8List> readValue(
    String deviceId,
    String service,
    String characteristic,
  ) async {
    return await _platform.readValue(deviceId, service, characteristic);
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
    await _platform.writeValue(
      deviceId,
      service,
      characteristic,
      value,
      bleOutputProperty,
    );
  }

  /// `requestMtu` not supported on `Linux` and `Web
  static Future<int> requestMtu(String deviceId, int expectedMtu) async {
    return await _platform.requestMtu(deviceId, expectedMtu);
  }

  /// Pair methods are not supported on `iOS`, `MacOS` and `Web`
  static Future<bool> isPaired(String deviceId) async {
    return await _platform.isPaired(deviceId);
  }

  /// To trigger pair request, might throw errors if device is already paired
  static Future<void> pair(String deviceId) async {
    await _platform.pair(deviceId);
  }

  /// To trigger unPair request, might throw errors if device is not paired
  static Future<void> unPair(String deviceId) async {
    await _platform.unPair(deviceId);
  }

  /// To get connected devices to the system ( connected by any app )
  /// use [withServices] to filter devices by services
  /// on `iOS`, `MacOS` [withServices] is required to get connected devices, else [1800] service will be used as default filter
  /// on `Android`, `Linux` and `Windows`, if [withServices] is used, then internally all services will be discovered for each device first (either by connecting or by using cached services)
  /// Not supported on `Web`
  static Future<List<BleScanResult>> getConnectedDevices({
    List<String>? withServices,
  }) async {
    return await _platform.getConnectedDevices(withServices);
  }

  /// Enabling Bluetooth, might throw errors if Bluetooth is not available
  /// Not supported on `Web` and `Apple`
  static Future<bool> enableBluetooth() async {
    return await _platform.enableBluetooth();
  }

  /// To get Bluetooth state availability
  static set onAvailabilityChange(OnAvailabilityChange? onAvailabilityChange) =>
      _platform.onAvailabilityChange = onAvailabilityChange;

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
    if (Platform.isLinux) return UniversalBleLinux.instance;
    return UniversalBlePigeonChannel.instance;
  }
}

// Callback types
typedef OnConnectionChanged = void Function(
    String deviceId, BleConnectionState state);

typedef OnValueChanged = void Function(
    String deviceId, String characteristicId, Uint8List value);

typedef OnScanResult = void Function(BleScanResult scanResult);

typedef OnAvailabilityChange = void Function(AvailabilityState state);

typedef OnPairingStateChange = void Function(
    String deviceId, bool isPaired, String? error);
