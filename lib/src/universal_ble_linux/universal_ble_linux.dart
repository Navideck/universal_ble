import 'dart:async';
import 'dart:typed_data';

import 'package:bluez/bluez.dart';
import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:universal_ble/src/models/model_exports.dart';
import 'package:universal_ble/src/universal_ble_platform_interface.dart';

class UniversalBleLinux extends UniversalBlePlatform {
  UniversalBleLinux._();
  static UniversalBleLinux? _instance;
  static UniversalBleLinux get instance => _instance ??= UniversalBleLinux._();

  bool isInitialized = false;

  final BlueZClient _client = BlueZClient();

  BlueZAdapter? _activeAdapter;
  Completer<void>? _initializationCompleter;
  final Map<String, BlueZDevice> _devices = {};
  final Map<String, StreamSubscription> _deviceStreamSubscriptions = {};
  final Map<String, StreamSubscription> _characteristicPropertiesSubscriptions =
      {};

  @override
  Future<AvailabilityState> getBluetoothAvailabilityState() async {
    await _ensureInitialized();

    BlueZAdapter? adapter = _activeAdapter;
    if (adapter == null) {
      return AvailabilityState.unsupported;
    }
    return adapter.powered
        ? AvailabilityState.poweredOn
        : AvailabilityState.poweredOff;
  }

  @override
  Future<bool> enableBluetooth() async {
    await _ensureInitialized();
    if (_activeAdapter?.powered == true) return true;
    try {
      await _activeAdapter?.setPowered(true);
      return _activeAdapter?.powered ?? false;
    } catch (e) {
      UniversalBlePlatform.logInfo(
        'Error enabling bluetooth: $e',
        isError: true,
      );
      return false;
    }
  }

  @override
  Future<void> startScan({
    WebRequestOptionsBuilder? webRequestOptions,
    ScanFilter? scanFilter,
  }) async {
    await _ensureInitialized();
    if (_activeAdapter?.discovering != true) {
      // Add services filter
      _activeAdapter?.setDiscoveryFilter(
        uuids: scanFilter?.withServices.toValidUUIDList(),
      );
      await _activeAdapter?.startDiscovery();
      _client.devices.forEach(_onDeviceAdd);
    }
  }

  @override
  Future<void> stopScan() async {
    await _ensureInitialized();
    try {
      if (_activeAdapter?.discovering == true) {
        await _activeAdapter?.stopDiscovery();
      }
    } catch (e) {
      UniversalBlePlatform.logInfo(
        "stopScan error: $e",
        isError: true,
      );
    }
  }

  @override
  Future<void> connect(String deviceId, {Duration? connectionTimeout}) async {
    var device = _findDeviceById(deviceId);
    if (device.connected) {
      onConnectionChanged?.call(deviceId, BleConnectionState.connected);
      return;
    }
    await device.connect();
  }

  @override
  Future<void> disconnect(String deviceId) async {
    var device = _findDeviceById(deviceId);
    if (!device.connected) {
      onConnectionChanged?.call(deviceId, BleConnectionState.disconnected);
      return;
    }
    await device.disconnect();
  }

  @override
  Future<List<BleService>> discoverServices(String deviceId) async {
    var device = _findDeviceById(deviceId);
    if (!device.servicesResolved) {
      await device.propertiesChanged
          .firstWhere(
              (element) => element.contains(BluezProperty.servicesResolved))
          .timeout(const Duration(seconds: 2), onTimeout: () => []);
    }

    // while (!device.servicesResolved) {
    //   await Future.delayed(const Duration(seconds: 200));
    // }

    List<BleService> services = [];
    for (var service in device.gattServices) {
      var characteristics = service.characteristics.map((e) {
        var properties = List<CharacteristicProperty>.from(e.flags
            .map((e) => e.toCharacteristicProperty())
            .where((element) => element != null)
            .toList());
        return BleCharacteristic(e.uuid.toString(), properties);
      }).toList();
      services.add(BleService(service.uuid.toString(), characteristics));
    }
    return services;
  }

  BlueZGattCharacteristic _getCharacteristic(
      String deviceId, String service, String characteristic) {
    var device = _findDeviceById(deviceId);
    var s = device.gattServices
        .firstWhereOrNull((s) => s.uuid.toString() == service);
    var c = s?.characteristics
        .firstWhereOrNull((c) => c.uuid.toString() == characteristic);

    if (c == null) {
      throw Exception('Unknown characteristic:$characteristic');
    }
    return c;
  }

  @override
  Future<void> setNotifiable(String deviceId, String service,
      String characteristic, BleInputProperty bleInputProperty) async {
    var char = _getCharacteristic(deviceId, service, characteristic);
    if (bleInputProperty != BleInputProperty.disabled) {
      if (char.notifying) throw Exception('Characteristic already notifying');

      await char.startNotify();

      if (_characteristicPropertiesSubscriptions[characteristic] != null) {
        _characteristicPropertiesSubscriptions[characteristic]?.cancel();
      }

      _characteristicPropertiesSubscriptions[characteristic] =
          char.propertiesChanged.listen((List<String> properties) {
        for (String property in properties) {
          switch (property) {
            case BluezProperty.value:
              onValueChanged?.call(
                deviceId,
                characteristic,
                Uint8List.fromList(char.value),
              );
              break;
            default:
              UniversalBlePlatform.logInfo(
                  "UnhandledCharValuePropertyChange: $property");
          }
        }
      });
    } else {
      if (!char.notifying) throw Exception('Characteristic not notifying');
      await char.stopNotify();
      _characteristicPropertiesSubscriptions.remove(characteristic)?.cancel();
    }
  }

  @override
  Future<Uint8List> readValue(
      String deviceId, String service, String characteristic) async {
    try {
      var c = _getCharacteristic(deviceId, service, characteristic);
      var data = await c.readValue();
      return Uint8List.fromList(data);
    } on BlueZFailedException catch (e) {
      throw PlatformException(
        code: e.errorCode ?? "ReadFailed",
        message: e.message,
      );
    }
  }

  @override
  Future<void> writeValue(
      String deviceId,
      String service,
      String characteristic,
      Uint8List value,
      BleOutputProperty bleOutputProperty) async {
    try {
      var c = _getCharacteristic(deviceId, service, characteristic);
      if (bleOutputProperty == BleOutputProperty.withResponse) {
        await c.writeValue(
          value,
          type: BlueZGattCharacteristicWriteType.request,
        );
      } else {
        await c.writeValue(
          value,
          type: BlueZGattCharacteristicWriteType.command,
        );
      }
    } on BlueZFailedException catch (e) {
      throw PlatformException(
        code: e.errorCode ?? "WriteFailed",
        message: e.message,
      );
    }
  }

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) async {
    var device = _findDeviceById(deviceId);
    if (!device.connected) throw Exception('Device not connected');
    for (BlueZGattService service in device.gattServices) {
      for (BlueZGattCharacteristic characteristic in service.characteristics) {
        int? mtu = characteristic.mtu;
        // The value provided by Bluez includes an extra 3 bytes from the GATT header, which needs to be removed.
        if (mtu != null) return mtu - 3;
      }
    }
    throw Exception('MTU not available');
  }

  @override
  Future<void> pair(String deviceId) async {
    BlueZDevice device = _findDeviceById(deviceId);
    device.pair().onError((error, _) {
      onPairingStateChange?.call(deviceId, false, error.toString());
    });
  }

  @override
  Future<void> unPair(String deviceId) async {
    BlueZDevice device = _findDeviceById(deviceId);
    if (device.paired) {
      // await device.cancelPairing();
      await _activeAdapter?.removeDevice(device);
    }
  }

  @override
  Future<bool> isPaired(String deviceId) async {
    return _findDeviceById(deviceId).paired;
  }

  @override
  Future<List<BleScanResult>> getConnectedDevices(
    List<String>? withServices,
  ) async {
    List<BlueZDevice> devices =
        _client.devices.where((device) => device.connected).toList();
    if (withServices != null && withServices.isNotEmpty) {
      devices = devices.where((device) {
        if (device.servicesResolved) {
          return device.gattServices
              .map((e) => e.uuid.toString())
              .any((service) => withServices.contains(service));
        } else {
          UniversalBlePlatform.logInfo(
              'Skipping: ${device.address}: Services not resolved yet.');
          return false;
        }
      }).toList();
    }
    return devices.map((device) => device.toBleScanResult()).toList();
  }

  AvailabilityState get _availabilityState {
    return _activeAdapter?.powered == true
        ? AvailabilityState.poweredOn
        : AvailabilityState.poweredOff;
  }

  BlueZDevice _findDeviceById(String deviceId) {
    var device = _devices[deviceId] ??
        _client.devices
            .firstWhereOrNull((device) => device.address == deviceId);
    if (device == null) {
      throw Exception('Unknown deviceId:$deviceId');
    }
    return device;
  }

  Future<void> _ensureInitialized() async {
    if (isInitialized) return;

    if (_initializationCompleter != null) {
      await _initializationCompleter?.future;
      return;
    }

    _initializationCompleter = Completer<void>();
    try {
      await _client.connect();
      await _waitForAdapter(_client);

      _activeAdapter ??= _client.adapters.first;

      UniversalBlePlatform.logInfo(
        'BleAdapter: ${_activeAdapter?.name} - ${_activeAdapter?.address}',
      );

      _activeAdapter?.propertiesChanged.listen((List<String> properties) {
        // Handle pairing state change
        for (var property in properties) {
          switch (property) {
            case BluezProperty.powered:
              onAvailabilityChange?.call(_availabilityState);
              break;
            case BluezProperty.discoverable:
            case BluezProperty.discovering:
              //  print("Adapter Discovering: ${_activeAdapter?.discovering}");
              break;
            case BluezProperty.propertyClass:
            default:
              UniversalBlePlatform.logInfo(
                "UnhandledPropertyChanged: $property",
              );
          }
        }
      });

      _client.deviceAdded.listen(_onDeviceAdd);
      _client.deviceRemoved.listen(_onDeviceRemoved);

      onAvailabilityChange?.call(_availabilityState);
      isInitialized = true;
      _initializationCompleter?.complete();
      _initializationCompleter = null;
    } catch (e) {
      UniversalBlePlatform.logInfo(
        'Error initializing: $e',
        isError: true,
      );
      _initializationCompleter?.completeError(e);
      await _client.close();
      rethrow;
    }
  }

  Future<void> _waitForAdapter(BlueZClient client) async {
    if (client.adapters.isNotEmpty) return;

    int attempts = 0;
    while (attempts < 10 && client.adapters.isEmpty) {
      await Future.delayed(const Duration(milliseconds: 100));
      attempts++;
    }

    if (client.adapters.isEmpty) {
      throw Exception('Bluetooth adapter unavailable');
    }
  }

  void _onDeviceAdd(BlueZDevice device) {
    // Update scan results only if rssi is available
    if (device.rssi != 0) onScanResult?.call(device.toBleScanResult());

    // Setup Cache
    _devices[device.address] = device;

    // Setup update listener
    if (_deviceStreamSubscriptions[device.address] != null) {
      _deviceStreamSubscriptions[device.address]?.cancel();
    }

    _deviceStreamSubscriptions[device.address] =
        device.propertiesChanged.listen((properties) {
      for (var property in properties) {
        switch (property) {
          case BluezProperty.rssi:
            onScanResult?.call(device.toBleScanResult());
            break;
          case BluezProperty.connected:
            onConnectionChanged?.call(
              device.address,
              device.connected
                  ? BleConnectionState.connected
                  : BleConnectionState.disconnected,
            );
            break;
          case BluezProperty.manufacturerData:
            onScanResult?.call(device.toBleScanResult());
            break;
          case BluezProperty.paired:
            onPairingStateChange?.call(device.address, device.paired, null);
            break;
          // Ignored these properties updates
          case BluezProperty.bonded:
          case BluezProperty.legacyPairing:
          case BluezProperty.servicesResolved:
          case BluezProperty.uuids:
          case BluezProperty.txPower:
          case BluezProperty.address:
          case BluezProperty.addressType:
            break;
          default:
            UniversalBlePlatform.logInfo(
                "UnhandledDevicePropertyChanged ${device.name} ${device.address}: $property");
            break;
        }
      }
    });
  }

  void _onDeviceRemoved(BlueZDevice device) {
    _devices.remove(device.address);
    // Stop listener
    _deviceStreamSubscriptions[device.address]?.cancel();
    _deviceStreamSubscriptions
        .removeWhere((key, value) => key == device.address);
  }
}

class BluezProperty {
  static const String rssi = 'RSSI';
  static const String connected = 'Connected';
  static const String txPower = 'TxPower';
  static const String bonded = 'Bonded';
  static const String manufacturerData = 'ManufacturerData';
  static const String legacyPairing = 'LegacyPairing';
  static const String servicesResolved = 'ServicesResolved';
  static const String paired = 'Paired';
  static const String address = 'Address';
  static const String addressType = 'AddressType';
  static const String modalias = 'Modalias';
  static const String uuids = 'UUIDs';
  static const String value = 'Value';
  static const String powered = 'Powered';
  static const String discoverable = 'Discoverable';
  static const String discovering = 'Discovering';
  static const String propertyClass = 'Class';
}

extension BlueZDeviceExtension on BlueZDevice {
  Uint8List get manufacturerDataHead {
    try {
      if (manufacturerData.isEmpty) return Uint8List(0);
      final sorted = manufacturerData.entries.toList()
        ..sort((a, b) => a.key.id - b.key.id);
      int companyId = sorted.first.key.id;
      List<int> manufacturerDataValue = sorted.first.value;
      var byteData = ByteData(2);
      // TODO: Verify that this works regardless of the endianess
      byteData.setInt16(0, companyId, Endian.host);
      List<int> bytes = byteData.buffer.asUint8List();
      return Uint8List.fromList(bytes + manufacturerDataValue);
    } catch (e) {
      UniversalBlePlatform.logInfo(
        'Error parsing manufacturerData: $e',
        isError: true,
      );
      return Uint8List(0);
    }
  }

  BleScanResult toBleScanResult() {
    return BleScanResult(
      name: alias,
      deviceId: address,
      isPaired: paired,
      manufacturerData: manufacturerDataHead,
      manufacturerDataHead: manufacturerDataHead,
      rssi: rssi,
      services: uuids.map((e) => e.toString()).toList(),
    );
  }
}

extension on BlueZGattCharacteristicFlag {
  CharacteristicProperty? toCharacteristicProperty() {
    return switch (this) {
      BlueZGattCharacteristicFlag.broadcast => CharacteristicProperty.broadcast,
      BlueZGattCharacteristicFlag.read => CharacteristicProperty.read,
      BlueZGattCharacteristicFlag.writeWithoutResponse =>
        CharacteristicProperty.writeWithoutResponse,
      BlueZGattCharacteristicFlag.write => CharacteristicProperty.write,
      BlueZGattCharacteristicFlag.notify => CharacteristicProperty.notify,
      BlueZGattCharacteristicFlag.indicate => CharacteristicProperty.indicate,
      BlueZGattCharacteristicFlag.authenticatedSignedWrites =>
        CharacteristicProperty.authenticatedSignedWrites,
      BlueZGattCharacteristicFlag.extendedProperties =>
        CharacteristicProperty.extendedProperties,
      _ => null,
    };
  }
}

extension on BlueZFailedException {
  /// Extract error code from message and parse into decimal
  /// example: 'Operation failed with ATT error: 0x90' => 144
  String? get errorCode {
    try {
      RegExp regExp = RegExp(r'0x\w+');
      Match? match = regExp.firstMatch(message);
      String? code = match?.group(0);
      if (code == null) return null;
      int? decimalValue = int.tryParse(
        code.replaceFirst('0x', ''),
        radix: 16,
      );
      return decimalValue?.toString() ?? code;
    } catch (e) {
      return null;
    }
  }
}
