import 'package:pigeon/pigeon.dart';

// dart run pigeon --input pigeon/universal_ble.dart
@ConfigurePigeon(
  PigeonOptions(
    dartPackageName: 'universal_ble',
    dartOut: 'lib/src/universal_ble.g.dart',
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

/// Shared models & enums
/// ------------------------------------------------------------
class UniversalBleScanResult {
  final String deviceId;
  final String? name;
  final bool? isPaired;
  final int? rssi;
  final List<UniversalManufacturerData>? manufacturerDataList;
  final Map<String, Uint8List>? serviceData;
  final List<String>? services;
  final int? timestamp;
  final int? timestampMicroseconds;
  final bool? connectable;

  UniversalBleScanResult({
    required this.name,
    required this.deviceId,
    required this.isPaired,
    required this.rssi,
    required this.manufacturerDataList,
    required this.serviceData,
    required this.services,
    required this.timestamp,
    required this.timestampMicroseconds,
    required this.connectable,
  });
}

/// The device a platform's native picker returned.
class UniversalDevicePickerResult {
  /// Identifier to pass to `connect`.
  String deviceId;

  /// Name the platform reported for the selected device, if any.
  String? name;

  UniversalDevicePickerResult({required this.deviceId, this.name});
}

enum BleLogLevel { none, error, warning, info, debug, verbose }

enum AvailabilityState {
  unknown,
  resetting,
  unsupported,
  unauthorized,
  poweredOff,
  poweredOn,
}

enum BleConnectionState { connected, disconnected, connecting, disconnecting }

enum BleInputProperty { disabled, notification, indication }

enum BleOutputProperty { withResponse, withoutResponse }

/// Connection priority hint passed to [requestConnectionPriority].
///
/// Maps to Android `BluetoothGatt.CONNECTION_PRIORITY_*` constants.
enum BleConnectionPriority {
  /// Default OS-managed interval (~30-50 ms). Android constant: 0.
  balanced,

  /// Low-latency interval (~7.5-15 ms), higher power draw. Android constant: 1.
  highPerformance,

  /// Power-optimized interval (~100-125 ms). Android constant: 2.
  lowPower,
}

enum AndroidScanMode { balanced, lowLatency, lowPower, opportunistic }

/// Mirrors `android.bluetooth.le.ScanSettings#setCallbackType`. Pass any
/// combination via `AndroidOptions.callbackType` (the plugin OR-folds the list
/// before calling `setCallbackType`).
///
/// API-level notes:
/// * [allMatches] — API 21+
/// * [firstMatch], [matchLost] — API 23+ (Marshmallow). Silently dropped on
///   older devices.
/// * [allMatchesAutoBatch] — API 34+ (Upside Down Cake). Silently dropped on
///   older devices.
///
/// See https://developer.android.com/reference/android/bluetooth/le/ScanSettings
enum AndroidScanCallbackType {
  allMatches,
  firstMatch,
  matchLost,
  allMatchesAutoBatch,
}

/// Mirrors `android.bluetooth.le.ScanSettings#setMatchMode`.
enum AndroidScanMatchMode { aggressive, sticky }

/// Mirrors `android.bluetooth.le.ScanSettings#setNumOfMatches`.
enum AndroidScanNumOfMatches { one, few, max }

enum CharacteristicProperty {
  broadcast,
  read,
  writeWithoutResponse,
  write,
  notify,
  indicate,
  authenticatedSignedWrites,
  extendedProperties,
}

enum PeripheralReadinessState {
  unknown,
  ready,
  bluetoothOff,
  unauthorized,
  unsupported,
}

enum PeripheralAttributePermission {
  readable,
  writeable,
  readEncryptionRequired,
  writeEncryptionRequired,
}

enum PeripheralAdvertisingState { idle, starting, advertising, stopping, error }

/// Central/GATT models
class UniversalBleService {
  String uuid;
  List<UniversalBleCharacteristic>? characteristics;
  UniversalBleService(this.uuid, this.characteristics);
}

class UniversalBleCharacteristic {
  String uuid;
  List<CharacteristicProperty> properties;
  List<UniversalBleDescriptor> descriptors;
  UniversalBleCharacteristic(this.uuid, this.properties, this.descriptors);
}

class UniversalBleDescriptor {
  String uuid;
  UniversalBleDescriptor(this.uuid);
}

/// Link-layer connection parameters reported by Android [onConnectionUpdated].
///
/// [interval] and [supervisionTimeout] use BLE connection parameter units
/// (multiply interval by 1.25 for ms; supervisionTimeout by 10 for ms).
class BleConnectionParametersChange {
  final String deviceId;
  final int interval;
  final int latency;
  final int supervisionTimeout;
  final int status;

  BleConnectionParametersChange({
    required this.deviceId,
    required this.interval,
    required this.latency,
    required this.supervisionTimeout,
    required this.status,
  });
}

/// Scan models
/// Android options to scan devices
/// [requestLocationPermission] is used to request location permission on Android 12+ (API 31+).
/// [scanMode] is used to set the scan mode for Bluetooth LE scan.
/// Set [reportDelayMillis] timestamp for Bluetooth LE scan. If set to 0, you will be notified of scan results immediately.
/// If > 0, scan results are queued up and delivered after the requested delay or 5000 milliseconds (whichever is higher).
/// Note scan results may be delivered sooner if the internal buffers fill up.
/// [callbackType], [matchMode], and [numOfMatches] map directly to the equivalent
/// `android.bluetooth.le.ScanSettings` setters. When `null`, the plugin leaves them
/// at the platform default — set them only if you need to override platform-side
/// advert de-duplication (e.g. on Pixel hardware where the default settings
/// throttle advertisements compared with nRF Connect).
///
/// [callbackType] is a list because Android's `setCallbackType` accepts any
/// bitwise combination of [AndroidScanCallbackType] values (for example
/// `[firstMatch, matchLost]` to be notified once on entry and again on exit).
/// The plugin OR-folds the list before calling the native API. Values that
/// require a newer API than the device supports are silently dropped (and
/// logged); see the [AndroidScanCallbackType] doc for per-value API levels.
///
/// [legacy] controls whether only legacy advertisements (BLE 4.2 and below) are
/// returned (API 26+). When `null` or `false`, the plugin scans for BLE 5
/// extended advertisements only (the library default, unchanged from prior
/// releases). Set to `true` for legacy BLE 4.x advertisements (e.g. ESP32); on
/// API 26+ the plugin sets `setLegacy(true)` and does not set `PHY`.
///
/// See https://developer.android.com/reference/android/bluetooth/le/ScanSettings
class AndroidOptions {
  bool? requestLocationPermission;
  AndroidScanMode? scanMode;
  int? reportDelayMillis;
  List<AndroidScanCallbackType>? callbackType;
  AndroidScanMatchMode? matchMode;
  AndroidScanNumOfMatches? numOfMatches;
  bool? legacy;
  AndroidOptions({
    this.requestLocationPermission,
    this.scanMode,
    this.reportDelayMillis,
    this.callbackType,
    this.matchMode,
    this.numOfMatches,
    this.legacy,
  });
}

class UniversalScanConfig {
  AndroidOptions? android;

  /// When `true`, each device is reported only once per scan session: repeated
  /// scan results for a device are suppressed. Platforms with a native lever
  /// apply it; the Dart layer de-duplicates as a cross-platform guarantee.
  /// Wired from `UniversalBle.startScan`'s `skipDuplicates`.
  bool? skipDuplicates;

  UniversalScanConfig(this.android, this.skipDuplicates);
}

class UniversalScanFilter {
  final List<String> withServices;
  final List<String> withNamePrefix;
  final List<ManufacturerDataFilter> withManufacturerData;

  /// Service data UUIDs to match. Appended last on purpose: pigeon encodes
  /// fields positionally, so inserting this anywhere else would shift the
  /// indices of the fields above and break against a stale native binary.
  final List<String> withServiceData;

  UniversalScanFilter(
    this.withServices,
    this.withNamePrefix,
    this.withManufacturerData,
    this.withServiceData,
  );
}

class ManufacturerDataFilter {
  /// Must be of integer type, in hex or decimal form (e.g. 0x004c or 76).
  int companyIdentifier;

  /// Matches as prefix the device's advertised data.
  Uint8List? payloadPrefix;

  /// For each bit in the mask, set it to 1 if it needs to match
  /// the corresponding one in manufacturer data, or otherwise set it to 0.
  /// The 'mask' must have the same length as the payload.
  Uint8List? payloadMask;

  /// Filter manufacturer data by company identifier, payload prefix, or payload mask.
  ManufacturerDataFilter({
    required this.companyIdentifier,
    this.payloadPrefix,
    this.payloadMask,
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

/// Apple options for `connect`.
///
/// Each flag maps to a `CBConnectPeripheralOptionNotifyOn*Key` connect option.
/// When `true`, the system displays an alert for the corresponding event if
/// the app is suspended while it occurs, relaunching the app into the
/// background to handle it. This keeps a backgrounded central responsive —
/// e.g. while reconnecting to a previously paired peripheral — without the
/// user having to foreground the app. Requires the `bluetooth-central`
/// background mode on iOS.
///
/// All flags default to `false` (no alerts, background events are not
/// delivered while suspended).
class AppleConnectionOptions {
  /// `CBConnectPeripheralOptionNotifyOnConnectionKey`:
  /// notify when a connection to the device succeeds while the app is suspended.
  bool? notifyOnConnection;

  /// `CBConnectPeripheralOptionNotifyOnDisconnectionKey`:
  /// notify when the peripheral disconnects while the app is suspended.
  bool? notifyOnDisconnection;

  /// `CBConnectPeripheralOptionNotifyOnNotificationKey`:
  /// notify when a characteristic notification arrives while the app is
  /// suspended. Fires per notification.
  bool? notifyOnNotification;

  AppleConnectionOptions({
    this.notifyOnConnection,
    this.notifyOnDisconnection,
    this.notifyOnNotification,
  });
}

/// One accessory the AccessorySetupKit picker can offer. Each item is shown as
/// a separate entry in the system picker.
class AppleAccessoryPickerItem {
  /// Name shown in the system accessory picker.
  String displayName;

  /// Name of the product image in the iOS app's asset catalog.
  String imageAsset;

  /// Advertised Bluetooth service UUID used to discover the accessory.
  String serviceUuid;

  /// Optional substring of the accessory's advertised Bluetooth name.
  String? nameSubstring;

  /// Limit discovery to accessories in the immediate vicinity.
  bool? requiresImmediateRange;

  /// Allow AccessorySetupKit to perform Bluetooth LE pairing when needed.
  bool? supportsBluetoothPairing;

  AppleAccessoryPickerItem({
    required this.displayName,
    required this.imageAsset,
    required this.serviceUuid,
    this.nameSubstring,
    this.requiresImmediateRange,
    this.supportsBluetoothPairing,
  });
}

/// iOS 18+ options for discovering and authorizing Bluetooth accessories with
/// AccessorySetupKit before connecting to them.
class AppleAccessorySetupOptions {
  /// Accessories the picker offers. At least one item is required.
  List<AppleAccessoryPickerItem> items;

  AppleAccessorySetupOptions({required this.items});
}

class AndroidConnectionOptions {
  /// Close the GATT client when the FlutterEngine is detached (for
  /// example, when the app is "killed"). The plugin otherwise leaves the
  /// GATT open, keeping the peripheral occupied until its supervision
  /// timeout; with `autoConnect` it also stays open for reconnection.
  ///
  /// When `null`, the value set by a previous `connect()` on this engine
  /// is kept.
  bool? closeGattOnDetach;

  AndroidConnectionOptions({this.closeGattOnDetach});
}

class ConnectionPlatformConfig {
  AppleConnectionOptions? apple;
  AndroidConnectionOptions? android;
  ConnectionPlatformConfig({this.apple, this.android});
}

class AndroidDiscoverServicesOptions {
  /// Clear the OS-level GATT cache of the connection (`BluetoothGatt.refresh()`)
  /// before discovering, so a peripheral whose GATT layout changed while it
  /// was disconnected is read again instead of served from the cache.
  ///
  /// `refresh()` is a hidden API invoked by reflection; discovery fails when
  /// it is unavailable or returns `false`.
  bool? clearGattCache;

  AndroidDiscoverServicesOptions({this.clearGattCache});
}

class AppleDiscoverServicesOptions {
  /// How long, in milliseconds, the native discovery may take before it fails.
  /// iOS and macOS bound discovery themselves, so that a discovery that never
  /// completes cannot hold back later calls; 10 seconds when not set. Other
  /// platforms are bounded by the `timeout` of `discoverServices` alone.
  ///
  /// `discoverServices` fills this in from its `timeout` (by default the global
  /// `UniversalBle.timeout`) when only that is given, and takes this as its
  /// `timeout` when only this is. A value that is not positive counts as unset.
  int? timeoutMillis;

  AppleDiscoverServicesOptions({this.timeoutMillis});
}

/// Platform-specific options for `discoverServices`. Ignored on platforms
/// that have no equivalent.
class DiscoverServicesPlatformConfig {
  AndroidDiscoverServicesOptions? android;
  AppleDiscoverServicesOptions? apple;
  DiscoverServicesPlatformConfig({this.android, this.apple});
}

class PeripheralAndroidOptions {
  bool? addManufacturerDataInScanResponse;

  /// Put advertised service UUIDs in the scan response instead of the primary
  /// advertisement. The Android primary advertisement and scan response are
  /// both capped at 31 bytes. A 128-bit service UUID (18 bytes) plus a
  /// device name can overflow the primary packet.
  /// Note: If this is enabled with `addManufacturerDataInScanResponse`, ensure
  /// the combined data fits within the scan response's 31-byte limit.
  bool? addServicesInScanResponse;
  PeripheralAndroidOptions({
    this.addManufacturerDataInScanResponse,
    this.addServicesInScanResponse,
  });
}

class PeripheralPlatformConfig {
  PeripheralAndroidOptions? android;
  PeripheralPlatformConfig({this.android});
}

/// Peripheral/GATT server models
class PeripheralService {
  String uuid;
  bool primary;
  List<PeripheralCharacteristic> characteristics;
  PeripheralService(this.uuid, this.primary, this.characteristics);
}

class PeripheralCharacteristic {
  String uuid;
  List<CharacteristicProperty> properties;
  List<PeripheralAttributePermission> permissions;
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
  List<PeripheralAttributePermission>? permissions;
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

/// APIs (Flutter -> Native / Native -> Flutter)
/// ------------------------------------------------------------
///
/// Async methods use [asyncCallback] instead of the Pigeon >= 28 default
/// (`async` / `suspend`): the native implementations are callback-based
/// (Swift completion handlers, Kotlin callbacks), and [asyncCallback] keeps
/// those signatures rather than forcing a rewrite to native async/await.

/// Flutter -> Native (central)
@HostApi()
abstract class UniversalBlePlatformChannel {
  @asyncCallback
  AvailabilityState getBluetoothAvailabilityState();

  bool hasPermissions(bool withAndroidFineLocation);

  @asyncCallback
  void requestPermissions(bool withAndroidFineLocation);

  @asyncCallback
  bool enableBluetooth();

  @asyncCallback
  bool disableBluetooth();

  void startScan(UniversalScanFilter? filter, UniversalScanConfig? config);

  void stopScan();

  bool isScanning();

  /// Shows the platform's native device picker (iOS 18+ AccessorySetupKit) and
  /// returns the selected device.
  @asyncCallback
  UniversalDevicePickerResult requestDevice(AppleAccessorySetupOptions options);

  void connect(
    String deviceId, {
    bool? autoConnect,
    ConnectionPlatformConfig? platformConfig,
  });

  void disconnect(String deviceId);

  @asyncCallback
  void setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  );

  @asyncCallback
  List<UniversalBleService> discoverServices(
    String deviceId,
    bool withDescriptors,
    DiscoverServicesPlatformConfig? platformConfig,
  );

  @asyncCallback
  Uint8List readValue(String deviceId, String service, String characteristic);

  @asyncCallback
  Uint8List readDescriptorValue(
    String deviceId,
    String service,
    String characteristic,
    String descriptor,
  );

  @asyncCallback
  int requestMtu(String deviceId, int expectedMtu);

  @asyncCallback
  void writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  );

  @asyncCallback
  void writeDescriptorValue(
    String deviceId,
    String service,
    String characteristic,
    String descriptor,
    Uint8List value,
  );

  @asyncCallback
  bool isPaired(String deviceId);

  @asyncCallback
  bool pair(String deviceId);

  @asyncCallback
  void unPair(String deviceId);

  @asyncCallback
  List<UniversalBleScanResult> getSystemDevices(List<String> withServices);

  BleConnectionState getConnectionState(String deviceId);

  @asyncCallback
  int readRssi(String deviceId);

  @asyncCallback
  void requestConnectionPriority(
    String deviceId,
    BleConnectionPriority priority,
  );

  void setLogLevel(BleLogLevel logLevel);
}

/// Native -> Flutter (central)
@FlutterApi()
abstract class UniversalBleCallbackChannel {
  @asyncCallback
  void onAvailabilityChanged(AvailabilityState state);

  /// [isFailure] marks a failed bond attempt — an event rather than a steady
  /// pairing state — so the Dart side can bypass its state de-duplication
  /// instead of swallowing every failure after the first (#325).
  @asyncCallback
  void onPairStateChange(String deviceId, bool isPaired, bool isFailure);

  @asyncCallback
  void onScanResult(UniversalBleScanResult result);

  @asyncCallback
  void onValueChanged(
    String deviceId,
    String characteristicId,
    Uint8List value,
    int? timestamp,
  );

  /// [errorCode] classifies a failed connection or an unexpected disconnect
  /// (`deviceDisconnected`, `connectionTimeout`, `connectionFailed`, ...),
  /// mapped on the native side from `CBError.Code` (Apple) or the GATT
  /// `status` (Android). [nativeErrorCode] is that raw platform value.
  /// Both are `null` when there is no error or the platform has no code.
  @asyncCallback
  void onConnectionChanged(
    String deviceId,
    bool connected,
    String? error,
    UniversalBleErrorCode? errorCode,
    int? nativeErrorCode,
  );

  @asyncCallback
  void onConnectionParametersUpdated(BleConnectionParametersChange update);
}

/// Flutter -> Native (peripheral)
@HostApi()
abstract class UniversalBlePeripheralChannel {
  PeripheralAdvertisingState getAdvertisingState();

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
    UniversalManufacturerData? manufacturerData,
    PeripheralPlatformConfig? platformConfig,
  );

  void updateCharacteristic(
    String characteristicId,
    Uint8List value,
    String? deviceId,
  );

  /// Returns peripheral-client device ids currently subscribed to [characteristicId]
  /// (e.g. HID report characteristic). Used to restore app state after restart.
  List<String> getSubscribedClients(String characteristicId);

  /// Returns max characteristic notify payload length for a connected client.
  int? getMaximumNotifyLength(String deviceId);
}

/// Flutter -> Native (Android only)
@HostApi()
abstract class UniversalBleAndroidChannel {
  bool hasBluetoothAdvertisePermission();

  @asyncCallback
  bool requestBluetoothAdvertisePermission();
}

/// Native -> Flutter (peripheral)
@FlutterApi()
abstract class UniversalBlePeripheralCallback {
  @asyncCallback
  PeripheralReadRequestResult? onReadRequest(
    String deviceId,
    String characteristicId,
    int offset,
    Uint8List? value,
  );

  @asyncCallback
  PeripheralWriteRequestResult? onWriteRequest(
    String deviceId,
    String characteristicId,
    int offset,
    Uint8List? value,
  );

  @asyncCallback
  PeripheralReadRequestResult? onDescriptorReadRequest(
    String deviceId,
    String characteristicId,
    String descriptorId,
    int offset,
    Uint8List? value,
  );

  @asyncCallback
  PeripheralWriteRequestResult? onDescriptorWriteRequest(
    String deviceId,
    String characteristicId,
    String descriptorId,
    int offset,
    Uint8List? value,
  );

  @asyncCallback
  void onCharacteristicSubscriptionChange(
    String deviceId,
    String characteristicId,
    bool isSubscribed,
    String? name,
  );

  @asyncCallback
  void onAdvertisingStateChange(
    PeripheralAdvertisingState state,
    String? error,
  );

  @asyncCallback
  void onServiceAdded(String serviceId, String? error);

  @asyncCallback
  void onMtuChange(String deviceId, int mtu);

  @asyncCallback
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
