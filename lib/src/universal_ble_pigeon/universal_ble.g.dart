// Autogenerated from Pigeon (v18.0.1), do not edit directly.
// See also: https://pub.dev/packages/pigeon
// ignore_for_file: public_member_api_docs, non_constant_identifier_names, avoid_as, unused_import, unnecessary_parenthesis, prefer_null_aware_operators, omit_local_variable_types, unused_shown_name, unnecessary_import, no_leading_underscores_for_local_identifiers

import 'dart:async';
import 'dart:typed_data' show Float64List, Int32List, Int64List, Uint8List;

import 'package:flutter/foundation.dart' show ReadBuffer, WriteBuffer;
import 'package:flutter/services.dart';

PlatformException _createConnectionError(String channelName) {
  return PlatformException(
    code: 'channel-error',
    message: 'Unable to establish connection on channel: "$channelName".',
  );
}

List<Object?> wrapResponse({Object? result, PlatformException? error, bool empty = false}) {
  if (empty) {
    return <Object?>[];
  }
  if (error == null) {
    return <Object?>[result];
  }
  return <Object?>[error.code, error.message, error.details];
}

class UniversalBleScanResult {
  UniversalBleScanResult({
    required this.deviceId,
    this.name,
    this.isPaired,
    this.rssi,
    this.manufacturerData,
    this.manufacturerDataHead,
    this.services,
  });

  String deviceId;

  String? name;

  bool? isPaired;

  int? rssi;

  Uint8List? manufacturerData;

  Uint8List? manufacturerDataHead;

  List<String?>? services;

  Object encode() {
    return <Object?>[
      deviceId,
      name,
      isPaired,
      rssi,
      manufacturerData,
      manufacturerDataHead,
      services,
    ];
  }

  static UniversalBleScanResult decode(Object result) {
    result as List<Object?>;
    return UniversalBleScanResult(
      deviceId: result[0]! as String,
      name: result[1] as String?,
      isPaired: result[2] as bool?,
      rssi: result[3] as int?,
      manufacturerData: result[4] as Uint8List?,
      manufacturerDataHead: result[5] as Uint8List?,
      services: (result[6] as List<Object?>?)?.cast<String?>(),
    );
  }
}

class UniversalBleService {
  UniversalBleService({
    required this.uuid,
    this.characteristics,
  });

  String uuid;

  List<UniversalBleCharacteristic?>? characteristics;

  Object encode() {
    return <Object?>[
      uuid,
      characteristics,
    ];
  }

  static UniversalBleService decode(Object result) {
    result as List<Object?>;
    return UniversalBleService(
      uuid: result[0]! as String,
      characteristics: (result[1] as List<Object?>?)?.cast<UniversalBleCharacteristic?>(),
    );
  }
}

class UniversalBleCharacteristic {
  UniversalBleCharacteristic({
    required this.uuid,
    required this.properties,
  });

  String uuid;

  List<int?> properties;

  Object encode() {
    return <Object?>[
      uuid,
      properties,
    ];
  }

  static UniversalBleCharacteristic decode(Object result) {
    result as List<Object?>;
    return UniversalBleCharacteristic(
      uuid: result[0]! as String,
      properties: (result[1] as List<Object?>?)!.cast<int?>(),
    );
  }
}

/// Scan Filters
class UniversalScanFilter {
  UniversalScanFilter({
    required this.withServices,
    required this.withManufacturerData,
  });

  List<String?> withServices;

  List<UniversalManufacturerDataFilter?> withManufacturerData;

  Object encode() {
    return <Object?>[
      withServices,
      withManufacturerData,
    ];
  }

  static UniversalScanFilter decode(Object result) {
    result as List<Object?>;
    return UniversalScanFilter(
      withServices: (result[0] as List<Object?>?)!.cast<String?>(),
      withManufacturerData: (result[1] as List<Object?>?)!.cast<UniversalManufacturerDataFilter?>(),
    );
  }
}

class UniversalManufacturerDataFilter {
  UniversalManufacturerDataFilter({
    this.companyIdentifier,
    this.data,
    this.mask,
  });

  int? companyIdentifier;

  Uint8List? data;

  Uint8List? mask;

  Object encode() {
    return <Object?>[
      companyIdentifier,
      data,
      mask,
    ];
  }

  static UniversalManufacturerDataFilter decode(Object result) {
    result as List<Object?>;
    return UniversalManufacturerDataFilter(
      companyIdentifier: result[0] as int?,
      data: result[1] as Uint8List?,
      mask: result[2] as Uint8List?,
    );
  }
}

class _UniversalBlePlatformChannelCodec extends StandardMessageCodec {
  const _UniversalBlePlatformChannelCodec();
  @override
  void writeValue(WriteBuffer buffer, Object? value) {
    if (value is UniversalBleCharacteristic) {
      buffer.putUint8(128);
      writeValue(buffer, value.encode());
    } else if (value is UniversalBleScanResult) {
      buffer.putUint8(129);
      writeValue(buffer, value.encode());
    } else if (value is UniversalBleService) {
      buffer.putUint8(130);
      writeValue(buffer, value.encode());
    } else if (value is UniversalManufacturerDataFilter) {
      buffer.putUint8(131);
      writeValue(buffer, value.encode());
    } else if (value is UniversalScanFilter) {
      buffer.putUint8(132);
      writeValue(buffer, value.encode());
    } else {
      super.writeValue(buffer, value);
    }
  }

  @override
  Object? readValueOfType(int type, ReadBuffer buffer) {
    switch (type) {
      case 128: 
        return UniversalBleCharacteristic.decode(readValue(buffer)!);
      case 129: 
        return UniversalBleScanResult.decode(readValue(buffer)!);
      case 130: 
        return UniversalBleService.decode(readValue(buffer)!);
      case 131: 
        return UniversalManufacturerDataFilter.decode(readValue(buffer)!);
      case 132: 
        return UniversalScanFilter.decode(readValue(buffer)!);
      default:
        return super.readValueOfType(type, buffer);
    }
  }
}

/// Flutter -> Native
class UniversalBlePlatformChannel {
  /// Constructor for [UniversalBlePlatformChannel].  The [binaryMessenger] named argument is
  /// available for dependency injection.  If it is left null, the default
  /// BinaryMessenger will be used which routes to the host platform.
  UniversalBlePlatformChannel({BinaryMessenger? binaryMessenger, String messageChannelSuffix = ''})
      : __pigeon_binaryMessenger = binaryMessenger,
        __pigeon_messageChannelSuffix = messageChannelSuffix.isNotEmpty ? '.$messageChannelSuffix' : '';
  final BinaryMessenger? __pigeon_binaryMessenger;

  static const MessageCodec<Object?> pigeonChannelCodec = _UniversalBlePlatformChannelCodec();

  final String __pigeon_messageChannelSuffix;

  Future<int> getBluetoothAvailabilityState() async {
    final String __pigeon_channelName = 'dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.getBluetoothAvailabilityState$__pigeon_messageChannelSuffix';
    final BasicMessageChannel<Object?> __pigeon_channel = BasicMessageChannel<Object?>(
      __pigeon_channelName,
      pigeonChannelCodec,
      binaryMessenger: __pigeon_binaryMessenger,
    );
    final List<Object?>? __pigeon_replyList =
        await __pigeon_channel.send(null) as List<Object?>?;
    if (__pigeon_replyList == null) {
      throw _createConnectionError(__pigeon_channelName);
    } else if (__pigeon_replyList.length > 1) {
      throw PlatformException(
        code: __pigeon_replyList[0]! as String,
        message: __pigeon_replyList[1] as String?,
        details: __pigeon_replyList[2],
      );
    } else if (__pigeon_replyList[0] == null) {
      throw PlatformException(
        code: 'null-error',
        message: 'Host platform returned null value for non-null return value.',
      );
    } else {
      return (__pigeon_replyList[0] as int?)!;
    }
  }

  Future<bool> enableBluetooth() async {
    final String __pigeon_channelName = 'dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.enableBluetooth$__pigeon_messageChannelSuffix';
    final BasicMessageChannel<Object?> __pigeon_channel = BasicMessageChannel<Object?>(
      __pigeon_channelName,
      pigeonChannelCodec,
      binaryMessenger: __pigeon_binaryMessenger,
    );
    final List<Object?>? __pigeon_replyList =
        await __pigeon_channel.send(null) as List<Object?>?;
    if (__pigeon_replyList == null) {
      throw _createConnectionError(__pigeon_channelName);
    } else if (__pigeon_replyList.length > 1) {
      throw PlatformException(
        code: __pigeon_replyList[0]! as String,
        message: __pigeon_replyList[1] as String?,
        details: __pigeon_replyList[2],
      );
    } else if (__pigeon_replyList[0] == null) {
      throw PlatformException(
        code: 'null-error',
        message: 'Host platform returned null value for non-null return value.',
      );
    } else {
      return (__pigeon_replyList[0] as bool?)!;
    }
  }

  Future<void> startScan(UniversalScanFilter? filter) async {
    final String __pigeon_channelName = 'dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.startScan$__pigeon_messageChannelSuffix';
    final BasicMessageChannel<Object?> __pigeon_channel = BasicMessageChannel<Object?>(
      __pigeon_channelName,
      pigeonChannelCodec,
      binaryMessenger: __pigeon_binaryMessenger,
    );
    final List<Object?>? __pigeon_replyList =
        await __pigeon_channel.send(<Object?>[filter]) as List<Object?>?;
    if (__pigeon_replyList == null) {
      throw _createConnectionError(__pigeon_channelName);
    } else if (__pigeon_replyList.length > 1) {
      throw PlatformException(
        code: __pigeon_replyList[0]! as String,
        message: __pigeon_replyList[1] as String?,
        details: __pigeon_replyList[2],
      );
    } else {
      return;
    }
  }

  Future<void> stopScan() async {
    final String __pigeon_channelName = 'dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.stopScan$__pigeon_messageChannelSuffix';
    final BasicMessageChannel<Object?> __pigeon_channel = BasicMessageChannel<Object?>(
      __pigeon_channelName,
      pigeonChannelCodec,
      binaryMessenger: __pigeon_binaryMessenger,
    );
    final List<Object?>? __pigeon_replyList =
        await __pigeon_channel.send(null) as List<Object?>?;
    if (__pigeon_replyList == null) {
      throw _createConnectionError(__pigeon_channelName);
    } else if (__pigeon_replyList.length > 1) {
      throw PlatformException(
        code: __pigeon_replyList[0]! as String,
        message: __pigeon_replyList[1] as String?,
        details: __pigeon_replyList[2],
      );
    } else {
      return;
    }
  }

  Future<void> connect(String deviceId) async {
    final String __pigeon_channelName = 'dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.connect$__pigeon_messageChannelSuffix';
    final BasicMessageChannel<Object?> __pigeon_channel = BasicMessageChannel<Object?>(
      __pigeon_channelName,
      pigeonChannelCodec,
      binaryMessenger: __pigeon_binaryMessenger,
    );
    final List<Object?>? __pigeon_replyList =
        await __pigeon_channel.send(<Object?>[deviceId]) as List<Object?>?;
    if (__pigeon_replyList == null) {
      throw _createConnectionError(__pigeon_channelName);
    } else if (__pigeon_replyList.length > 1) {
      throw PlatformException(
        code: __pigeon_replyList[0]! as String,
        message: __pigeon_replyList[1] as String?,
        details: __pigeon_replyList[2],
      );
    } else {
      return;
    }
  }

  Future<void> disconnect(String deviceId) async {
    final String __pigeon_channelName = 'dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.disconnect$__pigeon_messageChannelSuffix';
    final BasicMessageChannel<Object?> __pigeon_channel = BasicMessageChannel<Object?>(
      __pigeon_channelName,
      pigeonChannelCodec,
      binaryMessenger: __pigeon_binaryMessenger,
    );
    final List<Object?>? __pigeon_replyList =
        await __pigeon_channel.send(<Object?>[deviceId]) as List<Object?>?;
    if (__pigeon_replyList == null) {
      throw _createConnectionError(__pigeon_channelName);
    } else if (__pigeon_replyList.length > 1) {
      throw PlatformException(
        code: __pigeon_replyList[0]! as String,
        message: __pigeon_replyList[1] as String?,
        details: __pigeon_replyList[2],
      );
    } else {
      return;
    }
  }

  Future<void> setNotifiable(String deviceId, String service, String characteristic, int bleInputProperty) async {
    final String __pigeon_channelName = 'dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.setNotifiable$__pigeon_messageChannelSuffix';
    final BasicMessageChannel<Object?> __pigeon_channel = BasicMessageChannel<Object?>(
      __pigeon_channelName,
      pigeonChannelCodec,
      binaryMessenger: __pigeon_binaryMessenger,
    );
    final List<Object?>? __pigeon_replyList =
        await __pigeon_channel.send(<Object?>[deviceId, service, characteristic, bleInputProperty]) as List<Object?>?;
    if (__pigeon_replyList == null) {
      throw _createConnectionError(__pigeon_channelName);
    } else if (__pigeon_replyList.length > 1) {
      throw PlatformException(
        code: __pigeon_replyList[0]! as String,
        message: __pigeon_replyList[1] as String?,
        details: __pigeon_replyList[2],
      );
    } else {
      return;
    }
  }

  Future<List<UniversalBleService?>> discoverServices(String deviceId) async {
    final String __pigeon_channelName = 'dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.discoverServices$__pigeon_messageChannelSuffix';
    final BasicMessageChannel<Object?> __pigeon_channel = BasicMessageChannel<Object?>(
      __pigeon_channelName,
      pigeonChannelCodec,
      binaryMessenger: __pigeon_binaryMessenger,
    );
    final List<Object?>? __pigeon_replyList =
        await __pigeon_channel.send(<Object?>[deviceId]) as List<Object?>?;
    if (__pigeon_replyList == null) {
      throw _createConnectionError(__pigeon_channelName);
    } else if (__pigeon_replyList.length > 1) {
      throw PlatformException(
        code: __pigeon_replyList[0]! as String,
        message: __pigeon_replyList[1] as String?,
        details: __pigeon_replyList[2],
      );
    } else if (__pigeon_replyList[0] == null) {
      throw PlatformException(
        code: 'null-error',
        message: 'Host platform returned null value for non-null return value.',
      );
    } else {
      return (__pigeon_replyList[0] as List<Object?>?)!.cast<UniversalBleService?>();
    }
  }

  Future<Uint8List> readValue(String deviceId, String service, String characteristic) async {
    final String __pigeon_channelName = 'dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.readValue$__pigeon_messageChannelSuffix';
    final BasicMessageChannel<Object?> __pigeon_channel = BasicMessageChannel<Object?>(
      __pigeon_channelName,
      pigeonChannelCodec,
      binaryMessenger: __pigeon_binaryMessenger,
    );
    final List<Object?>? __pigeon_replyList =
        await __pigeon_channel.send(<Object?>[deviceId, service, characteristic]) as List<Object?>?;
    if (__pigeon_replyList == null) {
      throw _createConnectionError(__pigeon_channelName);
    } else if (__pigeon_replyList.length > 1) {
      throw PlatformException(
        code: __pigeon_replyList[0]! as String,
        message: __pigeon_replyList[1] as String?,
        details: __pigeon_replyList[2],
      );
    } else if (__pigeon_replyList[0] == null) {
      throw PlatformException(
        code: 'null-error',
        message: 'Host platform returned null value for non-null return value.',
      );
    } else {
      return (__pigeon_replyList[0] as Uint8List?)!;
    }
  }

  Future<int> requestMtu(String deviceId, int expectedMtu) async {
    final String __pigeon_channelName = 'dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.requestMtu$__pigeon_messageChannelSuffix';
    final BasicMessageChannel<Object?> __pigeon_channel = BasicMessageChannel<Object?>(
      __pigeon_channelName,
      pigeonChannelCodec,
      binaryMessenger: __pigeon_binaryMessenger,
    );
    final List<Object?>? __pigeon_replyList =
        await __pigeon_channel.send(<Object?>[deviceId, expectedMtu]) as List<Object?>?;
    if (__pigeon_replyList == null) {
      throw _createConnectionError(__pigeon_channelName);
    } else if (__pigeon_replyList.length > 1) {
      throw PlatformException(
        code: __pigeon_replyList[0]! as String,
        message: __pigeon_replyList[1] as String?,
        details: __pigeon_replyList[2],
      );
    } else if (__pigeon_replyList[0] == null) {
      throw PlatformException(
        code: 'null-error',
        message: 'Host platform returned null value for non-null return value.',
      );
    } else {
      return (__pigeon_replyList[0] as int?)!;
    }
  }

  Future<void> writeValue(String deviceId, String service, String characteristic, Uint8List value, int bleOutputProperty) async {
    final String __pigeon_channelName = 'dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.writeValue$__pigeon_messageChannelSuffix';
    final BasicMessageChannel<Object?> __pigeon_channel = BasicMessageChannel<Object?>(
      __pigeon_channelName,
      pigeonChannelCodec,
      binaryMessenger: __pigeon_binaryMessenger,
    );
    final List<Object?>? __pigeon_replyList =
        await __pigeon_channel.send(<Object?>[deviceId, service, characteristic, value, bleOutputProperty]) as List<Object?>?;
    if (__pigeon_replyList == null) {
      throw _createConnectionError(__pigeon_channelName);
    } else if (__pigeon_replyList.length > 1) {
      throw PlatformException(
        code: __pigeon_replyList[0]! as String,
        message: __pigeon_replyList[1] as String?,
        details: __pigeon_replyList[2],
      );
    } else {
      return;
    }
  }

  Future<bool> isPaired(String deviceId) async {
    final String __pigeon_channelName = 'dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.isPaired$__pigeon_messageChannelSuffix';
    final BasicMessageChannel<Object?> __pigeon_channel = BasicMessageChannel<Object?>(
      __pigeon_channelName,
      pigeonChannelCodec,
      binaryMessenger: __pigeon_binaryMessenger,
    );
    final List<Object?>? __pigeon_replyList =
        await __pigeon_channel.send(<Object?>[deviceId]) as List<Object?>?;
    if (__pigeon_replyList == null) {
      throw _createConnectionError(__pigeon_channelName);
    } else if (__pigeon_replyList.length > 1) {
      throw PlatformException(
        code: __pigeon_replyList[0]! as String,
        message: __pigeon_replyList[1] as String?,
        details: __pigeon_replyList[2],
      );
    } else if (__pigeon_replyList[0] == null) {
      throw PlatformException(
        code: 'null-error',
        message: 'Host platform returned null value for non-null return value.',
      );
    } else {
      return (__pigeon_replyList[0] as bool?)!;
    }
  }

  Future<void> pair(String deviceId) async {
    final String __pigeon_channelName = 'dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.pair$__pigeon_messageChannelSuffix';
    final BasicMessageChannel<Object?> __pigeon_channel = BasicMessageChannel<Object?>(
      __pigeon_channelName,
      pigeonChannelCodec,
      binaryMessenger: __pigeon_binaryMessenger,
    );
    final List<Object?>? __pigeon_replyList =
        await __pigeon_channel.send(<Object?>[deviceId]) as List<Object?>?;
    if (__pigeon_replyList == null) {
      throw _createConnectionError(__pigeon_channelName);
    } else if (__pigeon_replyList.length > 1) {
      throw PlatformException(
        code: __pigeon_replyList[0]! as String,
        message: __pigeon_replyList[1] as String?,
        details: __pigeon_replyList[2],
      );
    } else {
      return;
    }
  }

  Future<void> unPair(String deviceId) async {
    final String __pigeon_channelName = 'dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.unPair$__pigeon_messageChannelSuffix';
    final BasicMessageChannel<Object?> __pigeon_channel = BasicMessageChannel<Object?>(
      __pigeon_channelName,
      pigeonChannelCodec,
      binaryMessenger: __pigeon_binaryMessenger,
    );
    final List<Object?>? __pigeon_replyList =
        await __pigeon_channel.send(<Object?>[deviceId]) as List<Object?>?;
    if (__pigeon_replyList == null) {
      throw _createConnectionError(__pigeon_channelName);
    } else if (__pigeon_replyList.length > 1) {
      throw PlatformException(
        code: __pigeon_replyList[0]! as String,
        message: __pigeon_replyList[1] as String?,
        details: __pigeon_replyList[2],
      );
    } else {
      return;
    }
  }

  Future<List<UniversalBleScanResult?>> getConnectedDevices(List<String?> withServices) async {
    final String __pigeon_channelName = 'dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.getConnectedDevices$__pigeon_messageChannelSuffix';
    final BasicMessageChannel<Object?> __pigeon_channel = BasicMessageChannel<Object?>(
      __pigeon_channelName,
      pigeonChannelCodec,
      binaryMessenger: __pigeon_binaryMessenger,
    );
    final List<Object?>? __pigeon_replyList =
        await __pigeon_channel.send(<Object?>[withServices]) as List<Object?>?;
    if (__pigeon_replyList == null) {
      throw _createConnectionError(__pigeon_channelName);
    } else if (__pigeon_replyList.length > 1) {
      throw PlatformException(
        code: __pigeon_replyList[0]! as String,
        message: __pigeon_replyList[1] as String?,
        details: __pigeon_replyList[2],
      );
    } else if (__pigeon_replyList[0] == null) {
      throw PlatformException(
        code: 'null-error',
        message: 'Host platform returned null value for non-null return value.',
      );
    } else {
      return (__pigeon_replyList[0] as List<Object?>?)!.cast<UniversalBleScanResult?>();
    }
  }

  Future<bool> isConnected(String deviceId) async {
    final String __pigeon_channelName = 'dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.isConnected$__pigeon_messageChannelSuffix';
    final BasicMessageChannel<Object?> __pigeon_channel = BasicMessageChannel<Object?>(
      __pigeon_channelName,
      pigeonChannelCodec,
      binaryMessenger: __pigeon_binaryMessenger,
    );
    final List<Object?>? __pigeon_replyList =
        await __pigeon_channel.send(<Object?>[deviceId]) as List<Object?>?;
    if (__pigeon_replyList == null) {
      throw _createConnectionError(__pigeon_channelName);
    } else if (__pigeon_replyList.length > 1) {
      throw PlatformException(
        code: __pigeon_replyList[0]! as String,
        message: __pigeon_replyList[1] as String?,
        details: __pigeon_replyList[2],
      );
    } else if (__pigeon_replyList[0] == null) {
      throw PlatformException(
        code: 'null-error',
        message: 'Host platform returned null value for non-null return value.',
      );
    } else {
      return (__pigeon_replyList[0] as bool?)!;
    }
  }
}

class _UniversalBleCallbackChannelCodec extends StandardMessageCodec {
  const _UniversalBleCallbackChannelCodec();
  @override
  void writeValue(WriteBuffer buffer, Object? value) {
    if (value is UniversalBleScanResult) {
      buffer.putUint8(128);
      writeValue(buffer, value.encode());
    } else {
      super.writeValue(buffer, value);
    }
  }

  @override
  Object? readValueOfType(int type, ReadBuffer buffer) {
    switch (type) {
      case 128: 
        return UniversalBleScanResult.decode(readValue(buffer)!);
      default:
        return super.readValueOfType(type, buffer);
    }
  }
}

/// Native -> Flutter
abstract class UniversalBleCallbackChannel {
  static const MessageCodec<Object?> pigeonChannelCodec = _UniversalBleCallbackChannelCodec();

  void onAvailabilityChanged(int state);

  void onPairStateChange(String deviceId, bool isPaired, String? error);

  void onScanResult(UniversalBleScanResult result);

  void onValueChanged(String deviceId, String characteristicId, Uint8List value);

  void onConnectionChanged(String deviceId, int state);

  static void setUp(UniversalBleCallbackChannel? api, {BinaryMessenger? binaryMessenger, String messageChannelSuffix = '',}) {
    messageChannelSuffix = messageChannelSuffix.isNotEmpty ? '.$messageChannelSuffix' : '';
    {
      final BasicMessageChannel<Object?> __pigeon_channel = BasicMessageChannel<Object?>(
          'dev.flutter.pigeon.universal_ble.UniversalBleCallbackChannel.onAvailabilityChanged$messageChannelSuffix', pigeonChannelCodec,
          binaryMessenger: binaryMessenger);
      if (api == null) {
        __pigeon_channel.setMessageHandler(null);
      } else {
        __pigeon_channel.setMessageHandler((Object? message) async {
          assert(message != null,
          'Argument for dev.flutter.pigeon.universal_ble.UniversalBleCallbackChannel.onAvailabilityChanged was null.');
          final List<Object?> args = (message as List<Object?>?)!;
          final int? arg_state = (args[0] as int?);
          assert(arg_state != null,
              'Argument for dev.flutter.pigeon.universal_ble.UniversalBleCallbackChannel.onAvailabilityChanged was null, expected non-null int.');
          try {
            api.onAvailabilityChanged(arg_state!);
            return wrapResponse(empty: true);
          } on PlatformException catch (e) {
            return wrapResponse(error: e);
          }          catch (e) {
            return wrapResponse(error: PlatformException(code: 'error', message: e.toString()));
          }
        });
      }
    }
    {
      final BasicMessageChannel<Object?> __pigeon_channel = BasicMessageChannel<Object?>(
          'dev.flutter.pigeon.universal_ble.UniversalBleCallbackChannel.onPairStateChange$messageChannelSuffix', pigeonChannelCodec,
          binaryMessenger: binaryMessenger);
      if (api == null) {
        __pigeon_channel.setMessageHandler(null);
      } else {
        __pigeon_channel.setMessageHandler((Object? message) async {
          assert(message != null,
          'Argument for dev.flutter.pigeon.universal_ble.UniversalBleCallbackChannel.onPairStateChange was null.');
          final List<Object?> args = (message as List<Object?>?)!;
          final String? arg_deviceId = (args[0] as String?);
          assert(arg_deviceId != null,
              'Argument for dev.flutter.pigeon.universal_ble.UniversalBleCallbackChannel.onPairStateChange was null, expected non-null String.');
          final bool? arg_isPaired = (args[1] as bool?);
          assert(arg_isPaired != null,
              'Argument for dev.flutter.pigeon.universal_ble.UniversalBleCallbackChannel.onPairStateChange was null, expected non-null bool.');
          final String? arg_error = (args[2] as String?);
          try {
            api.onPairStateChange(arg_deviceId!, arg_isPaired!, arg_error);
            return wrapResponse(empty: true);
          } on PlatformException catch (e) {
            return wrapResponse(error: e);
          }          catch (e) {
            return wrapResponse(error: PlatformException(code: 'error', message: e.toString()));
          }
        });
      }
    }
    {
      final BasicMessageChannel<Object?> __pigeon_channel = BasicMessageChannel<Object?>(
          'dev.flutter.pigeon.universal_ble.UniversalBleCallbackChannel.onScanResult$messageChannelSuffix', pigeonChannelCodec,
          binaryMessenger: binaryMessenger);
      if (api == null) {
        __pigeon_channel.setMessageHandler(null);
      } else {
        __pigeon_channel.setMessageHandler((Object? message) async {
          assert(message != null,
          'Argument for dev.flutter.pigeon.universal_ble.UniversalBleCallbackChannel.onScanResult was null.');
          final List<Object?> args = (message as List<Object?>?)!;
          final UniversalBleScanResult? arg_result = (args[0] as UniversalBleScanResult?);
          assert(arg_result != null,
              'Argument for dev.flutter.pigeon.universal_ble.UniversalBleCallbackChannel.onScanResult was null, expected non-null UniversalBleScanResult.');
          try {
            api.onScanResult(arg_result!);
            return wrapResponse(empty: true);
          } on PlatformException catch (e) {
            return wrapResponse(error: e);
          }          catch (e) {
            return wrapResponse(error: PlatformException(code: 'error', message: e.toString()));
          }
        });
      }
    }
    {
      final BasicMessageChannel<Object?> __pigeon_channel = BasicMessageChannel<Object?>(
          'dev.flutter.pigeon.universal_ble.UniversalBleCallbackChannel.onValueChanged$messageChannelSuffix', pigeonChannelCodec,
          binaryMessenger: binaryMessenger);
      if (api == null) {
        __pigeon_channel.setMessageHandler(null);
      } else {
        __pigeon_channel.setMessageHandler((Object? message) async {
          assert(message != null,
          'Argument for dev.flutter.pigeon.universal_ble.UniversalBleCallbackChannel.onValueChanged was null.');
          final List<Object?> args = (message as List<Object?>?)!;
          final String? arg_deviceId = (args[0] as String?);
          assert(arg_deviceId != null,
              'Argument for dev.flutter.pigeon.universal_ble.UniversalBleCallbackChannel.onValueChanged was null, expected non-null String.');
          final String? arg_characteristicId = (args[1] as String?);
          assert(arg_characteristicId != null,
              'Argument for dev.flutter.pigeon.universal_ble.UniversalBleCallbackChannel.onValueChanged was null, expected non-null String.');
          final Uint8List? arg_value = (args[2] as Uint8List?);
          assert(arg_value != null,
              'Argument for dev.flutter.pigeon.universal_ble.UniversalBleCallbackChannel.onValueChanged was null, expected non-null Uint8List.');
          try {
            api.onValueChanged(arg_deviceId!, arg_characteristicId!, arg_value!);
            return wrapResponse(empty: true);
          } on PlatformException catch (e) {
            return wrapResponse(error: e);
          }          catch (e) {
            return wrapResponse(error: PlatformException(code: 'error', message: e.toString()));
          }
        });
      }
    }
    {
      final BasicMessageChannel<Object?> __pigeon_channel = BasicMessageChannel<Object?>(
          'dev.flutter.pigeon.universal_ble.UniversalBleCallbackChannel.onConnectionChanged$messageChannelSuffix', pigeonChannelCodec,
          binaryMessenger: binaryMessenger);
      if (api == null) {
        __pigeon_channel.setMessageHandler(null);
      } else {
        __pigeon_channel.setMessageHandler((Object? message) async {
          assert(message != null,
          'Argument for dev.flutter.pigeon.universal_ble.UniversalBleCallbackChannel.onConnectionChanged was null.');
          final List<Object?> args = (message as List<Object?>?)!;
          final String? arg_deviceId = (args[0] as String?);
          assert(arg_deviceId != null,
              'Argument for dev.flutter.pigeon.universal_ble.UniversalBleCallbackChannel.onConnectionChanged was null, expected non-null String.');
          final int? arg_state = (args[1] as int?);
          assert(arg_state != null,
              'Argument for dev.flutter.pigeon.universal_ble.UniversalBleCallbackChannel.onConnectionChanged was null, expected non-null int.');
          try {
            api.onConnectionChanged(arg_deviceId!, arg_state!);
            return wrapResponse(empty: true);
          } on PlatformException catch (e) {
            return wrapResponse(error: e);
          }          catch (e) {
            return wrapResponse(error: PlatformException(code: 'error', message: e.toString()));
          }
        });
      }
    }
  }
}
