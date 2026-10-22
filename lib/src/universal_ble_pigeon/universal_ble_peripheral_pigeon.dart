import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:universal_ble/src/universal_ble.g.dart';
import 'package:universal_ble/src/utils/device_id.dart';
import 'package:universal_ble/universal_ble.dart';

class UniversalBlePeripheralPigeon extends UniversalBlePeripheralPlatform
    implements UniversalBlePeripheralCallback {
  static UniversalBlePeripheralPigeon? _instance;
  static UniversalBlePeripheralPigeon get instance =>
      _instance ??= UniversalBlePeripheralPigeon._();

  UniversalBlePeripheralPigeon._() {
    UniversalBlePeripheralCallback.setUp(this);
  }

  final _channel = UniversalBlePeripheralChannel();
  UniversalBleAndroidChannel? _androidChannelRef;

  UniversalBleAndroidChannel? get _androidChannel =>
      (kIsWeb || defaultTargetPlatform != TargetPlatform.android)
          ? null
          : _androidChannelRef ??= UniversalBleAndroidChannel();

  OnPeripheralReadRequest? _readRequestHandler;
  OnPeripheralWriteRequest? _writeRequestHandler;
  OnPeripheralDescriptorReadRequest? _descriptorReadRequestHandler;
  OnPeripheralDescriptorWriteRequest? _descriptorWriteRequestHandler;
  OnPeripheralReadRequestWithInstance? _readRequestHandlerWithInstance;
  OnPeripheralWriteRequestWithInstance? _writeRequestHandlerWithInstance;
  OnPeripheralDescriptorReadRequestWithInstance?
      _descriptorReadRequestHandlerWithInstance;
  OnPeripheralDescriptorWriteRequestWithInstance?
      _descriptorWriteRequestHandlerWithInstance;

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
      supportsManufacturerDataInAdvertisement: supported &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.windows),
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
    PeripheralPlatformConfig? platformConfig,
  }) async {
    await _ensureBluetoothAdvertisePermission();
    return _channel.startAdvertising(
      services.map((e) => BleUuidParser.string(e)).toList(),
      localName,
      timeout?.inMilliseconds,
      manufacturerData?.toUniversalManufacturerData(),
      platformConfig,
    );
  }

  @override
  Future<void> stopAdvertising() => _channel.stopAdvertising();

  @override
  Future<void> updateCharacteristicValue({
    required String characteristicId,
    String? instanceId,
    required Uint8List value,
    String? deviceId,
  }) {
    return _channel.updateCharacteristic(
      BleUuidParser.string(characteristicId),
      instanceId,
      value,
      deviceId?.toDeviceId(isAddress: hasAddressDeviceIds).native,
    );
  }

  @override
  Future<List<String>> getSubscribedClients(
    String characteristicId, {
    String? instanceId,
  }) async {
    final clients = await _channel.getSubscribedClients(
      BleUuidParser.string(characteristicId),
      instanceId,
    );
    // Emitted ids are canonical (see UniversalBlePeripheralPlatform).
    return clients
        .map((e) => e.toDeviceId(isAddress: hasAddressDeviceIds).canonical)
        .toList();
  }

  @override
  Future<int?> getMaximumNotifyLength(String deviceId) =>
      _channel.getMaximumNotifyLength(
        deviceId.toDeviceId(isAddress: hasAddressDeviceIds).native,
      );

  @override
  void setReadRequestHandler(OnPeripheralReadRequest? handler) =>
      _readRequestHandler = handler;

  @override
  void setWriteRequestHandler(OnPeripheralWriteRequest? handler) =>
      _writeRequestHandler = handler;

  @override
  void setDescriptorReadRequestHandler(
    OnPeripheralDescriptorReadRequest? handler,
  ) =>
      _descriptorReadRequestHandler = handler;

  @override
  void setDescriptorWriteRequestHandler(
    OnPeripheralDescriptorWriteRequest? handler,
  ) =>
      _descriptorWriteRequestHandler = handler;

  @override
  void setReadRequestHandlerWithInstance(
    OnPeripheralReadRequestWithInstance? handler,
  ) =>
      _readRequestHandlerWithInstance = handler;

  @override
  void setWriteRequestHandlerWithInstance(
    OnPeripheralWriteRequestWithInstance? handler,
  ) =>
      _writeRequestHandlerWithInstance = handler;

  @override
  void setDescriptorReadRequestHandlerWithInstance(
    OnPeripheralDescriptorReadRequestWithInstance? handler,
  ) =>
      _descriptorReadRequestHandlerWithInstance = handler;

  @override
  void setDescriptorWriteRequestHandlerWithInstance(
    OnPeripheralDescriptorWriteRequestWithInstance? handler,
  ) =>
      _descriptorWriteRequestHandlerWithInstance = handler;

  @override
  Future<void> onAdvertisingStateChange(
    PeripheralAdvertisingState state,
    String? error,
  ) async {
    updateAdvertisingState(BlePeripheralAdvertisingStateChanged(state, error));
  }

  @override
  Future<void> onCharacteristicSubscriptionChange(
    String deviceId,
    String characteristicId,
    String? characteristicInstanceId,
    bool isSubscribed,
    String? name,
  ) async {
    updateCharacteristicSubscription(
      BlePeripheralCharacteristicSubscriptionChanged(
        deviceId: deviceId,
        characteristicId: BleUuidParser.string(characteristicId),
        instanceId: characteristicInstanceId,
        isSubscribed: isSubscribed,
        name: name,
      ),
    );
  }

  @override
  Future<void> onConnectionStateChange(String deviceId, bool connected) async {
    updateConnectionState(
      BlePeripheralConnectionStateChanged(deviceId, connected),
    );
  }

  @override
  Future<void> onMtuChange(String deviceId, int mtu) async {
    updateMtu(BlePeripheralMtuChanged(deviceId, mtu));
  }

  @override
  Future<PeripheralReadRequestResult?> onReadRequest(
    String deviceId,
    String characteristicId,
    String? characteristicInstanceId,
    int offset,
    Uint8List? value,
  ) async {
    final canonicalId = deviceId
        .toDeviceId(isAddress: hasAddressDeviceIds)
        .canonical;
    final parsedCharacteristicId = BleUuidParser.string(characteristicId);
    final result = _readRequestHandlerWithInstance?.call(
          canonicalId,
          parsedCharacteristicId,
          characteristicInstanceId,
          offset,
          value,
        ) ??
        _readRequestHandler?.call(
          canonicalId,
          parsedCharacteristicId,
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
  Future<void> onServiceAdded(String serviceId, String? error) async {
    updateServiceAdded(
      BlePeripheralServiceAdded(BleUuidParser.string(serviceId), error),
    );
  }

  @override
  Future<PeripheralWriteRequestResult?> onWriteRequest(
    String deviceId,
    String characteristicId,
    String? characteristicInstanceId,
    int offset,
    Uint8List? value,
  ) async {
    final canonicalId = deviceId
        .toDeviceId(isAddress: hasAddressDeviceIds)
        .canonical;
    final parsedCharacteristicId = BleUuidParser.string(characteristicId);
    final result = _writeRequestHandlerWithInstance?.call(
          canonicalId,
          parsedCharacteristicId,
          characteristicInstanceId,
          offset,
          value,
        ) ??
        _writeRequestHandler?.call(
          canonicalId,
          parsedCharacteristicId,
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
  Future<PeripheralReadRequestResult?> onDescriptorReadRequest(
    String deviceId,
    String characteristicId,
    String? characteristicInstanceId,
    String descriptorId,
    int offset,
    Uint8List? value,
  ) async {
    final canonicalId = deviceId
        .toDeviceId(isAddress: hasAddressDeviceIds)
        .canonical;
    final parsedCharacteristicId = BleUuidParser.string(characteristicId);
    final parsedDescriptorId = BleUuidParser.string(descriptorId);
    final result = _descriptorReadRequestHandlerWithInstance?.call(
          canonicalId,
          parsedCharacteristicId,
          characteristicInstanceId,
          parsedDescriptorId,
          offset,
          value,
        ) ??
        _descriptorReadRequestHandler?.call(
          canonicalId,
          parsedCharacteristicId,
          parsedDescriptorId,
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
  Future<PeripheralWriteRequestResult?> onDescriptorWriteRequest(
    String deviceId,
    String characteristicId,
    String? characteristicInstanceId,
    String descriptorId,
    int offset,
    Uint8List? value,
  ) async {
    final canonicalId = deviceId
        .toDeviceId(isAddress: hasAddressDeviceIds)
        .canonical;
    final parsedCharacteristicId = BleUuidParser.string(characteristicId);
    final parsedDescriptorId = BleUuidParser.string(descriptorId);
    final result = _descriptorWriteRequestHandlerWithInstance?.call(
          canonicalId,
          parsedCharacteristicId,
          characteristicInstanceId,
          parsedDescriptorId,
          offset,
          value,
        ) ??
        _descriptorWriteRequestHandler?.call(
          canonicalId,
          parsedCharacteristicId,
          parsedDescriptorId,
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

  Future<void> _ensureBluetoothAdvertisePermission() async {
    if (await _hasBluetoothAdvertisePermission()) {
      return;
    }
    if (await _requestBluetoothAdvertisePermission()) {
      return;
    }
    throw PlatformException(
      code: 'bluetooth-advertise-permission-denied',
      message: 'Bluetooth advertise permission denied',
    );
  }

  Future<bool> _requestBluetoothAdvertisePermission() =>
      _androidChannel?.requestBluetoothAdvertisePermission() ??
      Future.value(true);

  Future<bool> _hasBluetoothAdvertisePermission() =>
      _androidChannel?.hasBluetoothAdvertisePermission() ?? Future.value(true);

  @override
  void dispose() {
    UniversalBlePeripheralCallback.setUp(null);
    _readRequestHandler = null;
    _writeRequestHandler = null;
    _descriptorReadRequestHandler = null;
    _descriptorWriteRequestHandler = null;
    _readRequestHandlerWithInstance = null;
    _writeRequestHandlerWithInstance = null;
    _descriptorReadRequestHandlerWithInstance = null;
    _descriptorWriteRequestHandlerWithInstance = null;
    super.dispose();
    if (identical(_instance, this)) {
      _instance = null;
    }
  }
}
