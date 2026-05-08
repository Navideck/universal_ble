import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:universal_ble/src/universal_ble.g.dart';
import 'package:universal_ble/universal_ble.dart';

class UniversalBlePeripheralPigeon extends UniversalBlePeripheralPlatform
    implements UniversalBlePeripheralCallback {
  UniversalBlePeripheralPigeon._() {
    UniversalBlePeripheralCallback.setUp(this);
  }

  static UniversalBlePeripheralPigeon? _instance;
  static UniversalBlePeripheralPigeon get instance =>
      _instance ??= UniversalBlePeripheralPigeon._();

  final _channel = UniversalBlePeripheralChannel();

  OnPeripheralReadRequest? _readRequestHandler;
  OnPeripheralWriteRequest? _writeRequestHandler;
  OnPeripheralDescriptorReadRequest? _descriptorReadRequestHandler;
  OnPeripheralDescriptorWriteRequest? _descriptorWriteRequestHandler;

  @override
  Future<PeripheralReadinessState> getAvailabilityState() =>
      _channel.getReadinessState();

  @override
  Future<PeripheralAdvertisingState> getAdvertisingState() =>
      _channel.getAdvertisingState();

  @override
  Future<BlePeripheralCapabilities> getCapabilities() async {
    final readiness = await getAvailabilityState();
    final supported = readiness != PeripheralReadinessState.unsupported;
    final supportsManufacturerDataInScanResponse =
        defaultTargetPlatform == TargetPlatform.android;
    final supportsAdvertisingTimeout =
        defaultTargetPlatform == TargetPlatform.android;
    return BlePeripheralCapabilities(
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
    serviceAddedStream
        .where((e) => BleUuidParser.compareStrings(e.serviceId, serviceId))
        .first
        .timeout(
          timeout ?? const Duration(seconds: 5),
          onTimeout: () =>
              BlePeripheralServiceAdded(serviceId, 'Service add timed out'),
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
    String? deviceId,
  }) {
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
  void setReadRequestHandler(OnPeripheralReadRequest? handler) =>
      _readRequestHandler = handler;

  @override
  void setWriteRequestHandler(OnPeripheralWriteRequest? handler) =>
      _writeRequestHandler = handler;

  @override
  void setDescriptorReadRequestHandler(
    OnPeripheralDescriptorReadRequest? handler,
  ) => _descriptorReadRequestHandler = handler;

  @override
  void setDescriptorWriteRequestHandler(
    OnPeripheralDescriptorWriteRequest? handler,
  ) => _descriptorWriteRequestHandler = handler;

  @override
  void onAdvertisingStateChange(
    PeripheralAdvertisingState state,
    String? error,
  ) {
    updateAdvertisingState(BlePeripheralAdvertisingStateChanged(state, error));
  }

  @override
  void onCharacteristicSubscriptionChange(
    String deviceId,
    String characteristicId,
    bool isSubscribed,
    String? name,
  ) {
    updateCharacteristicSubscription(
      BlePeripheralCharacteristicSubscriptionChanged(
        deviceId: deviceId,
        characteristicId: characteristicId,
        isSubscribed: isSubscribed,
        name: name,
      ),
    );
  }

  @override
  void onConnectionStateChange(String deviceId, bool connected) {
    updateConnectionState(
      BlePeripheralConnectionStateChanged(deviceId, connected),
    );
  }

  @override
  void onMtuChange(String deviceId, int mtu) {
    updateMtu(BlePeripheralMtuChanged(deviceId, mtu));
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
    updateServiceAdded(BlePeripheralServiceAdded(serviceId, error));
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
    UniversalBlePeripheralCallback.setUp(null);
    _readRequestHandler = null;
    _writeRequestHandler = null;
    _descriptorReadRequestHandler = null;
    _descriptorWriteRequestHandler = null;
    super.dispose();
    if (identical(_instance, this)) {
      _instance = null;
    }
  }
}
