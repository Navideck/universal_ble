import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

/// Central mode callbacks
///
typedef OnConnectionChange =
    void Function(String deviceId, bool isConnected, String? error);

typedef OnValueChange =
    void Function(
      String deviceId,
      String characteristicId,
      Uint8List value,
      int? timestamp,
    );

typedef OnScanResult = void Function(BleDevice scanResult);

typedef OnAvailabilityChange = void Function(AvailabilityState state);

typedef OnPairingStateChange = void Function(String deviceId, bool isPaired);

typedef OnQueueUpdate = void Function(String id, int remainingQueueItems);

/// Peripheral mode callbacks
///
typedef OnPeripheralReadRequest =
    PeripheralReadRequestResult? Function(
      String deviceId,
      String characteristicId,
      int offset,
      Uint8List? value,
    );

typedef OnPeripheralWriteRequest =
    PeripheralWriteRequestResult? Function(
      String deviceId,
      String characteristicId,
      int offset,
      Uint8List? value,
    );

typedef OnPeripheralDescriptorReadRequest =
    PeripheralReadRequestResult? Function(
      String deviceId,
      String characteristicId,
      String descriptorId,
      int offset,
      Uint8List? value,
    );

typedef OnPeripheralDescriptorWriteRequest =
    PeripheralWriteRequestResult? Function(
      String deviceId,
      String characteristicId,
      String descriptorId,
      int offset,
      Uint8List? value,
    );
