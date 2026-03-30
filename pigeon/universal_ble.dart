import 'package:pigeon/pigeon.dart';

// dart run pigeon --input pigeon/universal_ble.dart
@ConfigurePigeon(
  PigeonOptions(
    dartPackageName: 'universal_ble',
    dartOut: 'lib/src/universal_ble_pigeon/universal_ble.g.dart',
    dartOptions: DartOptions(),
    kotlinOut:
        'android/src/main/kotlin/com/navideck/universal_ble/UniversalBle.g.kt',
    swiftOut: 'darwin/universal_ble/Sources/universal_ble/UniversalBle.g.swift',
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

  bool hasPermissions(bool withAndroidFineLocation);

  @async
  void requestPermissions(bool withAndroidFineLocation);

  @async
  bool enableBluetooth();

  @async
  bool disableBluetooth();

  void startScan(UniversalScanFilter? filter, UniversalScanConfig? config);

  void stopScan();

  bool isScanning();

  void connect(String deviceId, {bool? autoConnect});

  void disconnect(String deviceId);

  @async
  void setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    int bleInputProperty,
  );

  @async
  List<UniversalBleService> discoverServices(
    String deviceId,
    bool withDescriptors,
  );

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

  @async
  bool pair(String deviceId);

  void unPair(String deviceId);

  @async
  List<UniversalBleScanResult> getSystemDevices(
    List<String> withServices,
  );

  int getConnectionState(String deviceId);

  @async
  int readRssi(String deviceId);

  @async
  void requestConnectionPriority(String deviceId, int priority);

  void setLogLevel(UniversalBleLogLevel logLevel);
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
    int? timestamp,
  );

  void onConnectionChanged(
    String deviceId,
    bool connected,
    String? error,
  );
}

class UniversalBleScanResult {
  final String deviceId;
  final String? name;
  final bool? isPaired;
  final int? rssi;
  final List<UniversalManufacturerData>? manufacturerDataList;
  final Map<String, Uint8List>? serviceData;
  final List<String>? services;
  final int? timestamp;

  UniversalBleScanResult({
    required this.name,
    required this.deviceId,
    required this.isPaired,
    required this.rssi,
    required this.manufacturerDataList,
    required this.serviceData,
    required this.services,
    required this.timestamp,
  });
}

enum UniversalBleLogLevel {
  none,
  error,
  warning,
  info,
  debug,
  verbose,
}

class UniversalBleService {
  String uuid;
  List<UniversalBleCharacteristic>? characteristics;
  UniversalBleService(this.uuid, this.characteristics);
}

class UniversalBleCharacteristic {
  String uuid;
  List<int> properties;
  List<UniversalBleDescriptor> descriptors;
  UniversalBleCharacteristic(this.uuid, this.properties, this.descriptors);
}

class UniversalBleDescriptor {
  String uuid;
  UniversalBleDescriptor(this.uuid);
}

/// Scan config

enum AndroidScanMode {
  balanced,
  lowLatency,
  lowPower,
  opportunistic,
}

/// Android options to scan devices
/// [requestLocationPermission] is used to request location permission on Android 12+ (API 31+).
/// [scanMode] is used to set the scan mode for for Bluetooth LE scan.
/// Set [reportDelayMillis] timestamp for Bluetooth LE scan. If set to 0, you will be notified of scan results immediately.
/// If > 0, scan results are queued up and delivered after the requested delay or 5000 milliseconds (whichever is higher).
/// Note scan results may be delivered sooner if the internal buffers fill up.
class AndroidOptions {
  bool? requestLocationPermission;
  AndroidScanMode? scanMode;
  int? reportDelayMillis;
  AndroidOptions({
    this.requestLocationPermission,
    this.scanMode,
    this.reportDelayMillis,
  });
}

class UniversalScanConfig {
  AndroidOptions? android;
  UniversalScanConfig(this.android);
}

/// Scan Filters
class UniversalScanFilter {
  final List<String> withServices;
  final List<String> withNamePrefix;
  final List<UniversalManufacturerDataFilter> withManufacturerData;

  UniversalScanFilter(
    this.withServices,
    this.withNamePrefix,
    this.withManufacturerData,
  );
}

class UniversalManufacturerDataFilter {
  int companyIdentifier;
  Uint8List? data;
  Uint8List? mask;
  UniversalManufacturerDataFilter({
    required this.companyIdentifier,
    this.data,
    this.mask,
  });
}

class UniversalManufacturerData {
  final int companyIdentifier;
  final Uint8List data;

  UniversalManufacturerData({
    required this.companyIdentifier,
    required this.data,
  });
}

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

enum PeripheralReadinessState {
  unknown,
  ready,
  bluetoothOff,
  unauthorized,
  unsupported,
}

enum PeripheralAdvertisingState {
  idle,
  starting,
  advertising,
  stopping,
  error,
}

/// Flutter -> Native (peripheral)
@HostApi()
abstract class UniversalBlePeripheralChannel {
  PeripheralAdvertisingState getAdvertisingState();
  bool isFeatureSupported();
  PeripheralReadinessState getReadinessState();
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

/// Native -> Flutter (peripheral)
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
  void onAdvertisingStateChange(PeripheralAdvertisingState state, String? error);
  void onServiceAdded(String serviceId, String? error);
  void onMtuChange(String deviceId, int mtu);
  void onConnectionStateChange(String deviceId, bool connected);
}

/// Unified error codes for all platforms
enum UniversalBleErrorCode {
  // General errors
  unknownError,
  failed,
  notSupported,
  notImplemented,
  channelError,

  // Bluetooth availability errors
  bluetoothNotAvailable,
  bluetoothNotEnabled,
  bluetoothNotAllowed,
  bluetoothUnauthorized,

  // Connection errors
  deviceDisconnected,
  connectionTimeout,
  connectionFailed,
  connectionRejected,
  connectionLimitExceeded,
  connectionAlreadyExists,
  connectionTerminated,
  connectionInProgress,

  // Device/Service/Characteristic errors
  illegalArgument,
  deviceNotFound,
  serviceNotFound,
  characteristicNotFound,
  invalidServiceUuid,
  invalidCharacteristicUuid,
  invalidOffset,
  invalidAttributeLength,
  invalidPdu,
  invalidHandle,

  // Operation errors
  readFailed,
  readNotPermitted,
  writeFailed,
  writeNotPermitted,
  writeRequestBusy,
  invalidAction,
  operationNotSupported,
  operationTimeout,
  operationCancelled,
  operationInProgress,

  // Characteristic property errors
  characteristicDoesNotSupportRead,
  characteristicDoesNotSupportWrite,
  characteristicDoesNotSupportWriteWithoutResponse,
  characteristicDoesNotSupportNotify,
  characteristicDoesNotSupportIndicate,

  // Pairing errors
  notPaired,
  notPairable,
  alreadyPaired,
  pairingFailed,
  pairingCancelled,
  pairingTimeout,
  pairingNotAllowed,
  authenticationFailure,
  insufficientAuthentication,
  insufficientAuthorization,
  insufficientEncryption,
  insufficientKeySize,
  protectionLevelNotMet,
  accessDenied,

  // Unpairing errors
  unpairingFailed,
  alreadyUnpaired,

  // Scan errors
  scanFailed,
  stoppingScanInProgress,

  // Web-specific errors
  webBluetoothGloballyDisabled,
}
