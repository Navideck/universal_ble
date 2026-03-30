import 'dart:async';
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
  bool _disposed = false;

  @override
  Future<void> initialize() => _channel.initialize();

  @override
  Future<bool> isSupported() => _channel.isSupported();

  @override
  Future<bool> isAdvertising() async =>
      (await _channel.isAdvertising()) ?? false;

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
    int? timeout,
    ManufacturerData? manufacturerData,
    bool addManufacturerDataInScanResponse = false,
  }) {
    return _channel.startAdvertising(
      services.map(BleUuidParser.string).toList(),
      localName,
      timeout,
      UniversalBlePeripheralMapper.toPigeonManufacturerData(manufacturerData),
      addManufacturerDataInScanResponse,
    );
  }

  @override
  Future<void> stopAdvertising() => _channel.stopAdvertising();

  @override
  Future<void> updateCharacteristic({
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
  Future<List<String>> getSubscribedCentrals(String characteristicId) =>
      _channel.getSubscribedCentrals(characteristicId);

  @override
  void onAdvertisingStatusUpdate(bool advertising, String? error) {
    super.advertisingStatusUpdateCallback?.call(advertising, error);
  }

  @override
  void onCharacteristicSubscriptionChange(
    String deviceId,
    String characteristicId,
    bool isSubscribed,
    String? name,
  ) {
    super.subscriptionChangeCallback?.call(
          deviceId,
          characteristicId,
          isSubscribed,
          name,
        );
  }

  @override
  void onConnectionStateChange(String deviceId, bool connected) {
    super.connectionStateChangeCallback?.call(deviceId, connected);
  }

  @override
  void onMtuChange(String deviceId, int mtu) {
    super.mtuChangeCallback?.call(deviceId, mtu);
  }

  @override
  pigeon.PeripheralReadRequestResult? onReadRequest(
    String deviceId,
    String characteristicId,
    int offset,
    Uint8List? value,
  ) {
    final result = super
        .readRequestCallback
        ?.call(deviceId, characteristicId, offset, value);
    if (result == null) return null;
    return pigeon.PeripheralReadRequestResult(
      value: result.value,
      offset: result.offset,
      status: result.status,
    );
  }

  @override
  void onServiceAdded(String serviceId, String? error) {
    super.serviceAddedCallback?.call(serviceId, error);
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
    final result = super.writeRequestCallback?.call(
          deviceId,
          characteristicId,
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
    if (identical(_instance, this)) {
      _instance = null;
    }
  }
}
