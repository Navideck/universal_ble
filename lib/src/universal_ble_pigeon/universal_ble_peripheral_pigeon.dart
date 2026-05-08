import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:universal_ble/src/models/model_exports.dart';
import 'package:universal_ble/src/universal_ble.g.dart';
import 'package:universal_ble/src/interfaces/universal_ble_peripheral_platform_interface.dart';

class UniversalBlePeripheralPigeon extends UniversalBlePeripheralPlatform
    implements UniversalBlePeripheralCallback {
  UniversalBlePeripheralPigeon._() {
    UniversalBlePeripheralCallback.setUp(this);
  }

  static UniversalBlePeripheralPigeon? _instance;
  static UniversalBlePeripheralPigeon get instance =>
      _instance ??= UniversalBlePeripheralPigeon._();

  final _channel = UniversalBlePeripheralChannel();
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
  Future<PeripheralReadinessState> getAvailabilityState() =>
      _channel.getReadinessState();

  @override
  Future<PeripheralAdvertisingState> getAdvertisingState() =>
      _channel.getAdvertisingState();

  @override
  Future<UniversalBlePeripheralCapabilities> getCapabilities() async {
    final readiness = await getAvailabilityState();
    final supported = readiness != PeripheralReadinessState.unsupported;
    final supportsManufacturerDataInScanResponse =
        defaultTargetPlatform == TargetPlatform.android;
    final supportsAdvertisingTimeout =
        defaultTargetPlatform == TargetPlatform.android;
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
    PeripheralService service, {
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

    await _channel.addService(service);
    await completer.future;
  }

  @override
  Future<void> removeService(String serviceId) =>
      _channel.removeService(BleUuidParser.string(serviceId));

  @override
  Future<void> clearServices() => _channel.clearServices();

  @override
  Future<List<String>> getServices() => _channel.getServices();

  @override
  Future<void> startAdvertising({
    required List<String> services,
    String? localName,
    Duration? timeout,
    ManufacturerData? manufacturerData,
    bool addManufacturerDataInScanResponse = false,
  }) {
    return _channel.startAdvertising(
      services.map((e) => BleUuidParser.string(e)).toList(),
      localName,
      timeout?.inMilliseconds,
      manufacturerData != null
          ? UniversalManufacturerData(
              companyIdentifier: manufacturerData.companyId,
              data: manufacturerData.payload,
            )
          : null,
      addManufacturerDataInScanResponse,
    );
  }

  @override
  Future<void> stopAdvertising() => _channel.stopAdvertising();

  @override
  Future<void> updateCharacteristicValue({
    required String characteristicId,
    required Uint8List value,
    PeripheralUpdateTarget target = const PeripheralUpdateAllSubscribed(),
  }) {
    final String? deviceId = switch (target) {
      PeripheralUpdateAllSubscribed() => null,
      PeripheralUpdateSingleDevice(deviceId: final id) => id,
    };
    return _channel.updateCharacteristic(
      BleUuidParser.string(characteristicId),
      value,
      deviceId,
    );
  }

  @override
  Future<List<String>> getSubscribedClients(String characteristicId) =>
      _channel.getSubscribedClients(characteristicId);

  @override
  Future<int?> getMaximumNotifyLength(String deviceId) =>
      _channel.getMaximumNotifyLength(deviceId);

  @override
  void onAdvertisingStateChange(
    PeripheralAdvertisingState state,
    String? error,
  ) {
    if (!_eventController.isClosed) {
      _eventController.add(
        UniversalBlePeripheralAdvertisingStateChanged(state, error),
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
  PeripheralReadRequestResult? onReadRequest(
    String deviceId,
    String characteristicId,
    int offset,
    Uint8List? value,
  ) {
    final result = _readRequestHandler?.call(
      deviceId,
      characteristicId,
      offset,
      value,
    );
    if (result == null) return null;
    return PeripheralReadRequestResult(
      value: result.value,
      offset: result.offset,
      status: result.status,
    );
  }

  @override
  void onServiceAdded(String serviceId, String? error) {
    if (!_eventController.isClosed) {
      _eventController.add(
        UniversalBlePeripheralServiceAdded(serviceId, error),
      );
    }
    if (!_serviceResultController.isClosed) {
      _serviceResultController.add((serviceId: serviceId, error: error));
    }
  }

  @override
  PeripheralWriteRequestResult? onWriteRequest(
    String deviceId,
    String characteristicId,
    int offset,
    Uint8List? value,
  ) {
    final result = _writeRequestHandler?.call(
      deviceId,
      characteristicId,
      offset,
      value,
    );
    if (result == null) return null;
    return PeripheralWriteRequestResult(
      value: result.value,
      offset: result.offset,
      status: result.status,
    );
  }

  @override
  PeripheralReadRequestResult? onDescriptorReadRequest(
    String deviceId,
    String characteristicId,
    String descriptorId,
    int offset,
    Uint8List? value,
  ) {
    final result = _descriptorReadRequestHandler?.call(
      deviceId,
      characteristicId,
      descriptorId,
      offset,
      value,
    );
    if (result == null) return null;
    return PeripheralReadRequestResult(
      value: result.value,
      offset: result.offset,
      status: result.status,
    );
  }

  @override
  PeripheralWriteRequestResult? onDescriptorWriteRequest(
    String deviceId,
    String characteristicId,
    String descriptorId,
    int offset,
    Uint8List? value,
  ) {
    final result = _descriptorWriteRequestHandler?.call(
      deviceId,
      characteristicId,
      descriptorId,
      offset,
      value,
    );
    if (result == null) return null;
    return PeripheralWriteRequestResult(
      value: result.value,
      offset: result.offset,
      status: result.status,
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    UniversalBlePeripheralCallback.setUp(null);
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
