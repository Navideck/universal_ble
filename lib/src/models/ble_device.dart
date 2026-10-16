import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

class BleDevice {
  /// Unique identifier of the device.
  ///
  /// Emitted in lower-case canonical format on native platforms (e.g. MAC addresses
  /// on Android/Windows/Linux, UUIDs on iOS/macOS) and verbatim on Web (where tokens
  /// are opaque and case-sensitive).
  String deviceId;
  String? name;
  String? rawName;
  int? rssi;
  bool? paired;
  int? timestamp;
  int? timestampMicroseconds;
  /// Whether the device is connectable based on its advertising flags.
  ///
  /// Can be `null` if the platform or advertising packet does not indicate
  /// connectability (e.g. Linux and Web always report `null`).
  bool? connectable;

  /// List of services advertised by the device.
  ///
  /// Normalised to full 128-bit lower-case UUIDs on every platform (like the keys
  /// of [serviceData]), so the value is comparable across platforms and against
  /// user input of either form. Entries that are not valid UUIDs are kept
  /// verbatim rather than dropped, so unexpected advertisement data cannot lose
  /// information.
  List<String> services;
  bool? isSystemDevice;
  List<ManufacturerData> manufacturerDataList;
  Map<String, Uint8List> serviceData;

  @Deprecated("Use `manufacturerDataList` instead")
  Uint8List? get manufacturerData => manufacturerDataList.isEmpty
      ? null
      : manufacturerDataList.first.toUint8List();

  /// Returns connection state of the device.
  /// All platforms will return `Connected/Disconnected` states.
  /// `Android` and `Apple` can also return `Connecting/Disconnecting` states.
  Future<BleConnectionState> get connectionState =>
      UniversalBle.getConnectionState(deviceId);

  /// Read the RSSI value of this connected device.
  ///
  /// Returns the current RSSI value in dBm. This value indicates the signal strength
  /// between the device and the connected peripheral. Lower (more negative) values
  /// indicate weaker signal, while higher (less negative) values indicate stronger signal.
  ///
  /// **Note**: The device must be connected before reading RSSI.
  ///
  /// Throws [UniversalBleException] if:
  /// - The device is not connected
  /// - Reading RSSI fails
  Future<int> readRssi() => UniversalBle.readRssi(deviceId);

  /// On web, it returns true if the web browser supports receiving advertisements from this device.
  /// The rest of the platforms will always return true.
  bool get receivesAdvertisements =>
      UniversalBle.receivesAdvertisements(deviceId);

  BleDevice({
    required this.deviceId,
    required String? name,
    this.rssi,
    this.paired,
    List<String> services = const [],
    this.isSystemDevice,
    this.manufacturerDataList = const [],
    Map<String, Uint8List> serviceData = const {},
    this.timestamp,
    this.timestampMicroseconds,
    this.connectable,
  })  : services = _validateServices(services),
        serviceData = _validateServiceData(serviceData),
        rawName = name,
        name = name?.replaceAll(RegExp(r'[^ -~]'), '').trim();

  /// Returns a copy of this device with [deviceId] optionally replaced.
  ///
  /// The copy re-derives the sanitised [name] from [rawName] so both survive
  /// unchanged — passing [name] straight to the constructor would overwrite
  /// [rawName] with the already-sanitised name.
  BleDevice copyWith({String? deviceId}) => BleDevice(
        deviceId: deviceId ?? this.deviceId,
        name: rawName,
        rssi: rssi,
        paired: paired,
        services: services,
        isSystemDevice: isSystemDevice,
        manufacturerDataList: manufacturerDataList,
        serviceData: serviceData,
        timestamp: timestamp,
        timestampMicroseconds: timestampMicroseconds,
        connectable: connectable,
      );

  DateTime? get timestampDateTime => timestamp != null
      ? DateTime.fromMillisecondsSinceEpoch(timestamp!)
      : null;

  DateTime? get timestampMicrosecondsDateTime => timestampMicroseconds != null
      ? DateTime.fromMicrosecondsSinceEpoch(timestampMicroseconds!)
      : null;

  static Map<String, Uint8List> _validateServiceData(
    Map<String, Uint8List> data,
  ) {
    if (data.isEmpty) return const {};
    return data.map(
      (key, value) => MapEntry(
        BleUuidParser.stringOrNull(key) ?? key,
        Uint8List.fromList(value),
      ),
    );
  }

  /// Normalises advertised service UUIDs to the full 128-bit lower-case form.
  static List<String> _validateServices(List<String> services) {
    if (services.isEmpty) return const [];
    return services
        .map((uuid) => BleUuidParser.stringOrNull(uuid) ?? uuid)
        .toList();
  }

  @override
  String toString() {
    return 'BleDevice: '
        'deviceId: $deviceId, '
        'name: $name, '
        'rssi: $rssi, '
        'paired: $paired, '
        'services: $services, '
        'isSystemDevice: $isSystemDevice, '
        'timestamp: $timestamp, '
        'timestampMicroseconds: $timestampMicroseconds, '
        'connectable: $connectable, '
        'manufacturerDataList: $manufacturerDataList, '
        'serviceData: $serviceData';
  }
}
