import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:universal_ble/src/universal_ble_pigeon/universal_ble.g.dart'
    as pigeon;
import 'package:universal_ble/src/universal_ble_peripheral/universal_ble_peripheral_mapper.dart';
import 'package:universal_ble/universal_ble.dart';

class UniversalBlePeripheralPigeon extends UniversalBlePeripheralPlatform
    implements pigeon.UniversalBlePeripheralCallback {
  UniversalBlePeripheralPigeon._() {
    pigeon.UniversalBlePeripheralCallback.setUp(this);
  }

  static UniversalBlePeripheralPigeon? _instance;
  static UniversalBlePeripheralPigeon get instance =>
      _instance ??= UniversalBlePeripheralPigeon._();

  final pigeon.UniversalBlePeripheralChannel _channel =
      pigeon.UniversalBlePeripheralChannel();
  final StreamController<({String serviceId, String? error})>
      _serviceResultController =
      StreamController<({String serviceId, String? error})>.broadcast();
  final StreamController<UniversalBlePeripheralEvent> _eventController =
      StreamController<UniversalBlePeripheralEvent>.broadcast();
  bool _disposed = false;
  OnPeripheralReadRequest? _readRequestHandler;
  OnPeripheralWriteRequest? _writeRequestHandler;
  OnPeripheralDescriptorReadRequest? _descriptorReadRequestHandler;
  OnPeripheralDescriptorWriteRequest? _descriptorWriteRequestHandler;

  @override
  Stream<UniversalBlePeripheralEvent> get eventStream =>
      _eventController.stream;

  @override
  void setRequestHandlers(PeripheralRequestHandlers handlers) {
    _readRequestHandler = handlers.onReadRequest;
    _writeRequestHandler = handlers.onWriteRequest;
    _descriptorReadRequestHandler = handlers.onDescriptorReadRequest;
    _descriptorWriteRequestHandler = handlers.onDescriptorWriteRequest;
  }

  @override
  Future<UniversalBlePeripheralReadinessState> getReadinessState() async {
    final state = await _channel.getReadinessState();
    return switch (state) {
      pigeon.PeripheralReadinessState.ready =>
        UniversalBlePeripheralReadinessState.ready,
      pigeon.PeripheralReadinessState.bluetoothOff =>
        UniversalBlePeripheralReadinessState.bluetoothOff,
      pigeon.PeripheralReadinessState.unauthorized =>
        UniversalBlePeripheralReadinessState.unauthorized,
      pigeon.PeripheralReadinessState.unsupported =>
        UniversalBlePeripheralReadinessState.unsupported,
      pigeon.PeripheralReadinessState.unknown =>
        UniversalBlePeripheralReadinessState.unknown,
    };
  }

  @override
  Future<UniversalBlePeripheralAdvertisingState> getAdvertisingState() async {
    final state = await _channel.getAdvertisingState();
    return switch (state) {
      pigeon.PeripheralAdvertisingState.idle =>
        UniversalBlePeripheralAdvertisingState.idle,
      pigeon.PeripheralAdvertisingState.starting =>
        UniversalBlePeripheralAdvertisingState.starting,
      pigeon.PeripheralAdvertisingState.advertising =>
        UniversalBlePeripheralAdvertisingState.advertising,
      pigeon.PeripheralAdvertisingState.stopping =>
        UniversalBlePeripheralAdvertisingState.stopping,
      pigeon.PeripheralAdvertisingState.error =>
        UniversalBlePeripheralAdvertisingState.error,
    };
  }

  @override
  Future<UniversalBlePeripheralCapabilities> getStaticCapabilities() async {
    final readiness = await getReadinessState();
    final platform = defaultTargetPlatform;
    final supported = readiness != UniversalBlePeripheralReadinessState.unsupported;

    final supportsManufacturerDataInScanResponse =
        platform == TargetPlatform.android;
    final supportsAdvertisingTimeout = platform == TargetPlatform.android;

    return UniversalBlePeripheralCapabilities(
      supportsPeripheralMode: supported,
      supportsManufacturerDataInAdvertisement: supported,
      supportsManufacturerDataInScanResponse:
          supported && supportsManufacturerDataInScanResponse,
      supportsServiceDataInAdvertisement: false,
      supportsServiceDataInScanResponse: false,
      supportsTargetedCharacteristicUpdate: supported,
      supportsAdvertisingTimeout: supported && supportsAdvertisingTimeout,
    );
  }

  @override
  Future<void> addService(
    BleService service, {
    bool primary = true,
    Duration? timeout,
  }) async {
    final String serviceId = BleUuidParser.string(service.uuid);
    final Completer<void> completer = Completer<void>();
    _serviceResultController.stream
        .where((e) => BleUuidParser.compareStrings(e.serviceId, serviceId))
        .first
        .timeout(
          timeout ?? const Duration(seconds: 5),
          onTimeout: () =>
              (serviceId: serviceId, error: 'Service add timed out'),
        )
        .then((e) {
      if (completer.isCompleted) return;
      if (e.error != null) {
        completer.completeError(
          PlatformException(code: 'service-add-failed', message: e.error),
        );
      } else {
        completer.complete();
      }
    });

    await _channel.addService(
      UniversalBlePeripheralMapper.toPigeonService(service, primary: primary),
    );
    await completer.future;
  }

  @override
  Future<void> removeService(PeripheralServiceId serviceId) =>
      _channel.removeService(BleUuidParser.string(serviceId.value));

  @override
  Future<void> clearServices() => _channel.clearServices();

  @override
  Future<List<PeripheralServiceId>> getServices() async =>
      (await _channel.getServices()).map(PeripheralServiceId.new).toList();

  @override
  Future<void> startAdvertising({
    required List<PeripheralServiceId> services,
    String? localName,
    int? timeout,
    ManufacturerData? manufacturerData,
    bool addManufacturerDataInScanResponse = false,
  }) {
    return _channel.startAdvertising(
      services.map((e) => BleUuidParser.string(e.value)).toList(),
      localName,
      timeout,
      UniversalBlePeripheralMapper.toPigeonManufacturerData(manufacturerData),
      addManufacturerDataInScanResponse,
    );
  }

  @override
  Future<void> stopAdvertising() => _channel.stopAdvertising();

  @override
  Future<void> updateCharacteristicValue({
    required PeripheralCharacteristicId characteristicId,
    required Uint8List value,
    PeripheralUpdateTarget target = const PeripheralUpdateAllSubscribed(),
  }) {
    final String? deviceId = switch (target) {
      PeripheralUpdateAllSubscribed() => null,
      PeripheralUpdateSingleDevice(deviceId: final id) => id,
    };
    return _channel.updateCharacteristic(
      BleUuidParser.string(characteristicId.value),
      value,
      deviceId,
    );
  }

  @override
  Future<List<String>> getSubscribedClients(PeripheralCharacteristicId characteristicId) =>
      _channel.getSubscribedClients(characteristicId.value);

  @override
  Future<int?> getMaximumNotifyLength(String deviceId) =>
      _channel.getMaximumNotifyLength(deviceId);

  @override
  void onAdvertisingStateChange(
    pigeon.PeripheralAdvertisingState state,
    String? error,
  ) {
    final mapped = switch (state) {
      pigeon.PeripheralAdvertisingState.idle =>
        UniversalBlePeripheralAdvertisingState.idle,
      pigeon.PeripheralAdvertisingState.starting =>
        UniversalBlePeripheralAdvertisingState.starting,
      pigeon.PeripheralAdvertisingState.advertising =>
        UniversalBlePeripheralAdvertisingState.advertising,
      pigeon.PeripheralAdvertisingState.stopping =>
        UniversalBlePeripheralAdvertisingState.stopping,
      pigeon.PeripheralAdvertisingState.error =>
        UniversalBlePeripheralAdvertisingState.error,
    };
    if (!_eventController.isClosed) {
      _eventController.add(
        UniversalBlePeripheralAdvertisingStateChanged(mapped, error),
      );
    }
  }

  @override
  void onCharacteristicSubscriptionChange(
    String deviceId,
    String characteristicId,
    bool isSubscribed,
    String? name,
  ) {
    if (!_eventController.isClosed) {
      _eventController.add(
        UniversalBlePeripheralCharacteristicSubscriptionChanged(
          deviceId: deviceId,
          characteristicId: characteristicId,
          isSubscribed: isSubscribed,
          name: name,
        ),
      );
    }
  }

  @override
  void onConnectionStateChange(String deviceId, bool connected) {
    if (!_eventController.isClosed) {
      _eventController.add(
        UniversalBlePeripheralConnectionStateChanged(deviceId, connected),
      );
    }
  }

  @override
  void onMtuChange(String deviceId, int mtu) {
    if (!_eventController.isClosed) {
      _eventController.add(UniversalBlePeripheralMtuChanged(deviceId, mtu));
    }
  }

  @override
  pigeon.PeripheralReadRequestResult? onReadRequest(
    String deviceId,
    String characteristicId,
    int offset,
    Uint8List? value,
  ) {
    final result = _readRequestHandler?.call(
      deviceId,
      PeripheralCharacteristicId(characteristicId),
      offset,
      value,
    );
    if (result == null) return null;
    return pigeon.PeripheralReadRequestResult(
      value: result.value,
      offset: result.offset,
      status: result.status,
    );
  }

  @override
  void onServiceAdded(String serviceId, String? error) {
    if (!_eventController.isClosed) {
      _eventController.add(UniversalBlePeripheralServiceAdded(serviceId, error));
    }
    if (!_serviceResultController.isClosed) {
      _serviceResultController.add((serviceId: serviceId, error: error));
    }
  }

  @override
  pigeon.PeripheralWriteRequestResult? onWriteRequest(
    String deviceId,
    String characteristicId,
    int offset,
    Uint8List? value,
  ) {
    final result = _writeRequestHandler?.call(
          deviceId,
          PeripheralCharacteristicId(characteristicId),
          offset,
          value,
        );
    if (result == null) return null;
    return pigeon.PeripheralWriteRequestResult(
      value: result.value,
      offset: result.offset,
      status: result.status,
    );
  }

  @override
  pigeon.PeripheralReadRequestResult? onDescriptorReadRequest(
    String deviceId,
    String characteristicId,
    String descriptorId,
    int offset,
    Uint8List? value,
  ) {
    final result = _descriptorReadRequestHandler?.call(
      deviceId,
      PeripheralCharacteristicId(characteristicId),
      PeripheralDescriptorId(descriptorId),
      offset,
      value,
    );
    if (result == null) return null;
    return pigeon.PeripheralReadRequestResult(
      value: result.value,
      offset: result.offset,
      status: result.status,
    );
  }

  @override
  pigeon.PeripheralWriteRequestResult? onDescriptorWriteRequest(
    String deviceId,
    String characteristicId,
    String descriptorId,
    int offset,
    Uint8List? value,
  ) {
    final result = _descriptorWriteRequestHandler?.call(
      deviceId,
      PeripheralCharacteristicId(characteristicId),
      PeripheralDescriptorId(descriptorId),
      offset,
      value,
    );
    if (result == null) return null;
    return pigeon.PeripheralWriteRequestResult(
      value: result.value,
      offset: result.offset,
      status: result.status,
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    pigeon.UniversalBlePeripheralCallback.setUp(null);
    if (!_serviceResultController.isClosed) {
      _serviceResultController.close();
    }
    if (!_eventController.isClosed) {
      _eventController.close();
    }
    if (identical(_instance, this)) {
      _instance = null;
    }
  }
}
