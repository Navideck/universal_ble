import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

typedef OnPeripheralReadRequest = BleReadRequestResult? Function(
  String deviceId,
  String characteristicId,
  int offset,
  Uint8List? value,
);
typedef OnPeripheralWriteRequest = BleWriteRequestResult? Function(
  String deviceId,
  String characteristicId,
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

class PeripheralServiceId {
  final String value;
  const PeripheralServiceId(this.value);
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

  void setRequestHandlers({
    OnPeripheralReadRequest? onReadRequest,
    OnPeripheralWriteRequest? onWriteRequest,
  });

  Future<bool> isFeatureSupported();
  Future<UniversalBlePeripheralReadinessState> getReadinessState();
  Future<UniversalBlePeripheralAdvertisingState> getAdvertisingState();

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
    required String characteristicId,
    required Uint8List value,
    PeripheralUpdateTarget target = const PeripheralUpdateAllSubscribed(),
  });

  /// Returns GATT central device ids currently subscribed to [characteristicId].
  Future<List<String>> getSubscribedCentrals(String characteristicId);

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
  void setRequestHandlers({
    OnPeripheralReadRequest? onReadRequest,
    OnPeripheralWriteRequest? onWriteRequest,
  }) {}

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
  Future<bool> isFeatureSupported() async => false;

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
    required String characteristicId,
    required Uint8List value,
    PeripheralUpdateTarget target = const PeripheralUpdateAllSubscribed(),
  }) async {
    throw _notSupported();
  }

  @override
  Future<List<String>> getSubscribedCentrals(String characteristicId) async {
    throw _notSupported();
  }
}
