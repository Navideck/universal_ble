import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_web_bluetooth/flutter_web_bluetooth.dart';
import 'package:flutter_web_bluetooth/js_web_bluetooth.dart'
    show WatchAdvertisementsOptions;
import 'package:flutter_web_bluetooth/web/js/js.dart' show AbortController;
import 'package:universal_ble/src/utils/universal_logger.dart';
import 'package:universal_ble/universal_ble.dart';

class UniversalBleWeb extends UniversalBlePlatform {
  static UniversalBleWeb? _instance;
  static UniversalBleWeb get instance => _instance ??= UniversalBleWeb._();

  UniversalBleWeb._() {
    _setupListeners();
  }

  /// Web Bluetooth device ids are opaque, case-sensitive browser tokens (Chromium emits Base64 of a
  /// random value), not the case-insensitive addresses the other platforms report — so they are
  /// emitted and matched verbatim. Case-folding one would corrupt the id the caller sees and break
  /// `_bluetoothDeviceList`, which is keyed by the browser's own `BluetoothDevice.id`.
  @override
  bool get hasAddressDeviceIds => false;

  final Map<String, BluetoothDevice> _bluetoothDeviceList = {};
  final Map<String, StreamSubscription> _deviceAdvertisementStreamList = {};
  final Map<String, Future<void>> _advertisementStartOperations = {};
  final Map<String, AbortController> _advertisementControllers = {};
  static const _advertisementTimeout = Duration(seconds: 5);
  final Map<String, StreamSubscription> _connectedDeviceStreamList = {};
  final Map<String, StreamSubscription> _characteristicStreamList = {};
  final Map<String, List<_UniversalWebBluetoothService>> _serviceCache = {};
  final Map<String, Completer<void>> _connectCancellations = {};
  final Map<String, Future<void>> _disconnectOperations = {};
  final Map<String, int> _connectionGenerations = {};
  bool _isScanning = false;
  int _scanGeneration = 0;
  static const _connectionCancellationGrace = Duration(seconds: 5);

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
    bool autoConnect = false,
    ConnectionPlatformConfig? platformConfig,
  }) async {
    // autoConnect and platformConfig are not supported on Web.
    final device = _getDeviceById(deviceId);
    if (device == null) {
      throw UniversalBleException(
        code: UniversalBleErrorCode.deviceNotFound,
        message: "$deviceId Not Found",
      );
    }
    if (_connectCancellations.containsKey(deviceId) ||
        _disconnectOperations.containsKey(deviceId)) {
      throw UniversalBleException(
        code: UniversalBleErrorCode.connectionInProgress,
        message: 'A connection operation is already in progress for $deviceId',
      );
    }
    final generation = (_connectionGenerations[deviceId] ?? 0) + 1;
    _connectionGenerations[deviceId] = generation;
    _serviceCache.remove(deviceId);
    final cancellation = Completer<void>();
    _connectCancellations[deviceId] = cancellation;
    unawaited(cancellation.future.then((_) async {
      await Future<void>.delayed(_connectionCancellationGrace);
      if (identical(_connectCancellations[deviceId], cancellation)) {
        _connectCancellations.remove(deviceId);
      }
    }));
    final clock = Stopwatch()..start();

    // Keep the reservation until setup settles or cancellation's grace expires.
    final setup = _connectDevice(
            device, generation, cancellation, connectionTimeout, clock)
        .whenComplete(() {
      if (identical(_connectCancellations[deviceId], cancellation)) {
        _connectCancellations.remove(deviceId);
      }
    });
    final result = Future.any<void>([
      setup,
      cancellation.future.then<void>((_) => throw UniversalBleException(
            code: UniversalBleErrorCode.deviceDisconnected,
            message: 'Device $deviceId disconnected during connection setup',
          )),
    ]);
    try {
      if (connectionTimeout == null) {
        await result;
      } else {
        await result.timeout(connectionTimeout);
      }
    } catch (error) {
      // An old attempt must never disconnect or clear a newer session.
      if (_connectionGenerations[deviceId] == generation) {
        _cleanConnection(deviceId);
        device.disconnect();
      }
      if (error is TimeoutException) {
        throw UniversalBleException(
          code: UniversalBleErrorCode.connectionTimeout,
          message: 'Connection to $deviceId timed out',
          details: error,
        );
      }
      rethrow;
    }
  }

  Future<void> _connectDevice(BluetoothDevice device, int generation,
      Completer<void> cancellation, Duration? timeout, Stopwatch clock) async {
    final deviceId = device.id;
    await _stopAdvertisementWatcher(deviceId);
    _assertConnectionGeneration(deviceId, generation);
    await _connectedDeviceStreamList.remove(deviceId)?.cancel();
    _assertConnectionGeneration(deviceId, generation);
    final remaining = timeout == null ? null : timeout - clock.elapsed;
    if (remaining != null && remaining <= Duration.zero) {
      throw TimeoutException('Connection setup timed out');
    }
    // Stay on the dependency's supported API. It updates its connection stream
    // on successful connect; native calls bypass that state and replay false.
    // The outer deadline owns cancellation. The wrapper's timeout calls
    // disconnect internally and could otherwise tear down a retry after the
    // cancelled attempt's reservation has expired.
    await device.connect(timeout: null);
    if (_connectionGenerations[deviceId] != generation) {
      // Protect a newer pending attempt or tracked connection. Failed and
      // cancelled retries no longer own the link, even during their grace period.
      final owner = _connectCancellations[deviceId];
      final newerAttemptPending = owner != null &&
          !identical(owner, cancellation) &&
          !owner.isCompleted;
      if (!newerAttemptPending &&
          !_connectedDeviceStreamList.containsKey(deviceId)) {
        device.disconnect();
      }
    }
    _assertConnectionGeneration(deviceId, generation);
    _connectedDeviceStreamList[deviceId] = device.connected.listen((connected) {
      if (_connectionGenerations[deviceId] != generation) return;
      if (!connected) _cleanConnection(deviceId);
      updateConnection(deviceId, connected);
    });
  }

  void _assertConnectionGeneration(String deviceId, int generation) {
    if ((_connectionGenerations[deviceId] ?? 0) == generation) return;
    throw UniversalBleException(
      code: UniversalBleErrorCode.deviceDisconnected,
      message: 'Device $deviceId disconnected during GATT setup',
    );
  }

  @override
  Future<void> disconnect(String deviceId) async {
    final existing = _disconnectOperations[deviceId];
    if (existing != null) return existing;
    final operation = _disconnectDevice(deviceId);
    _disconnectOperations[deviceId] = operation;
    try {
      await operation;
    } finally {
      if (identical(_disconnectOperations[deviceId], operation)) {
        _disconnectOperations.remove(deviceId);
      }
      // Cleanup has finished. Callbacks may now start another connection.
      updateConnection(deviceId, false);
    }
  }

  Future<void> _disconnectDevice(String deviceId) async {
    _connectionGenerations[deviceId] =
        (_connectionGenerations[deviceId] ?? 0) + 1;
    final cancellation = _connectCancellations[deviceId];
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
    // Abort native connect immediately, before waiting for subscription cleanup.
    _getDeviceById(deviceId)?.disconnect();
    _serviceCache.remove(deviceId);
    await _connectedDeviceStreamList.remove(deviceId)?.cancel();
    final prefix = '${deviceId}_';
    final keys = _characteristicStreamList.keys
        .where((key) => key.startsWith(prefix))
        .toList(growable: false);
    for (final key in keys) {
      await _characteristicStreamList.remove(key)?.cancel();
    }
    await _stopAdvertisementWatcher(deviceId);
  }

  @override
  Future<List<BleService>> discoverServices(
    String deviceId,
    bool withDescriptors,
  ) async {
    final generation = _connectionGenerations[deviceId] ?? 0;
    List<BleService> services = [];
    for (var service in await _getServices(deviceId)) {
      services.add(await service._toBleService(deviceId, withDescriptors));
      _assertConnectionGeneration(deviceId, generation);
    }
    return services;
  }

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
    final scanGeneration = ++_scanGeneration;
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

      unawaited(_watchDeviceAdvertisements(device, scanGeneration));
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
  Future<void> _watchDeviceAdvertisements(
      BluetoothDevice device, int scanGeneration) async {
    try {
      if (!device.hasWatchAdvertisements()) return;
      final generation = _connectionGenerations[device.id] ?? 0;
      await _stopAdvertisementWatcher(device.id);
      // A scan callback may immediately start connecting or stop the scan.
      // Do not restart advertisement watching after connection cleanup.
      if (_scanGeneration != scanGeneration ||
          (_connectionGenerations[device.id] ?? 0) != generation ||
          _connectCancellations.containsKey(device.id) ||
          _connectedDeviceStreamList.containsKey(device.id)) {
        return;
      }

      _deviceAdvertisementStreamList[device.id] = device.advertisements.listen((
        event,
      ) {
        final serviceDataMap = event.serviceData.map(
          (key, value) => MapEntry(key, value.buffer.asUint8List()),
        );
        updateScanResult(
          device.toBleScanResult(
            rssi: event.rssi,
            manufacturerDataMap: event.manufacturerData,
            services: event.uuids.toSet().toList(),
            serviceDataMap: serviceDataMap,
          ),
        );
      });
      device.advertisementsUseMemory = true;
      // Own the abort signal: the dependency does not retain its controller
      // when watchAdvertisements is called without a timeout. A lifetime
      // timeout would also stop a successfully started scan after five seconds.
      final controller = AbortController();
      _advertisementControllers[device.id] = controller;
      // The wrapper has no API accepting a caller-owned abort signal.
      // ignore: deprecated_member_use
      final operation = device.nativeDevice
          .watchAdvertisements(
              WatchAdvertisementsOptions(signal: controller.signal))
          .timeout(_advertisementTimeout, onTimeout: () {
        controller.abort();
        throw TimeoutException('Advertisement startup timed out');
      });
      _advertisementStartOperations[device.id] = operation;
      try {
        await operation;
      } finally {
        if (identical(_advertisementStartOperations[device.id], operation)) {
          _advertisementStartOperations.remove(device.id);
        }
      }
    } catch (e) {
      UniversalLogger.logError("WebWatchAdvertisementError: $e");
    }
  }

  @override
  Future<void> stopScan() async {
    _scanGeneration++;
    _isScanning = false;
    try {
      await _stopAdvertisementWatcher();
    } catch (error) {
      UniversalLogger.logError('WebUnwatchAdvertisementError: $error');
    }
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
    UniversalLogger.logDebug(
      "SET_NOTIFY -> $deviceId $service $characteristic input=${bleInputProperty.name}",
      withTimestamp: true,
    );
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
        final preview = event.buffer
            .asUint8List()
            .take(8)
            .map((e) => e.toRadixString(16).padLeft(2, '0'))
            .join();
        UniversalLogger.logVerbose(
          "NOTIFY <- $deviceId $characteristic len=${event.lengthInBytes} data=$preview",
          withTimestamp: true,
        );
        updateCharacteristicValue(
          deviceId,
          characteristic,
          event.buffer.asUint8List(),
          DateTime.now().millisecondsSinceEpoch,
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
    UniversalLogger.logDebug(
      "WRITE -> $deviceId $service $characteristic len=${value.length} property=${bleOutputProperty.name}",
      withTimestamp: true,
    );
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
      await bleCharacteristic.writeValueWithoutResponse(
        Uint8List.fromList(value),
      );
    }
  }

  @override
  Future<Uint8List> readValue(
    String deviceId,
    String service,
    String characteristic, {
    Duration? timeout,
  }) async {
    UniversalLogger.logDebug(
      "READ -> $deviceId $service $characteristic",
      withTimestamp: true,
    );
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

  @override
  Future<Uint8List> readDescriptorValue(
    String deviceId,
    String service,
    String characteristic,
    String descriptor, {
    Duration? timeout,
  }) async {
    UniversalLogger.logDebug(
      "READ_DESCRIPTOR -> $deviceId $service $characteristic $descriptor",
      withTimestamp: true,
    );
    var bleDescriptor = await _getBleDescriptor(
      deviceId: deviceId,
      serviceId: service,
      characteristicId: characteristic,
      descriptorId: descriptor,
    );
    if (bleDescriptor == null) {
      throw UniversalBleException(
        code: UniversalBleErrorCode.characteristicNotFound,
        message:
            'Descriptor $descriptor for characteristic $characteristic not found',
      );
    }
    var data = await bleDescriptor.readValue();
    return data.buffer.asUint8List();
  }

  @override
  Future<void> writeDescriptorValue(
    String deviceId,
    String service,
    String characteristic,
    String descriptor,
    Uint8List value,
  ) async {
    UniversalLogger.logDebug(
      "WRITE_DESCRIPTOR -> $deviceId $service $characteristic $descriptor len=${value.length}",
      withTimestamp: true,
    );
    var bleDescriptor = await _getBleDescriptor(
      deviceId: deviceId,
      serviceId: service,
      characteristicId: characteristic,
      descriptorId: descriptor,
    );
    if (bleDescriptor == null) {
      throw UniversalBleException(
        code: UniversalBleErrorCode.characteristicNotFound,
        message:
            'Descriptor $descriptor for characteristic $characteristic not found',
      );
    }
    await bleDescriptor.writeValue(Uint8List.fromList(value));
  }

  /// `Unimplemented`
  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) {
    throw UniversalBleException(
      code: UniversalBleErrorCode.notImplemented,
      message: "requestMtu is not implemented on Web platform",
    );
  }

  /// `Unimplemented`
  @override
  Future<void> requestConnectionPriority(
    String deviceId,
    BleConnectionPriority priority,
  ) {
    throw UniversalBleException(
      code: UniversalBleErrorCode.notSupported,
      message: "requestConnectionPriority is not supported on Web platform",
    );
  }

  /// `Unimplemented`
  @override
  Future<int> readRssi(String deviceId) {
    throw UniversalBleException(
      code: UniversalBleErrorCode.notImplemented,
      message: "readRssi is not implemented on Web platform",
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
  Future<List<BleDevice>> getSystemDevices(List<String>? withServices) {
    throw UniversalBleException(
      code: UniversalBleErrorCode.notImplemented,
      message: "getSystemDevices is not implemented on Web platform",
    );
  }

  /// Helpers
  void _setupListeners() {
    FlutterWebBluetooth.instance.isAvailable.listen((bool isAvailable) {
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
    });
  }

  void _cleanConnection(String deviceId) {
    _connectionGenerations[deviceId] =
        (_connectionGenerations[deviceId] ?? 0) + 1;
    final cancellation = _connectCancellations[deviceId];
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
    _connectedDeviceStreamList.removeWhere((key, value) {
      if (key == deviceId) value.cancel();
      return key == deviceId;
    });
    _characteristicStreamList.removeWhere((key, value) {
      if (key.contains(deviceId)) value.cancel();
      return key.contains(deviceId);
    });
    unawaited(_stopAdvertisementWatcher(deviceId).catchError((Object error) {
      UniversalLogger.logError('WebUnwatchAdvertisementError: $error');
    }));
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

  Future<BluetoothDescriptor?> _getBleDescriptor({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
    required String descriptorId,
  }) async {
    var bleCharacteristic = await _getBleCharacteristic(
      deviceId: deviceId,
      serviceId: serviceId,
      characteristicId: characteristicId,
    );
    if (bleCharacteristic == null) return null;
    try {
      return await bleCharacteristic.getDescriptor(descriptorId);
    } catch (_) {
      try {
        var descriptors = await bleCharacteristic.getDescriptors();
        for (var desc in descriptors) {
          if (BleUuidParser.compareStrings(desc.uuid, descriptorId)) {
            return desc;
          }
        }
      } catch (_) {}
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
    final device = _getDeviceById(deviceId);
    if (device == null) return [];
    final generation = _connectionGenerations[deviceId] ?? 0;
    final cached = _serviceCache[deviceId];
    if (cached != null && cached.isNotEmpty) return cached;
    final services = <_UniversalWebBluetoothService>[];
    final discovered = await device.discoverServices();
    _assertConnectionGeneration(deviceId, generation);
    for (final service in discovered) {
      services.add(await _UniversalWebBluetoothService.fromService(service));
      _assertConnectionGeneration(deviceId, generation);
    }
    _serviceCache[deviceId] = services;
    return services;
  }

  Future<void> _stopAdvertisementWatcher([String? deviceId]) async {
    final deviceIds = _deviceAdvertisementStreamList.keys
        .where((key) => deviceId == null || key == deviceId)
        .toList(growable: false);
    for (final id in deviceIds) {
      final subscription = _deviceAdvertisementStreamList[id];
      final device = _getDeviceById(id);
      // Abort pending startup before waiting for it. An aborted signal also
      // prevents a late native completion from restarting advertisements.
      _advertisementControllers.remove(id)?.abort();
      await subscription?.cancel();
      try {
        await _advertisementStartOperations[id];
      } catch (_) {
        // Advertisement startup reports its own error and is optional.
      }
      // Let unexpected stop failures propagate: connecting while the browser
      // is still watching would recreate the scan/connect overlap.
      try {
        await device?.unwatchAdvertisements().timeout(_advertisementTimeout);
      } finally {
        if (identical(_deviceAdvertisementStreamList[id], subscription)) {
          _deviceAdvertisementStreamList.remove(id);
        }
      }
    }
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
        exclusionFilters.add(
          RequestFilterBuilder(
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
          ),
        );
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
    Map<String, Uint8List>? serviceDataMap,
  }) {
    final timestampMicroseconds = DateTime.now().microsecondsSinceEpoch;
    return BleDevice(
      name: name,
      deviceId: id,
      manufacturerDataList: manufacturerDataMap?.toManufacturerDataList() ?? [],
      rssi: rssi,
      services: services,
      serviceData: serviceDataMap ?? {},
      timestamp: timestampMicroseconds ~/ Duration.microsecondsPerMillisecond,
      timestampMicroseconds: timestampMicroseconds,
    );
  }
}

extension _UnmodifiableMapViewExtension on UnmodifiableMapView<int, ByteData> {
  List<ManufacturerData>? toManufacturerDataList() => entries
      .map(
        (MapEntry<int, ByteData> data) =>
            ManufacturerData(data.key, data.value.buffer.asUint8List()),
      )
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

  Future<BleService> _toBleService(
    String deviceId,
    bool withDescriptors,
  ) async {
    List<BleCharacteristic> bleCharacteristics = [];
    for (var characteristic in characteristics) {
      List<BleDescriptor> descriptors = [];
      if (withDescriptors) {
        try {
          var bluetoothDescriptors = await characteristic.getDescriptors();
          descriptors =
              bluetoothDescriptors.map((e) => BleDescriptor(e.uuid)).toList();
        } catch (_) {}
      }
      bleCharacteristics.add(
        BleCharacteristic.withMetaData(
          deviceId: deviceId,
          serviceId: service.uuid,
          uuid: characteristic.uuid,
          properties: [
            if (characteristic.properties.broadcast)
              CharacteristicProperty.broadcast,
            if (characteristic.properties.read) CharacteristicProperty.read,
            if (characteristic.properties.write) CharacteristicProperty.write,
            if (characteristic.properties.writeWithoutResponse)
              CharacteristicProperty.writeWithoutResponse,
            if (characteristic.properties.notify) CharacteristicProperty.notify,
            if (characteristic.properties.indicate)
              CharacteristicProperty.indicate,
            if (characteristic.properties.authenticatedSignedWrites)
              CharacteristicProperty.authenticatedSignedWrites,
          ],
          descriptors: descriptors,
        ),
      );
    }
    return BleService(service.uuid, bleCharacteristics);
  }
}
