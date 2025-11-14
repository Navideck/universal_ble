import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_web_bluetooth/flutter_web_bluetooth.dart';
import 'package:universal_ble/src/utils/universal_logger.dart';
import 'package:universal_ble/src/universal_ble_pigeon/universal_ble.g.dart';
import 'package:universal_ble/universal_ble.dart';

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
  final Map<String, List<_UniversalWebBluetoothService>> _serviceCache = {};
  bool _isScanning = false;

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
    if (device == null) {
      throw UniversalBleException(
        code: UniversalBleErrorCode.deviceNotFound,
        message: "$deviceId Not Found",
      );
    }
    await device.connect(timeout: connectionTimeout);

    // Subscribe to Connection Stream
    if (_connectedDeviceStreamList[deviceId] != null) {
      _connectedDeviceStreamList[deviceId]?.cancel();
    }

    _connectedDeviceStreamList[deviceId] = device.connected.listen((event) {
      if (!event) _cleanConnection(deviceId);
      updateConnection(deviceId, event);
    });
  }

  @override
  Future<void> disconnect(String deviceId) async {
    _getDeviceById(deviceId)?.disconnect();
  }

  @override
  Future<List<BleService>> discoverServices(String deviceId) async =>
      (await _getServices(deviceId))
          .map((e) => e._bleService(deviceId))
          .toList();

  @override
  Future<AvailabilityState> getBluetoothAvailabilityState() async {
    bool isSupported = FlutterWebBluetooth.instance.isBluetoothApiSupported;
    if (!isSupported) return AvailabilityState.unsupported;
    bool isAvailable = await FlutterWebBluetooth.instance.getAvailability();
    if (isAvailable) return AvailabilityState.poweredOn;
    return AvailabilityState.unknown;
  }

  @override
  Future<void> startScan({
    ScanFilter? scanFilter,
    PlatformConfig? platformConfig,
  }) async {
    try {
      _isScanning = true;
      FlutterWebBluetooth.instance.isAvailable;
      BluetoothDevice device = await FlutterWebBluetooth.instance.requestDevice(
        _getRequestOptionBuilder(scanFilter, platformConfig?.web),
      );

      // Update local device list
      _bluetoothDeviceList[device.id] = device;

      // Update Scan Result
      updateScanResult(device.toBleScanResult());

      _watchDeviceAdvertisements(device);
    } catch (e) {
      String error = e.toString().replaceAll("DeviceNotFoundError:", "").trim();
      if (error.toLowerCase().contains("api globally disabled")) {
        throw WebBluetoothGloballyDisabled(message: error);
      }
      rethrow;
    } finally {
      _isScanning = false;
    }
  }

  @override
  bool receivesAdvertisements(String deviceId) {
    // Advertisements do not work on Linux/Web even with the "Experimental Web Platform features" flag enabled. Verified with Chrome Version 128.0.6613.138
    if (kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
      return false;
    }

    return _getDeviceById(deviceId)?.hasWatchAdvertisements() ?? false;
  }

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
            services: event.uuids.toSet().toList(),
          ),
        );
      });
      device.advertisementsUseMemory = true;
      await device.watchAdvertisements();
    } catch (e) {
      UniversalLogger.logError("WebWatchAdvertisementError: $e");
    }
  }

  @override
  Future<void> stopScan() async {
    _disposeAdvertisementWatcher();
  }

  @override
  Future<bool> isScanning() async => _isScanning;

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
      throw UniversalBleException(
        code: UniversalBleErrorCode.characteristicNotFound,
        message:
            'Characteristic $characteristic for service $service not found',
      );
    }

    String characteristicKey = "${deviceId}_${service}_$characteristic";

    if (bleInputProperty != BleInputProperty.disabled) {
      if (_characteristicStreamList[characteristicKey] != null) {
        _characteristicStreamList[characteristicKey]?.cancel();
      }
      await bleCharacteristic.startNotifications();
      _characteristicStreamList[characteristicKey] =
          bleCharacteristic.value.listen((ByteData event) {
        updateCharacteristicValue(
          deviceId,
          characteristic,
          event.buffer.asUint8List(),
        );
      });
    } else {
      await bleCharacteristic.stopNotifications();
      _characteristicStreamList.remove(characteristicKey)?.cancel();
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
      throw UniversalBleException(
        code: UniversalBleErrorCode.characteristicNotFound,
        message:
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
    String characteristic, {
    final Duration? timeout,
  }) async {
    var bleCharacteristic = await _getBleCharacteristic(
      deviceId: deviceId,
      serviceId: service,
      characteristicId: characteristic,
    );
    if (bleCharacteristic == null) {
      throw UniversalBleException(
        code: UniversalBleErrorCode.characteristicNotFound,
        message:
            'Characteristic $characteristic for service $service not found',
      );
    }
    var data = timeout != null
        ? bleCharacteristic.readValue(timeout: timeout)
        : bleCharacteristic.readValue();
    return (await data).buffer.asUint8List();
  }

  /// `Unimplemented`
  @override
  Future<void> requestPermissions(
      {bool withAndroidFineLocation = false}) async {
    // No permissions to request on Web
  }

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) {
    throw UniversalBleException(
      code: UniversalBleErrorCode.notImplemented,
      message: "requestMtu is not implemented on Web platform",
    );
  }

  @override
  Future<bool> isPaired(String deviceId) {
    throw UniversalBleException(
      code: UniversalBleErrorCode.notImplemented,
      message: "isPaired is not implemented on Web platform",
    );
  }

  @override
  Future<bool> pair(String deviceId) {
    throw UniversalBleException(
      code: UniversalBleErrorCode.notImplemented,
      message: "pair is not implemented on Web platform",
    );
  }

  @override
  Future<void> unpair(String deviceId) {
    throw UniversalBleException(
      code: UniversalBleErrorCode.notImplemented,
      message: "unpair is not implemented on Web platform",
    );
  }

  @override
  Future<List<BleDevice>> getSystemDevices(
    List<String>? withServices,
  ) {
    throw UniversalBleException(
      code: UniversalBleErrorCode.notImplemented,
      message: "getSystemDevices is not implemented on Web platform",
    );
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
        updateAvailability(newState);
      },
    );
  }

  void _cleanConnection(String deviceId) {
    // _connectedDeviceStreamList.removeWhere((key, value) {
    //   if (key == deviceId) value.cancel();
    //   return key == deviceId;
    // });
    _characteristicStreamList.removeWhere((key, value) {
      if (key.contains(deviceId)) value.cancel();
      return key.contains(deviceId);
    });
    _disposeAdvertisementWatcher(deviceId);
    _serviceCache.remove(deviceId);
    // _bluetoothDeviceList.removeWhere((element) => element.id == deviceId);
  }

  Future<BluetoothCharacteristic?> _getBleCharacteristic({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
  }) async {
    for (var service in await _getServices(deviceId)) {
      if (BleUuidParser.compareStrings(service.uuid, serviceId)) {
        return service.getCharacteristic(characteristicId);
      }
    }
    return null;
  }

  BluetoothDevice? _getDeviceById(String id) => _bluetoothDeviceList[id];

  /// Get services and their characteristics.
  /// Services and characteristics are cached.
  /// Clears cache on disconnection.
  Future<List<_UniversalWebBluetoothService>> _getServices(
    String deviceId,
  ) async {
    BluetoothDevice? device = _getDeviceById(deviceId);
    if (device == null) return [];
    var services = _serviceCache[deviceId] ?? [];
    if (services.isNotEmpty) return services;
    for (var service in await device.discoverServices()) {
      services.add(await _UniversalWebBluetoothService.fromService(service));
    }
    _serviceCache[deviceId] = services;
    return services;
  }

  void _disposeAdvertisementWatcher([String? deviceId]) {
    _deviceAdvertisementStreamList.removeWhere((key, value) {
      if (deviceId != null && key != deviceId) return false;
      value.cancel();
      _getDeviceById(deviceId ?? key)
          ?.unwatchAdvertisements()
          .onError((_, __) {});
      return true;
    });
  }

  @override
  Future<bool> enableBluetooth() {
    throw UniversalBleException(
      code: UniversalBleErrorCode.notImplemented,
      message: "enableBluetooth is not implemented on Web platform",
    );
  }

  @override
  Future<bool> disableBluetooth() {
    throw UniversalBleException(
      code: UniversalBleErrorCode.notImplemented,
      message: "disableBluetooth is not implemented on Web platform",
    );
  }

  RequestOptionsBuilder _getRequestOptionBuilder(
    ScanFilter? scanFilter,
    WebOptions? webOptions,
  ) {
    List<RequestFilterBuilder> filters = [];
    List<RequestFilterBuilder> exclusionFilters = [];
    List<int> optionalManufacturerData = [];
    List<String> optionalServices = [];

    if (webOptions != null) {
      optionalServices.addAll(webOptions.optionalServices.toValidUUIDList());
      optionalManufacturerData.addAll(webOptions.optionalManufacturerData);
    }

    if (scanFilter != null) {
      // Add services filter
      for (var service in scanFilter.withServices.toValidUUIDList()) {
        filters.add(RequestFilterBuilder(services: [service]));
        if (webOptions == null || webOptions.optionalServices.isEmpty) {
          optionalServices.add(service);
        }
      }

      // Add manufacturer data filter
      for (var manufacturerData in scanFilter.withManufacturerData) {
        filters.add(
          RequestFilterBuilder(
            manufacturerData: [
              ManufacturerDataFilterBuilder(
                companyIdentifier: manufacturerData.companyIdentifier,
                dataPrefix: manufacturerData.payloadPrefix,
                mask: manufacturerData.payloadMask,
              ),
            ],
          ),
        );

        // Add optionalManufacturerData from scanFilter if webOptions is not provided
        if (webOptions == null || webOptions.optionalManufacturerData.isEmpty) {
          optionalManufacturerData.add(manufacturerData.companyIdentifier);
        }
      }

      // Add name filter
      for (var name in scanFilter.withNamePrefix) {
        filters.add(RequestFilterBuilder(namePrefix: name));
      }

      // Add exclusion filters
      for (var exclusionFilter in scanFilter.exclusionFilters) {
        exclusionFilters.add(RequestFilterBuilder(
          services: exclusionFilter.services.isEmpty
              ? null
              : exclusionFilter.services.toValidUUIDList(),
          namePrefix: exclusionFilter.namePrefix,
          manufacturerData: exclusionFilter.manufacturerDataFilter.isEmpty
              ? null
              : exclusionFilter.manufacturerDataFilter.map((e) {
                  return ManufacturerDataFilterBuilder(
                    companyIdentifier: e.companyIdentifier,
                    dataPrefix: e.payloadPrefix,
                    mask: e.payloadMask,
                  );
                }).toList(),
        ));
      }
    }

    if (optionalServices.isEmpty) {
      UniversalLogger.logError(
        "OptionalServices list is empty on web, you have to specify services in the ScanFilter in order to be able to access those after connecting",
      );
    }
    if (filters.isEmpty && exclusionFilters.isNotEmpty) {
      UniversalLogger.logError(
        "Web platform requires inclusion filters when using exclusion filters. Please add withServices, withNamePrefix, or withManufacturerData filters.",
      );
    }

    if (filters.isEmpty && exclusionFilters.isEmpty) {
      return RequestOptionsBuilder.acceptAllDevices(
        optionalServices: optionalServices,
        optionalManufacturerData: optionalManufacturerData,
      );
    } else {
      return RequestOptionsBuilder(
        filters,
        optionalServices: optionalServices,
        optionalManufacturerData: optionalManufacturerData,
        exclusionFilters: exclusionFilters.isEmpty ? null : exclusionFilters,
      );
    }
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
      manufacturerDataList: manufacturerDataMap?.toManufacturerDataList() ?? [],
      rssi: rssi,
      services: services,
    );
  }
}

extension _UnmodifiableMapViewExtension on UnmodifiableMapView<int, ByteData> {
  List<ManufacturerData>? toManufacturerDataList() => entries
      .map((MapEntry<int, ByteData> data) =>
          ManufacturerData(data.key, data.value.buffer.asUint8List()))
      .toList();
}

class _UniversalWebBluetoothService {
  late String uuid;
  BluetoothService service;
  List<BluetoothCharacteristic> characteristics;

  _UniversalWebBluetoothService({
    required this.service,
    required this.characteristics,
  }) {
    uuid = service.uuid;
  }

  static Future<_UniversalWebBluetoothService> fromService(
    BluetoothService service,
  ) async {
    return _UniversalWebBluetoothService(
      service: service,
      characteristics: await service.getCharacteristics(),
    );
  }

  BluetoothCharacteristic? getCharacteristic(String characteristicId) {
    for (var characteristic in characteristics) {
      if (BleUuidParser.compareStrings(characteristic.uuid, characteristicId)) {
        return characteristic;
      }
    }
    return null;
  }

  BleService _bleService(String deviceId) => BleService(
        service.uuid,
        characteristics.map((e) {
          return BleCharacteristic.withMetaData(
              deviceId: deviceId,
              serviceId: service.uuid,
              uuid: e.uuid,
              properties: [
                if (e.properties.broadcast) CharacteristicProperty.broadcast,
                if (e.properties.read) CharacteristicProperty.read,
                if (e.properties.write) CharacteristicProperty.write,
                if (e.properties.writeWithoutResponse)
                  CharacteristicProperty.writeWithoutResponse,
                if (e.properties.notify) CharacteristicProperty.notify,
                if (e.properties.indicate) CharacteristicProperty.indicate,
                if (e.properties.authenticatedSignedWrites)
                  CharacteristicProperty.authenticatedSignedWrites,
              ]);
        }).toList(),
      );
}
