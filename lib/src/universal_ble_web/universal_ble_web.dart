import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter_web_bluetooth/flutter_web_bluetooth.dart';
import 'package:universal_ble/src/models/model_exports.dart';
import 'package:universal_ble/src/universal_ble_platform_interface.dart';

class UniversalBleWeb extends UniversalBlePlatform {
  static UniversalBleWeb? _instance;
  static UniversalBleWeb get instance => _instance ??= UniversalBleWeb._();

  UniversalBleWeb._() {
    _setupListeners();
  }

  final Map<String, BluetoothDevice> _bluetoothDeviceList = {};
  final Map<String, StreamSubscription> _deviceAdvertisementStreamList = {};
  final Map<String, StreamSubscription> _connectedDeviceStreamList = {};
  final Map<String, StreamSubscription> _characteristicStreamList = {};

  @override
  Future<BleConnectionState> getConnectionState(String deviceId) async {
    BluetoothDevice? device = _getDeviceById(deviceId);
    bool connected = await device?.connected.first ?? false;
    return connected
        ? BleConnectionState.connected
        : BleConnectionState.disconnected;
  }

  @override
  Future<void> connect(
    String deviceId, {
    Duration? connectionTimeout = const Duration(seconds: 10),
  }) async {
    var device = _getDeviceById(deviceId);
    if (device == null) throw "$deviceId Not Found";
    await device.connect(timeout: connectionTimeout);

    // Subscribe to Connection Stream
    if (_connectedDeviceStreamList[deviceId] != null) {
      _connectedDeviceStreamList[deviceId]?.cancel();
    }

    _connectedDeviceStreamList[deviceId] = device.connected.listen((event) {
      if (!event) _cleanConnection(deviceId);
      onConnectionChange?.call(deviceId, event);
    });
  }

  @override
  Future<void> disconnect(String deviceId) async {
    _cleanConnection(deviceId);
    onConnectionChange?.call(deviceId, false);
    _getDeviceById(deviceId)?.disconnect();
  }

  @override
  Future<List<BleService>> discoverServices(String deviceId) async {
    final device = _getDeviceById(deviceId);
    final services = await device?.discoverServices();
    if (services == null) return [];
    var discoveredServices = <BleService>[];
    for (var service in services) {
      final characteristics = await service.getCharacteristics();
      List<BleCharacteristic> bleCharacteristics = [];
      for (BluetoothCharacteristic characteristic in characteristics) {
        List<CharacteristicProperty> properties = [];
        if (characteristic.properties.broadcast) {
          properties.add(CharacteristicProperty.broadcast);
        }
        if (characteristic.properties.read) {
          properties.add(CharacteristicProperty.read);
        }
        if (characteristic.properties.writeWithoutResponse) {
          properties.add(CharacteristicProperty.writeWithoutResponse);
        }
        if (characteristic.properties.write) {
          properties.add(CharacteristicProperty.write);
        }
        if (characteristic.properties.notify) {
          properties.add(CharacteristicProperty.notify);
        }
        if (characteristic.properties.indicate) {
          properties.add(CharacteristicProperty.indicate);
        }
        if (characteristic.properties.authenticatedSignedWrites) {
          properties.add(CharacteristicProperty.authenticatedSignedWrites);
        }
        bleCharacteristics.add(
          BleCharacteristic(characteristic.uuid.toString(), properties),
        );
      }
      discoveredServices.add(
        BleService(service.uuid.toString(), bleCharacteristics),
      );
    }
    return discoveredServices;
  }

  @override
  Future<AvailabilityState> getBluetoothAvailabilityState() async {
    bool isSupported = FlutterWebBluetooth.instance.isBluetoothApiSupported;
    if (!isSupported) {
      return AvailabilityState.unsupported;
    }
    bool isAvailable = await FlutterWebBluetooth.instance.isAvailable.first;
    if (isSupported && !isAvailable) {
      return AvailabilityState.poweredOff;
    } else if (isAvailable) {
      return AvailabilityState.poweredOn;
    }
    return AvailabilityState.unknown;
  }

  @override
  Future<void> startScan({
    ScanFilter? scanFilter,
  }) async {
    if (scanFilter == null || scanFilter.withServices.isEmpty) {
      UniversalBlePlatform.logInfo(
        "Service list empty: on web you have to specify services in the ScanFilter in order to be able to access those after connecting",
        isError: true,
      );
    }

    BluetoothDevice device = await FlutterWebBluetooth.instance.requestDevice(
      scanFilter?.toRequestOptionsBuilder() ??
          RequestOptionsBuilder.acceptAllDevices(),
    );

    // Update local device list
    _bluetoothDeviceList[device.id] = device;

    // Update Scan Result
    updateScanResult(device.toBleScanResult());

    _watchDeviceAdvertisements(device);
  }

  @override
  bool canWatchAdvertisements(String deviceId) =>
      _getDeviceById(deviceId)?.hasWatchAdvertisements() ?? false;

  /// This will work only if `chrome://flags/#enable-experimental-web-platform-features` is enabled
  Future<void> _watchDeviceAdvertisements(BluetoothDevice device) async {
    try {
      if (!device.hasWatchAdvertisements()) return;

      if (_deviceAdvertisementStreamList[device.id] != null) {
        _deviceAdvertisementStreamList[device.id]?.cancel();
        await device.unwatchAdvertisements();
      }

      _deviceAdvertisementStreamList[device.id] =
          device.advertisements.listen((event) {
        updateScanResult(
          device.toBleScanResult(
            rssi: event.rssi,
            manufacturerDataMap: event.manufacturerData,
            services: event.uuids,
          ),
        );
      });
      device.advertisementsUseMemory = true;
      await device.watchAdvertisements();
    } catch (e) {
      UniversalBlePlatform.logInfo(
        "WebWatchAdvertisementError: $e",
        isError: true,
      );
    }
  }

  @override
  Future<void> stopScan() async {
    try {
      // Cancel advertisement streams
      if (FlutterWebBluetooth.instance.hasRequestLEScan) {
        _deviceAdvertisementStreamList.removeWhere((key, value) {
          value.cancel();
          return true;
        });

        for (var element in _bluetoothDeviceList.entries) {
          if (element.value.hasWatchAdvertisements()) {
            await element.value.unwatchAdvertisements();
          }
        }
      }
    } catch (e) {
      UniversalBlePlatform.logInfo(
        "WebStopScanError: $e",
        isError: true,
      );
    }
  }

  @override
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) async {
    final bleCharacteristic = await _getBleCharacteristic(
      deviceId: deviceId,
      serviceId: service,
      characteristicId: characteristic,
    );

    if (bleCharacteristic == null) {
      throw Exception(
        'Characteristic $characteristic for service $service not found',
      );
    }

    String characteristicKey = "${deviceId}_${service}_$characteristic";

    if (bleInputProperty == BleInputProperty.notification ||
        bleInputProperty == BleInputProperty.indication) {
      if (bleCharacteristic.isNotifying) {
        throw Exception("Already listening to this characteristic");
      }

      if (_characteristicStreamList[characteristicKey] != null) {
        _characteristicStreamList[characteristicKey]?.cancel();
      }

      await bleCharacteristic.startNotifications();

      _characteristicStreamList[characteristicKey] = bleCharacteristic.value
          .map((event) => event.buffer.asUint8List())
          .listen((event) {
        updateCharacteristicValue(deviceId, characteristic, event);
      });
    }
    // Cancel Notification
    else if (bleInputProperty == BleInputProperty.disabled) {
      await bleCharacteristic.stopNotifications();
      _characteristicStreamList.removeWhere((key, value) {
        if (key == characteristicKey) value.cancel();
        return key == characteristicKey;
      });
    }
  }

  @override
  Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  ) async {
    final bleCharacteristic = await _getBleCharacteristic(
      deviceId: deviceId,
      serviceId: service,
      characteristicId: characteristic,
    );

    if (bleCharacteristic == null) {
      throw Exception(
        'Characteristic $characteristic for service $service not found',
      );
    }

    if (bleOutputProperty == BleOutputProperty.withResponse) {
      await bleCharacteristic.writeValueWithResponse(Uint8List.fromList(value));
    } else {
      await bleCharacteristic
          .writeValueWithoutResponse(Uint8List.fromList(value));
    }
  }

  @override
  Future<Uint8List> readValue(
    String deviceId,
    String service,
    String characteristic,
  ) async {
    var bleCharacteristic = await _getBleCharacteristic(
      deviceId: deviceId,
      serviceId: service,
      characteristicId: characteristic,
    );
    if (bleCharacteristic == null) {
      throw Exception(
          'Characteristic $characteristic for service $service not found');
    }
    var data = await bleCharacteristic.readValue();
    return data.buffer.asUint8List();
  }

  /// `Unimplemented`
  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) {
    throw UnimplementedError();
  }

  @override
  Future<bool> isPaired(String deviceId) {
    throw UnimplementedError();
  }

  @override
  Future<void> pair(String deviceId) {
    throw UnimplementedError();
  }

  @override
  Future<void> unPair(String deviceId) {
    throw UnimplementedError();
  }

  @override
  Future<List<BleDevice>> getSystemDevices(
    List<String>? withServices,
  ) {
    throw UnimplementedError();
  }

  /// Helpers
  void _setupListeners() {
    FlutterWebBluetooth.instance.isAvailable.listen(
      (bool isAvailable) {
        AvailabilityState newState = AvailabilityState.unknown;
        if (!FlutterWebBluetooth.instance.isBluetoothApiSupported) {
          newState = AvailabilityState.unsupported;
        } else if (FlutterWebBluetooth.instance.isBluetoothApiSupported &&
            !isAvailable) {
          newState = AvailabilityState.poweredOff;
        } else if (isAvailable) {
          newState = AvailabilityState.poweredOn;
        }
        onAvailabilityChange?.call(newState);
      },
    );
  }

  void _cleanConnection(String deviceId) {
    _connectedDeviceStreamList.removeWhere((key, value) {
      if (key == deviceId) value.cancel();
      return key == deviceId;
    });
    _characteristicStreamList.removeWhere((key, value) {
      if (key.contains(deviceId)) value.cancel();
      return key.contains(deviceId);
    });
    // _bluetoothDeviceList.removeWhere((element) => element.id == deviceId);
  }

  Future<BluetoothCharacteristic?> _getBleCharacteristic({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
  }) async {
    final device = _getDeviceById(deviceId);
    List<BluetoothService> services = await device?.discoverServices() ?? [];
    BluetoothService? service;
    for (BluetoothService bleService in services) {
      if (bleService.uuid.toString() == serviceId.toString()) {
        service = bleService;
        break;
      }
    }
    return await service?.getCharacteristic(characteristicId.toString());
  }

  BluetoothDevice? _getDeviceById(String id) => _bluetoothDeviceList[id];

  @override
  Future<bool> enableBluetooth() {
    throw UnimplementedError();
  }
}

extension _BluetoothDeviceExtension on BluetoothDevice {
  BleDevice toBleScanResult({
    int? rssi,
    UnmodifiableMapView<int, ByteData>? manufacturerDataMap,
    List<String> services = const [],
  }) {
    return BleDevice(
      name: name,
      deviceId: id,
      manufacturerData: manufacturerDataMap?.toUint8List(),
      manufacturerDataHead: manufacturerDataMap?.toUint8List(),
      rssi: rssi,
      services: services,
    );
  }
}

extension _UnmodifiableMapViewExtension on UnmodifiableMapView<int, ByteData> {
  Uint8List? toUint8List() {
    List<MapEntry<int, ByteData>> sorted = entries.toList()
      ..sort((a, b) => a.key - b.key);
    if (sorted.isEmpty) return null;
    int companyId = sorted.first.key;
    List<int> manufacturerDataValue = sorted.first.value.buffer.asUint8List();
    final byteData = ByteData(2);
    byteData.setInt16(0, companyId, Endian.host);
    List<int> bytes = byteData.buffer.asUint8List();
    return Uint8List.fromList(bytes + manufacturerDataValue);
  }
}

extension ScanFilterExtension on ScanFilter {
  RequestOptionsBuilder toRequestOptionsBuilder() {
    List<RequestFilterBuilder> filters = [];
    List<int> manufacturerCompanyIdentifiers = [];

    // Add services filter
    for (var service in withServices.toValidUUIDList()) {
      filters.add(
        RequestFilterBuilder(
          services: [service],
        ),
      );
    }

    // Add manufacturer data filter
    for (var manufacturerData in withManufacturerData) {
      filters.add(
        RequestFilterBuilder(
          manufacturerData: [
            ManufacturerDataFilterBuilder(
              companyIdentifier: manufacturerData.companyIdentifier,
              dataPrefix: manufacturerData.data,
              mask: manufacturerData.mask,
            ),
          ],
        ),
      );
      int? companyId = manufacturerData.companyIdentifier;
      if (companyId != null) {
        manufacturerCompanyIdentifiers.add(companyId);
      }
    }

    // Add name filter
    for (var name in withNamePrefix) {
      filters.add(
        RequestFilterBuilder(namePrefix: name),
      );
    }

    if (filters.isEmpty) {
      return RequestOptionsBuilder.acceptAllDevices();
    }

    return RequestOptionsBuilder(
      filters,
      optionalServices: withServices.toValidUUIDList(),
      optionalManufacturerData: manufacturerCompanyIdentifiers,
    );
  }
}
