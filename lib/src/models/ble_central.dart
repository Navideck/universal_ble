import 'package:flutter/foundation.dart';
import 'package:universal_ble/src/models/ble_uuid_parser.dart';

@immutable
class BleCentral {
  /// The identifier (MAC address or UUID) of the central device.
  final String id;

  /// The advertised or discovered name of the central device, if available.
  final String? name;

  /// The set of characteristic UUIDs this central device is currently subscribed to.
  ///
  /// UUID format and casing are normalized automatically upon construction into
  /// 128-bit lowercase strings. The set is unmodifiable.
  final Set<String> subscribedCharacteristics;

  BleCentral({
    required this.id,
    this.name,
    Set<String> subscribedCharacteristics = const <String>{},
  }) : subscribedCharacteristics = subscribedCharacteristics.isEmpty
            ? const <String>{}
            : Set<String>.unmodifiable(
                subscribedCharacteristics.map(BleUuidParser.string),
              );

  /// Checks whether this central is subscribed to the specified characteristic UUID.
  ///
  /// The UUID format and casing are normalized automatically.
  bool isSubscribedTo(String characteristicId) =>
      subscribedCharacteristics.contains(BleUuidParser.string(characteristicId));

  BleCentral copyWith({
    String? id,
    String? name,
    Set<String>? subscribedCharacteristics,
  }) {
    return BleCentral(
      id: id ?? this.id,
      name: name ?? this.name,
      subscribedCharacteristics:
          subscribedCharacteristics ?? this.subscribedCharacteristics,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BleCentral &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          setEquals(subscribedCharacteristics, other.subscribedCharacteristics);

  @override
  int get hashCode =>
      Object.hash(id, name, Object.hashAllUnordered(subscribedCharacteristics));

  @override
  String toString() =>
      'BleCentral(id: $id, name: $name, subscribedCharacteristics: $subscribedCharacteristics)';
}
