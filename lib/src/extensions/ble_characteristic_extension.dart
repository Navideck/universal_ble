import 'dart:async';
import 'dart:typed_data';
import 'package:universal_ble/universal_ble.dart';

/// Extension methods for [BleCharacteristic] to simplify common operations.
extension BleCharacteristicExtension on BleCharacteristic {
  /// A stream of [Uint8List] that emits values received from the characteristic.
  Stream<Uint8List> get onValueReceived =>
      UniversalBle.characteristicValueStream(_deviceId, uuid);

  /// Subscribes to notifications for this characteristic.
  ///
  /// Throws an exception if the characteristic does not support notifications.
  CharacteristicSubscription get notifications =>
      CharacteristicSubscription(this, CharacteristicProperty.notify);

  /// Subscribes to indications for this characteristic.
  ///
  /// Throws an exception if the characteristic does not support indications.
  CharacteristicSubscription get indications =>
      CharacteristicSubscription(this, CharacteristicProperty.indicate);

  /// Unsubscribes notifications/indications from this characteristic.
  Future<void> unsubscribe({
    Duration? timeout,
  }) =>
      UniversalBle.unsubscribe(
        _deviceId,
        _serviceId,
        uuid,
        timeout: timeout,
      );

  /// Reads the current value of the characteristic.
  Future<Uint8List> read({
    Duration? timeout,
  }) =>
      UniversalBle.read(
        _deviceId,
        _serviceId,
        uuid,
        timeout: timeout,
      );

  /// Writes a value to the characteristic.
  ///
  /// [value] is the list of bytes to write.
  /// [withResponse] indicates whether the write should be performed with a response from the device.
  /// Default is true, meaning the device will acknowledge the write operation.
  /// If set to false, the write operation will be performed without waiting for a response.
  Future<void> write(
    List<int> value, {
    bool withResponse = true,
    Duration? timeout,
  }) async {
    await UniversalBle.write(
      _deviceId,
      _serviceId,
      uuid,
      Uint8List.fromList(value),
      withoutResponse: !withResponse,
      timeout: timeout,
    );
  }

  String get _deviceId {
    String? deviceId = metaData?.deviceId;
    if (deviceId == null) {
      throw "DeviceId is not preset in characteristic metaData";
    }
    return deviceId;
  }

  String get _serviceId {
    String? serviceId = metaData?.serviceId;
    if (serviceId == null) {
      throw "ServiceId is not preset in characteristic metaData";
    }
    return serviceId;
  }
}

/// Manages subscription to a characteristic's notifications or indications.
///
/// Instances are typically obtained via the `notifications` or `indications`
/// getters on `BleCharacteristic`.
///
/// call [subscribe] to instruct the device to start sending data.
/// call [unsubscribe] To stop receiving data and instruct the device to cease sending,
/// call [listen] to register a callback to receive this data..
/// use [isSupported] to check if this operation is supported by the characteristic
///
class CharacteristicSubscription {
  final BleCharacteristic _characteristic;
  final CharacteristicProperty _property;

  /// Indicates whether the characteristic supports the requested subscription type
  /// (notifications or indications).
  final bool isSupported;

  CharacteristicSubscription(
    this._characteristic,
    this._property,
  ) : isSupported = _characteristic.properties.contains(_property);

  /// Registers a listener for incoming data from the characteristic.
  StreamSubscription listen(
    void Function(Uint8List event) onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _characteristic.onValueReceived.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  /// Subscribes to this characteristic.
  Future<void> subscribe({
    Duration? timeout,
  }) {
    if (!isSupported) throw Exception('Operation not supported');

    if (_property == CharacteristicProperty.indicate) {
      return UniversalBle.subscribeIndications(
        _characteristic._deviceId,
        _characteristic._serviceId,
        _characteristic.uuid,
        timeout: timeout,
      );
    }

    return UniversalBle.subscribeNotifications(
      _characteristic._deviceId,
      _characteristic._serviceId,
      _characteristic.uuid,
      timeout: timeout,
    );
  }

  /// Unsubscribes from this characteristic.
  Future<void> unsubscribe({
    Duration? timeout,
  }) {
    if (!isSupported) throw Exception('Operation not supported');
    return UniversalBle.unsubscribe(
      _characteristic._deviceId,
      _characteristic._serviceId,
      _characteristic.uuid,
      timeout: timeout,
    );
  }

  @override
  String toString() =>
      "CharacteristicSubscription(property: ${_property.name}, isSupported: $isSupported, characteristic: ${_characteristic.uuid})";
}
