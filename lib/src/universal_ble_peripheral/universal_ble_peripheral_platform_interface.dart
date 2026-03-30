import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

typedef OnPeripheralReadRequest = BleReadRequestResult? Function(
  String deviceId,
  PeripheralCharacteristicId characteristicId,
  int offset,
  Uint8List? value,
);
typedef OnPeripheralWriteRequest = BleWriteRequestResult? Function(
  String deviceId,
  PeripheralCharacteristicId characteristicId,
  int offset,
  Uint8List? value,
);
typedef OnPeripheralDescriptorReadRequest = BleReadRequestResult? Function(
  String deviceId,
  PeripheralCharacteristicId characteristicId,
  PeripheralDescriptorId descriptorId,
  int offset,
  Uint8List? value,
);
typedef OnPeripheralDescriptorWriteRequest = BleWriteRequestResult? Function(
  String deviceId,
  PeripheralCharacteristicId characteristicId,
  PeripheralDescriptorId descriptorId,
  int offset,
  Uint8List? value,
);

enum UniversalBlePeripheralReadinessState {
  unknown,
  ready,
  bluetoothOff,
  unauthorized,
  unsupported,
}

enum UniversalBlePeripheralAdvertisingState {
  idle,
  starting,
  advertising,
  stopping,
  error,
}

sealed class UniversalBlePeripheralEvent {}

class UniversalBlePeripheralAdvertisingStateChanged
    extends UniversalBlePeripheralEvent {
  final UniversalBlePeripheralAdvertisingState state;
  final String? error;
  UniversalBlePeripheralAdvertisingStateChanged(this.state, this.error);
}

class UniversalBlePeripheralCharacteristicSubscriptionChanged
    extends UniversalBlePeripheralEvent {
  final String deviceId;
  final String characteristicId;
  final bool isSubscribed;
  final String? name;
  UniversalBlePeripheralCharacteristicSubscriptionChanged({
    required this.deviceId,
    required this.characteristicId,
    required this.isSubscribed,
    required this.name,
  });
}

class UniversalBlePeripheralConnectionStateChanged
    extends UniversalBlePeripheralEvent {
  final String deviceId;
  final bool connected;
  UniversalBlePeripheralConnectionStateChanged(this.deviceId, this.connected);
}

class UniversalBlePeripheralServiceAdded extends UniversalBlePeripheralEvent {
  final String serviceId;
  final String? error;
  UniversalBlePeripheralServiceAdded(this.serviceId, this.error);
}

class UniversalBlePeripheralMtuChanged extends UniversalBlePeripheralEvent {
  final String deviceId;
  final int mtu;
  UniversalBlePeripheralMtuChanged(this.deviceId, this.mtu);
}

class UniversalBlePeripheralCapabilities {
  final bool supportsPeripheralMode;
  final bool supportsManufacturerDataInAdvertisement;
  final bool supportsManufacturerDataInScanResponse;
  final bool supportsServiceDataInAdvertisement;
  final bool supportsServiceDataInScanResponse;
  final bool supportsTargetedCharacteristicUpdate;
  final bool supportsAdvertisingTimeout;

  const UniversalBlePeripheralCapabilities({
    required this.supportsPeripheralMode,
    required this.supportsManufacturerDataInAdvertisement,
    required this.supportsManufacturerDataInScanResponse,
    required this.supportsServiceDataInAdvertisement,
    required this.supportsServiceDataInScanResponse,
    required this.supportsTargetedCharacteristicUpdate,
    required this.supportsAdvertisingTimeout,
  });
}

class PeripheralServiceId {
  final String value;
  const PeripheralServiceId(this.value);
}

class PeripheralCharacteristicId {
  final String value;
  const PeripheralCharacteristicId(this.value);
}

class PeripheralDescriptorId {
  final String value;
  const PeripheralDescriptorId(this.value);
}

class PeripheralRequestHandlers {
  final OnPeripheralReadRequest? onReadRequest;
  final OnPeripheralWriteRequest? onWriteRequest;
  final OnPeripheralDescriptorReadRequest? onDescriptorReadRequest;
  final OnPeripheralDescriptorWriteRequest? onDescriptorWriteRequest;

  const PeripheralRequestHandlers({
    this.onReadRequest,
    this.onWriteRequest,
    this.onDescriptorReadRequest,
    this.onDescriptorWriteRequest,
  });
}

sealed class PeripheralUpdateTarget {
  const PeripheralUpdateTarget();
}

class PeripheralUpdateAllSubscribed extends PeripheralUpdateTarget {
  const PeripheralUpdateAllSubscribed();
}

class PeripheralUpdateSingleDevice extends PeripheralUpdateTarget {
  final String deviceId;
  const PeripheralUpdateSingleDevice(this.deviceId);
}

abstract class UniversalBlePeripheralPlatform {
  Stream<UniversalBlePeripheralEvent> get eventStream;

  void setRequestHandlers(PeripheralRequestHandlers handlers);

  Future<UniversalBlePeripheralReadinessState> getReadinessState();
  Future<UniversalBlePeripheralAdvertisingState> getAdvertisingState();
  Future<UniversalBlePeripheralCapabilities> getStaticCapabilities();

  Future<void> addService(
    BleService service, {
    bool primary = true,
    Duration? timeout,
  });

  Future<void> removeService(PeripheralServiceId serviceId);
  Future<void> clearServices();
  Future<List<PeripheralServiceId>> getServices();
  Future<void> startAdvertising({
    required List<PeripheralServiceId> services,
    String? localName,
    int? timeout,
    ManufacturerData? manufacturerData,
    bool addManufacturerDataInScanResponse = false,
  });
  Future<void> stopAdvertising();
  Future<void> updateCharacteristicValue({
    required PeripheralCharacteristicId characteristicId,
    required Uint8List value,
    PeripheralUpdateTarget target = const PeripheralUpdateAllSubscribed(),
  });

  /// Returns GATT client device ids currently subscribed to [characteristicId].
  Future<List<String>> getSubscribedClients(PeripheralCharacteristicId characteristicId);
  Future<int?> getMaximumNotifyLength(String deviceId);

  /// Called when this platform implementation is being replaced.
  ///
  /// Default is no-op so existing custom implementations remain compatible.
  void dispose() {}
}

class UniversalBlePeripheralUnsupported extends UniversalBlePeripheralPlatform {
  UnsupportedError _notSupported() =>
      UnsupportedError('BLE peripheral mode is not supported on this platform');

  @override
  Stream<UniversalBlePeripheralEvent> get eventStream =>
      const Stream<UniversalBlePeripheralEvent>.empty();

  @override
  void setRequestHandlers(PeripheralRequestHandlers handlers) {}

  @override
  Future<void> addService(
    BleService service, {
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
  Future<List<PeripheralServiceId>> getServices() async {
    throw _notSupported();
  }

  @override
  Future<UniversalBlePeripheralAdvertisingState> getAdvertisingState() async {
    throw _notSupported();
  }

  @override
  Future<UniversalBlePeripheralCapabilities> getStaticCapabilities() async {
    return const UniversalBlePeripheralCapabilities(
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
  Future<UniversalBlePeripheralReadinessState> getReadinessState() async {
    return UniversalBlePeripheralReadinessState.unsupported;
  }

  @override
  Future<void> removeService(PeripheralServiceId serviceId) async {
    throw _notSupported();
  }

  @override
  Future<void> startAdvertising({
    required List<PeripheralServiceId> services,
    String? localName,
    int? timeout,
    ManufacturerData? manufacturerData,
    bool addManufacturerDataInScanResponse = false,
  }) async {
    throw _notSupported();
  }

  @override
  Future<void> stopAdvertising() async {
    throw _notSupported();
  }

  @override
  Future<void> updateCharacteristicValue({
    required PeripheralCharacteristicId characteristicId,
    required Uint8List value,
    PeripheralUpdateTarget target = const PeripheralUpdateAllSubscribed(),
  }) async {
    throw _notSupported();
  }

  @override
  Future<List<String>> getSubscribedClients(PeripheralCharacteristicId characteristicId) async {
    throw _notSupported();
  }

  @override
  Future<int?> getMaximumNotifyLength(String deviceId) async {
    return null;
  }
}
