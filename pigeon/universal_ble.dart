import 'package:pigeon/pigeon.dart';

// dart run pigeon --input pigeon/universal_ble.dart
@ConfigurePigeon(
  PigeonOptions(
    dartPackageName: 'universal_ble',
    dartOut: 'lib/src/universal_ble_pigeon/universal_ble.g.dart',
    dartOptions: DartOptions(),
    kotlinOut:
        'android/src/main/kotlin/com/navideck/universal_ble/UniversalBle.g.kt',
    swiftOut: 'darwin/Classes/UniversalBle.g.swift',
    kotlinOptions: KotlinOptions(package: 'com.navideck.universal_ble'),
    swiftOptions: SwiftOptions(),
    cppOptions: CppOptions(namespace: 'universal_ble'),
    cppHeaderOut: 'windows/src/generated/universal_ble.g.h',
    cppSourceOut: 'windows/src/generated/universal_ble.g.cpp',
    debugGenerators: true,
  ),
)

/// Flutter -> Native
@HostApi()
abstract class UniversalBlePlatformChannel {
  @async
  int getBluetoothAvailabilityState();

  @async
  bool enableBluetooth();

  void startScan();

  void stopScan();

  void connect(String deviceId);

  void disconnect(String deviceId);

  void setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    int bleInputProperty,
  );

  @async
  List<UniversalBleService> discoverServices(String deviceId);

  @async
  Uint8List readValue(
    String deviceId,
    String service,
    String characteristic,
  );

  @async
  int requestMtu(String deviceId, int expectedMtu);

  @async
  void writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    int bleOutputProperty,
  );

  @async
  bool isPaired(String deviceId);

  void pair(String deviceId);

  void unPair(String deviceId);

  @async
  List<UniversalBleScanResult> getConnectedDevices(
    List<String> withServices,
  );
}

/// Native -> Flutter
@FlutterApi()
abstract class UniversalBleCallbackChannel {
  void onAvailabilityChanged(int state);

  void onPairStateChange(String deviceId, bool isPaired, String? error);

  void onScanResult(UniversalBleScanResult result);

  void onValueChanged(
    String deviceId,
    String characteristicId,
    Uint8List value,
  );

  void onConnectionChanged(
    String deviceId,
    int state,
  );
}

class UniversalBleScanResult {
  final String deviceId;
  final String? name;
  final bool? isPaired;
  final int? rssi;
  final Uint8List? manufacturerData;
  final Uint8List? manufacturerDataHead;

  UniversalBleScanResult({
    required this.name,
    required this.deviceId,
    required this.isPaired,
    required this.rssi,
    required this.manufacturerData,
    required this.manufacturerDataHead,
  });
}

class UniversalBleService {
  String uuid;
  List<UniversalBleCharacteristic?>? characteristics;
  UniversalBleService(this.uuid, this.characteristics);
}

class UniversalBleCharacteristic {
  String uuid;
  List<int?> properties;
  UniversalBleCharacteristic(this.uuid, this.properties);
}
