import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

class BleDevice {
  String deviceId;
  String? name;
  String? rawName;
  int? rssi;
  bool? paired;
  int? timestamp;

  /// List of services advertised by the device.
  List<String> services;
  bool? isSystemDevice;
  List<ManufacturerData> manufacturerDataList;

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
  /// Throws [BleException] if:
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
    this.services = const [],
    this.isSystemDevice,
    this.manufacturerDataList = const [],
    this.timestamp,
  }) {
    rawName = name;
    this.name = name?.replaceAll(RegExp(r'[^ -~]'), '').trim();
  }

  DateTime? get timestampDateTime => timestamp != null
      ? DateTime.fromMillisecondsSinceEpoch(timestamp!)
      : null;

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
        'manufacturerDataList: $manufacturerDataList';
  }
}
