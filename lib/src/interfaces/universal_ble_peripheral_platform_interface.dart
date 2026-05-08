import 'dart:typed_data';

import 'package:universal_ble/src/utils/universal_ble_stream_controller.dart';
import 'package:universal_ble/universal_ble.dart';

abstract class UniversalBlePeripheralPlatform {
  final _blePeripheralStreamHandler = _BlePeripheralStreamHandler();

  Stream<BlePeripheralAdvertisingStateChanged> get advertisingStateStream =>
      _blePeripheralStreamHandler.advertisingStateStreamController.stream;

  Stream<BlePeripheralCharacteristicSubscriptionChanged>
  get characteristicSubscriptionStream => _blePeripheralStreamHandler
      .characteristicSubscriptionStreamController
      .stream;

  Stream<BlePeripheralConnectionStateChanged> get connectionStateStream =>
      _blePeripheralStreamHandler.connectionStateStreamController.stream;

  Stream<BlePeripheralServiceAdded> get serviceAddedStream =>
      _blePeripheralStreamHandler.serviceAddedStreamController.stream;

  Stream<BlePeripheralMtuChanged> get mtuChangedStream =>
      _blePeripheralStreamHandler.mtuChangedStreamController.stream;

  void setReadRequestHandler(OnPeripheralReadRequest handler);

  void setWriteRequestHandler(OnPeripheralWriteRequest handler);

  void setDescriptorReadRequestHandler(
    OnPeripheralDescriptorReadRequest handler,
  );

  void setDescriptorWriteRequestHandler(
    OnPeripheralDescriptorWriteRequest handler,
  );

  Future<PeripheralReadinessState> getAvailabilityState();

  Future<PeripheralAdvertisingState> getAdvertisingState();

  Future<BlePeripheralCapabilities> getCapabilities();

  Future<void> addService(PeripheralService service, {Duration? timeout});

  Future<void> removeService(String serviceId);

  Future<void> clearServices();

  Future<List<String>> getServices();

  Future<void> startAdvertising({
    required List<String> services,
    String? localName,
    Duration? timeout,
    ManufacturerData? manufacturerData,
    PeripheralPlatformConfig? platformConfig,
  });

  Future<void> stopAdvertising();

  Future<void> updateCharacteristicValue({
    required String characteristicId,
    required Uint8List value,
    String? deviceId,
  });

  /// Returns GATT client device ids currently subscribed to [characteristicId].
  Future<List<String>> getSubscribedClients(String characteristicId);

  Future<int?> getMaximumNotifyLength(String deviceId);

  /// Push advertising state update to stream listeners.
  void updateAdvertisingState(BlePeripheralAdvertisingStateChanged event) {
    _blePeripheralStreamHandler.advertisingStateStreamController.add(event);
  }

  /// Push characteristic subscription update to stream listeners.
  void updateCharacteristicSubscription(
    BlePeripheralCharacteristicSubscriptionChanged event,
  ) {
    _blePeripheralStreamHandler.characteristicSubscriptionStreamController.add(
      event,
    );
  }

  /// Push connection state update to stream listeners.
  void updateConnectionState(BlePeripheralConnectionStateChanged event) {
    _blePeripheralStreamHandler.connectionStateStreamController.add(event);
  }

  /// Push service added update to stream listeners.
  void updateServiceAdded(BlePeripheralServiceAdded event) {
    _blePeripheralStreamHandler.serviceAddedStreamController.add(event);
  }

  /// Push MTU update to stream listeners.
  void updateMtu(BlePeripheralMtuChanged event) {
    _blePeripheralStreamHandler.mtuChangedStreamController.add(event);
  }

  /// Called when this platform implementation is being replaced.
  ///
  /// Default is no-op so existing custom implementations remain compatible.
  void dispose() {
    _blePeripheralStreamHandler.dispose();
  }
}

class UniversalBlePeripheralUnsupported extends UniversalBlePeripheralPlatform {
  @override
  Future<void> addService(
    PeripheralService service, {
    bool primary = true,
    Duration? timeout,
  }) async {
    throw _notSupported();
  }

  @override
  Future<void> clearServices() async {
    throw _notSupported();
  }

  @override
  Future<List<String>> getServices() async {
    throw _notSupported();
  }

  @override
  Future<PeripheralAdvertisingState> getAdvertisingState() async {
    throw _notSupported();
  }

  @override
  Future<BlePeripheralCapabilities> getCapabilities() async {
    return const BlePeripheralCapabilities(
      supportsPeripheralMode: false,
      supportsManufacturerDataInAdvertisement: false,
      supportsManufacturerDataInScanResponse: false,
      supportsServiceDataInAdvertisement: false,
      supportsServiceDataInScanResponse: false,
      supportsTargetedCharacteristicUpdate: false,
      supportsAdvertisingTimeout: false,
    );
  }

  @override
  Future<PeripheralReadinessState> getAvailabilityState() async {
    return PeripheralReadinessState.unsupported;
  }

  @override
  Future<void> removeService(String serviceId) async {
    throw _notSupported();
  }

  @override
  Future<void> startAdvertising({
    required List<String> services,
    String? localName,
    Duration? timeout,
    ManufacturerData? manufacturerData,
    PeripheralPlatformConfig? platformConfig,
  }) async {
    throw _notSupported();
  }

  @override
  Future<void> stopAdvertising() async {
    throw _notSupported();
  }

  @override
  Future<void> updateCharacteristicValue({
    required String characteristicId,
    required Uint8List value,
    String? deviceId,
  }) async {
    throw _notSupported();
  }

  @override
  Future<List<String>> getSubscribedClients(String characteristicId) async {
    throw _notSupported();
  }

  @override
  Future<int?> getMaximumNotifyLength(String deviceId) async {
    return null;
  }

  @override
  void setReadRequestHandler(OnPeripheralReadRequest handler) {}

  @override
  void setWriteRequestHandler(OnPeripheralWriteRequest handler) {}

  @override
  void setDescriptorReadRequestHandler(
    OnPeripheralDescriptorReadRequest handler,
  ) {}

  @override
  void setDescriptorWriteRequestHandler(
    OnPeripheralDescriptorWriteRequest handler,
  ) {}

  UnsupportedError _notSupported() =>
      UnsupportedError('BLE peripheral mode is not supported on this platform');
}

class _BlePeripheralStreamHandler {
  final advertisingStateStreamController =
      UniversalBleStreamController<BlePeripheralAdvertisingStateChanged>();
  final characteristicSubscriptionStreamController =
      UniversalBleStreamController<
        BlePeripheralCharacteristicSubscriptionChanged
      >();
  final connectionStateStreamController =
      UniversalBleStreamController<BlePeripheralConnectionStateChanged>();
  final serviceAddedStreamController =
      UniversalBleStreamController<BlePeripheralServiceAdded>();
  final mtuChangedStreamController =
      UniversalBleStreamController<BlePeripheralMtuChanged>();

  void dispose() {
    advertisingStateStreamController.close();
    characteristicSubscriptionStreamController.close();
    connectionStateStreamController.close();
    serviceAddedStreamController.close();
    mtuChangedStreamController.close();
  }
}
