import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_web_bluetooth/flutter_web_bluetooth.dart';
import 'package:universal_ble/universal_ble.dart';

/// Extension methods for [BleCharacteristic] to simplify common operations.
extension BleCharacteristicExtension on BleCharacteristic {
  /// A stream of [Uint8List] that emits values received from the characteristic.
  Stream<Uint8List> get onValueReceived =>
      UniversalBle.characteristicValueStream(_metaData.deviceId, uuid);

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

  /// Get descriptor by uuid
  BleDescriptor descriptor(String descriptorUuid) => descriptors.firstWhere(
    (e) => BleUuidParser.compareStrings(e.uuid, descriptorUuid),
    orElse: () => throw NotFoundError.forDescriptor(descriptorUuid, uuid),
  );

  /// Unsubscribes notifications/indications from this characteristic.
  Future<void> unsubscribe({Duration? timeout, String? queueId}) =>
      UniversalBle.unsubscribe(
        _metaData.deviceId,
        _metaData.serviceId,
        uuid,
        timeout: timeout,
        queueId: queueId,
      );

  /// Reads the current value of the characteristic.
  Future<Uint8List> read({Duration? timeout, String? queueId}) =>
      UniversalBle.read(
        _metaData.deviceId,
        _metaData.serviceId,
        uuid,
        timeout: timeout,
        queueId: queueId,
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
    String? queueId,
  }) async {
    await UniversalBle.write(
      _metaData.deviceId,
      _metaData.serviceId,
      uuid,
      Uint8List.fromList(value),
      withoutResponse: !withResponse,
      timeout: timeout,
      queueId: queueId,
    );
  }

  /// Reads the value of a descriptor of this characteristic.
  ///
  /// [descriptorUuid] is the UUID of the descriptor to read.
  /// [timeout] is the timeout for the read operation.
  /// [queueId] is the ID of the queue to use for the read operation.
  Future<Uint8List> readDescriptor(
    String descriptorUuid, {
    Duration? timeout,
    String? queueId,
  }) => UniversalBle.readDescriptor(
    _metaData.deviceId,
    _metaData.serviceId,
    uuid,
    descriptorUuid,
    timeout: timeout,
    queueId: queueId,
  );

  /// Writes a value to a descriptor of this characteristic.
  ///
  /// [descriptorUuid] is the UUID of the descriptor to write.
  /// [value] is the value to write.
  /// [timeout] is the timeout for the write operation.
  /// [queueId] is the ID of the queue to use for the write operation.
  Future<void> writeDescriptor(
    String descriptorUuid,
    Uint8List value, {
    Duration? timeout,
    String? queueId,
  }) => UniversalBle.writeDescriptor(
    _metaData.deviceId,
    _metaData.serviceId,
    uuid,
    descriptorUuid,
    value,
    timeout: timeout,
    queueId: queueId,
  );

  BleCharOperationMetadata get _metaData {
    BleCharOperationMetadata? metaData = this.metaData;
    if (metaData == null) throw "Characteristic metaData is not preset";
    return metaData;
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

  CharacteristicSubscription(this._characteristic, this._property)
    : isSupported = _characteristic.properties.contains(_property);

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
  Future<void> subscribe({Duration? timeout, String? queueId}) {
    if (!isSupported) throw Exception('Operation not supported');

    if (_property == CharacteristicProperty.indicate) {
      return UniversalBle.subscribeIndications(
        _characteristic._metaData.deviceId,
        _characteristic._metaData.serviceId,
        _characteristic.uuid,
        timeout: timeout,
        queueId: queueId,
      );
    }

    return UniversalBle.subscribeNotifications(
      _characteristic._metaData.deviceId,
      _characteristic._metaData.serviceId,
      _characteristic.uuid,
      timeout: timeout,
      queueId: queueId,
    );
  }

  /// Unsubscribes from this characteristic.
  Future<void> unsubscribe({Duration? timeout, String? queueId}) {
    if (!isSupported) throw Exception('Operation not supported');
    return UniversalBle.unsubscribe(
      _characteristic._metaData.deviceId,
      _characteristic._metaData.serviceId,
      _characteristic.uuid,
      timeout: timeout,
      queueId: queueId,
    );
  }

  @override
  String toString() =>
      "CharacteristicSubscription(property: ${_property.name}, isSupported: $isSupported, characteristic: ${_characteristic.uuid})";
}
