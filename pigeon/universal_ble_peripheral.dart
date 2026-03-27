import 'package:pigeon/pigeon.dart';

// dart run pigeon --input pigeon/universal_ble_peripheral.dart
@ConfigurePigeon(
  PigeonOptions(
    dartPackageName: 'universal_ble',
    dartOut:
        'lib/src/universal_ble_peripheral/generated/universal_ble_peripheral.g.dart',
    kotlinOut:
        'android/src/main/kotlin/com/navideck/universal_ble/UniversalBlePeripheral.g.kt',
    swiftOut: 'darwin/Classes/UniversalBlePeripheral.g.swift',
    kotlinOptions: KotlinOptions(package: 'com.navideck.universal_ble'),
    // Same CocoaPod target as UniversalBle.g.swift; omit duplicate PigeonError.
    swiftOptions: SwiftOptions(includeErrorClass: false),
    cppOptions: CppOptions(namespace: 'universal_ble'),
    cppHeaderOut: 'windows/src/generated/universal_ble_peripheral.g.h',
    cppSourceOut: 'windows/src/generated/universal_ble_peripheral.g.cpp',
  ),
)
enum PeripheralBondState { bonding, bonded, none }

class PeripheralService {
  String uuid;
  bool primary;
  List<PeripheralCharacteristic> characteristics;
  PeripheralService(this.uuid, this.primary, this.characteristics);
}

class PeripheralCharacteristic {
  String uuid;
  List<int> properties;
  List<int> permissions;
  List<PeripheralDescriptor>? descriptors;
  Uint8List? value;

  PeripheralCharacteristic(
    this.uuid,
    this.properties,
    this.permissions,
    this.descriptors,
    this.value,
  );
}

class PeripheralDescriptor {
  String uuid;
  Uint8List? value;
  List<int>? permissions;
  PeripheralDescriptor(this.uuid, this.value, this.permissions);
}

class PeripheralReadRequestResult {
  Uint8List value;
  int? offset;
  int? status;
  PeripheralReadRequestResult({required this.value, this.offset, this.status});
}

class PeripheralWriteRequestResult {
  Uint8List? value;
  int? offset;
  int? status;
  PeripheralWriteRequestResult({this.value, this.offset, this.status});
}

class PeripheralManufacturerData {
  int manufacturerId;
  Uint8List data;
  PeripheralManufacturerData(
      {required this.manufacturerId, required this.data});
}

@HostApi()
abstract class UniversalBlePeripheralChannel {
  void initialize();
  bool? isAdvertising();
  bool isSupported();
  void stopAdvertising();
  void addService(PeripheralService service);
  void removeService(String serviceId);
  void clearServices();
  List<String> getServices();
  void startAdvertising(
    List<String> services,
    String? localName,
    int? timeout,
    PeripheralManufacturerData? manufacturerData,
    bool addManufacturerDataInScanResponse,
  );
  void updateCharacteristic(
    String characteristicId,
    Uint8List value,
    String? deviceId,
  );

  /// Returns peripheral-central device ids currently subscribed to [characteristicId]
  /// (e.g. HID report characteristic). Used to restore app state after restart.
  List<String> getSubscribedCentrals(String characteristicId);
}

@FlutterApi()
abstract class UniversalBlePeripheralCallback {
  PeripheralReadRequestResult? onReadRequest(
    String deviceId,
    String characteristicId,
    int offset,
    Uint8List? value,
  );

  PeripheralWriteRequestResult? onWriteRequest(
    String deviceId,
    String characteristicId,
    int offset,
    Uint8List? value,
  );

  void onCharacteristicSubscriptionChange(
    String deviceId,
    String characteristicId,
    bool isSubscribed,
    String? name,
  );
  void onAdvertisingStatusUpdate(bool advertising, String? error);
  void onBleStateChange(bool state);
  void onServiceAdded(String serviceId, String? error);
  void onMtuChange(String deviceId, int mtu);
  void onConnectionStateChange(String deviceId, bool connected);
  void onBondStateChange(String deviceId, PeripheralBondState bondState);
}
