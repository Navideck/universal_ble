# Universal BLE

[![pub package](https://img.shields.io/pub/v/universal_ble?label=universal_ble&color=blue)](https://pub.dev/packages/universal_ble)
[![License](https://img.shields.io/badge/license-BSD%203--Clause-blue.svg)](https://opensource.org/licenses/BSD-3-Clause)
[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS%20%7C%20macOS%20%7C%20Windows%20%7C%20Linux%20%7C%20Web-lightgrey)](https://github.com/Navideck/universal_ble)
[![GitHub stars](https://img.shields.io/github/stars/Navideck/universal_ble?style=social)](https://github.com/Navideck/universal_ble)
[![pub points](https://img.shields.io/pub/points/universal_ble?color=2E7D32)](https://pub.dev/packages/universal_ble/score)
[![Flutter](https://img.shields.io/badge/Flutter-%3E%3D3.3.0-blue.svg?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-%3E%3D3.1.3-blue.svg?logo=dart)](https://dart.dev)

A cross-platform (Android/iOS/macOS/Windows/Linux/Web) Bluetooth Low Energy (BLE) plugin for Flutter.

> **Free**: This package is free for commercial or personal use as long as you adhere to the [BSD 3-Clause License](LICENSE).

[Try it online](https://navideck.github.io/universal_ble/), provided your browser supports [Web Bluetooth](https://caniuse.com/web-bluetooth).

## Features

- [Scanning](#scanning)
- [Connecting](#connecting)
- [Discovering Services](#discovering-services)
- [Reading & Writing data](#reading--writing-data)
- [Pairing](#pairing)
- [Bluetooth Availability](#bluetooth-availability)
- [Requesting MTU](#requesting-mtu)
- [Reading RSSI](#reading-rssi)
- [Command Queue](#command-queue)
- [Timeout](#timeout)
- [Error Handling](#error-handling)
- [UUID Format Agnostic](#uuid-format-agnostic)
- [Permissions](#permissions)

## API Support

|                               | Android | iOS | macOS | Windows | Linux | Web |
| :---------------------------- | :-----: | :-: | :---: | :-----: | :---: | :-: |
| startScan/stopScan            |   ✔️    | ✔️  |  ✔️   |   ✔️    |  ✔️   | ✔️  |
| connect/disconnect            |   ✔️    | ✔️  |  ✔️   |   ✔️    |  ✔️   | ✔️  |
| getSystemDevices              |   ✔️    | ✔️  |  ✔️   |   ✔️    |  ✔️   | ❌  |
| discoverServices              |   ✔️    | ✔️  |  ✔️   |   ✔️    |  ✔️   | ✔️  |
| read                          |   ✔️    | ✔️  |  ✔️   |   ✔️    |  ✔️   | ✔️  |
| write                         |   ✔️    | ✔️  |  ✔️   |   ✔️    |  ✔️   | ✔️  |
| subscriptions                 |   ✔️    | ✔️  |  ✔️   |   ✔️    |  ✔️   | ✔️  |
| pair                          |   ✔️    | ✔️  |  ✔️   |   ✔️    |  ✔️   |  ⏺  |
| unpair                        |   ✔️    | ❌  |  ❌   |   ✔️    |  ✔️   | ❌  |
| isPaired                      |   ✔️    | ✔️  |  ✔️   |   ✔️    |  ✔️   | ✔️  |
| onPairingStateChange          |   ✔️    |  ⏺  |   ⏺   |   ✔️    |  ✔️   |  ⏺  |
| getBluetoothAvailabilityState |   ✔️    | ✔️  |  ✔️   |   ✔️    |  ✔️   | ❌  |
| enable/disable Bluetooth      |   ✔️    | ❌  |  ❌   |   ✔️    |  ✔️   | ❌  |
| onAvailabilityChange          |   ✔️    | ✔️  |  ✔️   |   ✔️    |  ✔️   | ✔️  |
| requestMtu                    |   ✔️    | ✔️  |  ✔️   |   ✔️    |  ✔️   | ❌  |
| readRssi                      |   ✔️    | ✔️  |  ✔️   |   ❌    |  ❌   | ❌  |
| requestPermissions            |   ✔️    | ✔️  |  ✔️   |   ✔️    |  ✔️   | ✔️  |

## Getting Started

Add universal_ble in your pubspec.yaml:

```yaml
dependencies:
  universal_ble:
```

and import it wherever you want to use it:

```dart
import 'package:universal_ble/universal_ble.dart';
```

> **Important**: Before using BLE features, make sure to check the [Permissions](#permissions) section to see what setup is needed for your target platform (Android, iOS, macOS, Windows, Linux, or Web).

### Scanning

The very first thing you need to do before being able to connect to a device is to discover it by calling `startScan();`

```dart
// Get scan updates from stream
UniversalBle.scanStream.listen((BleDevice bleDevice) {
  // e.g. Use BleDevice ID to connect
});

// Or set a handler
UniversalBle.onScanResult = (bleDevice) {}

// Perform a scan
UniversalBle.startScan();

// Or optionally add a scan filter
UniversalBle.startScan(
  scanFilter: ScanFilter(
    withServices: ["SERVICE_UUID"],
    withManufacturerData: [ManufacturerDataFilter(companyIdentifier: 0x004c)],
    withNamePrefix: ["NAME_PREFIX"],
  )
);

// Stop scanning
UniversalBle.stopScan();

// Check if scanning
UniversalBle.isScanning();
```

Before initiating a scan, ensure that Bluetooth is available:

```dart
AvailabilityState state = await UniversalBle.getBluetoothAvailabilityState();
// Start scan only if Bluetooth is powered on
if (state == AvailabilityState.poweredOn) {
  UniversalBle.startScan();
}

// Listen to bluetooth availability changes using stream
UniversalBle.availabilityStream.listen((state) {
  if (state == AvailabilityState.poweredOn) {
    UniversalBle.startScan();
  }
});

// Or set a handler
UniversalBle.onAvailabilityChange = (state) {};
```

See the [Bluetooth Availability](#bluetooth-availability) section for more.

#### System Devices

Already connected devices, connected either through previous sessions, other apps or through system settings, won't show up as scan results. You can get those using `getSystemDevices()`.

```dart
// Get already connected devices.
// You can set `withServices` to narrow down the results.
// On `Apple`, `withServices` is required to get any connected devices. If not passed, several [18XX] generic services will be set by default.
List<BleDevice> devices = await UniversalBle.getSystemDevices(withServices: []);
```

For each such device the `isSystemDevice` property will be `true`.

You still need to explicitly [connect](#connecting) to them before being able to use them.

#### Scan Filter

You can optionally set a filter when scanning. A filter can have multiple conditions (services, manufacturerData, namePrefix) and all conditions are in `OR` relation, returning results that match any of the given conditions.

##### With Services

When setting this parameter, the scan results will only include devices that advertise any of the specified services.

```dart
List<String> withServices;
```

Note: On web **you have to** specify services before you are able to use them. See the [web](#web) section for more details.

##### With ManufacturerData

Use the `withManufacturerData` parameter to filter devices by manufacturer data. When you pass a list of `ManufacturerDataFilter` objects to this parameter, the scan results will only include devices that contain any of the specified manufacturer data.

You can filter manufacturer data by company identifier, payload prefix, or payload mask.

```dart
List<ManufacturerDataFilter> withManufacturerData = [ManufacturerDataFilter(
            companyIdentifier: 0x004c,
            payloadPrefix: Uint8List.fromList([0x001D,0x001A]),
            payloadMask: Uint8List.fromList([1,0,1,1]))
          ];
```

##### With namePrefix

Use the `withNamePrefix` parameter to filter devices by names (case sensitive). When you pass a list of names, the scan results will only include devices that have this name or start with the provided parameter.

```dart
List<String> withNamePrefix;
```

##### Exclusion Filter

Use exclusion filters to exclude specific devices from scan results:

```dart
exclusionFilters: [
    ExclusionFilter(
      namePrefix: 'EXCLUDED_NAME',
      services: ['EXCLUDED_SERVICE_UUID'],
      manufacturerDataFilter: [ManufacturerDataFilter(companyIdentifier: 0x004c)],
    ),
]
```

### Connecting

#### Connect

Connects to the BLE device. This method initiates a connection to the Bluetooth device.

```dart
await bleDevice.connect();
```

#### Disconnect

Disconnects from the BLE device. This method terminates the connection to the Bluetooth device.

```dart
await bleDevice.disconnect();
```

#### Connection Stream

```dart
bleDevice.connectionStream.listen((isConnected) {
  debugPrint('Is device connected?: $isConnected');
});
```

#### IsConnected

```dart
bool isConnected = await bleDevice.isConnected;
```

#### Connection state

```dart
// Can be connected, disconnected, connecting or disconnecting
BleConnectionState connectionState = await bleDevice.connectionState;
```

### Discovering Services

After establishing a connection, services need to be discovered. This method will discover all services and their characteristics.

If you don't call this method then it will be automatically called when you try to get any service or characteristic.

#### DiscoverServices

Discovers the services offered by the device. Returns a `Future<List<BleService>>`. After discovery services are cached and each call of this method updates the cache.

```dart
List<BleService> services = await bleDevice.discoverServices();
for (var service in services) {
  debugPrint('Service UUID: ${service.uuid}');
}
```

#### GetService

Retrieves a specific service. Returns a `Future<BleService>`.

- `service`: The UUID of the service.
- `preferCached`: If `true` (default), cached services are used. If cache is empty, `discoverServices()` will be called.

```dart
BleService service = await bleDevice.getService('180a');
```

#### GetCharacteristic

Retrieves a specific characteristic from a service. Returns a `Future<BleCharacteristic>`.

- `service`: The UUID of the service.
- `characteristic`: The UUID of the characteristic.
- `preferCached`: If `true` (default), cached services are used. If cache is empty, `discoverServices()` will be called

```dart
BleCharacteristic characteristic = await bleDevice.getCharacteristic('180a','2a56');
```

Or retrieve from `BleService`

```dart
BleCharacteristic characteristic = await service.getCharacteristic('2a56');
```

## Reading & Writing data

You need to first [discover services](#discovering-services) before you are able to read and write to characteristics.

```dart
Uint8List value = await characteristic.read();
```

```dart
await characteristic.write([0x01, 0x02, 0x03]);

await characteristic.write([0x01, 0x02, 0x03], withResponse: false);
```

## Subscriptions

Get `BleCharacteristic` using `bleDevice.getCharacteristic`

### OnValueReceived

A stream of `Uint8List` that emits values received from the characteristic. Listen to this stream to receive updates whenever the characteristic's value changes.

```dart
characteristic.onValueReceived.listen((value) {
  debugPrint('Received value: ${value.toString()}');
});
```

### Notifications

Subscribe to notifications for this characteristic. Throws an exception if the characteristic does not support notifications.

```dart
await characteristic.notifications.subscribe();
```

### Indications

Subscribe to indications for this characteristic. Throws an exception if the characteristic does not support indications.

```dart
await characteristic.indications.subscribe();
```

### Unsubscribe

Unsubscribe from notifications and indications of this characteristic.

```dart
await characteristic.unsubscribe();
```

### Pairing

#### Trigger pairing

##### Pair on Android, Windows, Linux

```dart
await bleDevice.pair();
```

##### Pair on Apple and web

For Apple and Web, pairing support depends on the device. Pairing is triggered automatically by the OS when you try to read/write from/to an encrypted characteristic.

Calling `bleDevice.pair()` will only trigger pairing if the device has an _encrypted read characteristic_.

If your device only has encrypted write characteristics or you happen to know which encrypted read characteristic you want to use, you can pass it with a `pairingCommand`.

```dart
await bleDevice.pair(pairingCommand: BleCommand(service:"SERVICE", characteristic:"ENCRYPTED_CHARACTERISTIC"));
```

After pairing you can check the pairing status.

#### Pairing status

##### Pair on Android, Windows, Linux

```dart
// Check current pairing state
bool? isPaired = bleDevice.isPaired();
```

##### Pair on Apple and web

For `Apple` and `Web`, you have to pass a "pairingCommand" with an encrypted read or write characteristic. If you don't pass it then it will return `null`.

```dart
bool? isPaired = await bleDevice.isPaired(pairingCommand: BleCommand(service:"SERVICE", characteristic:"ENCRYPTED_CHARACTERISTIC"));
```

##### Discovering encrypted characteristic

To discover encrypted characteristics, make sure your device is not paired and use the example app to read/write to all discovered characteristics one by one. If one of them triggers pairing, that means it is encrypted and you can use it to construct `BleCommand(service:"SERVICE", characteristic:"ENCRYPTED_CHARACTERISTIC")`.

#### Pairing state changes

```dart
// Get pairing state updates using stream
bleDevice.pairingStateStream.listen((bool paired) {
  // Handle pairing state change
});
```

#### Unpair

```dart
bleDevice.unpair();
```

### Bluetooth Availability

```dart
// Get current Bluetooth availability state
AvailabilityState availabilityState = UniversalBle.getBluetoothAvailabilityState(); // e.g. poweredOff or poweredOn,

// Receive Bluetooth availability changes
UniversalBle.onAvailabilityChange = (state) {
  // Handle the new Bluetooth availability state
};

// Enable Bluetooth programmatically
UniversalBle.enableBluetooth();

// Disable Bluetooth programmatically
UniversalBle.disableBluetooth();
```

### Requesting MTU

```dart
int mtu = await bleDevice.requestMtu(256);
```

> ⚠️ Note: Requesting an MTU is a *best-effort* operation.
> On many platforms the final MTU is fully controlled by the OS and remote device.

#### Platform Limitations

MTU negotiation is largely platform- and stack-managed, and often cannot be
explicitly controlled by applications:

* **iOS / macOS**

  * MTU is fully OS-managed; apps cannot request or set it.
  * Historically ~185 bytes, but modern devices may negotiate larger MTUs
    (≈247–517) automatically.

* **Android**

  * **Android ≤ 13**: Apps may request MTU once per connection (up to 517).
    If never requested, the default MTU is 23.
  * **Android 14+**: The first GATT client effectively drives MTU negotiation
    to 517 (or the link’s maximum); subsequent MTU requests are ignored.

* **Windows**

  * MTU is automatically negotiated by the OS.
  * Apps cannot set it; they can only query the effective PDU size.

* **Linux (BlueZ)**

  * MTU is negotiated automatically by default.
  * The standard D-Bus GATT API does not expose MTU control.
  * MTU can be requested via BlueZ tools or lower-level APIs, but most apps
    treat it as stack-defined.

* **Web**

  * MTU is negotiated internally by the browser/OS.
  * No API exists to query or modify the MTU size.

#### Best Practices

When developing cross-platform BLE applications and devices:

* Always design for the default ATT MTU (23 bytes)
* Treat MTU requests as opportunistic, not guaranteed
* Dynamically adapt packet sizes based on the negotiated MTU
* Implement application-level fragmentation for larger payloads
* Take advantage of higher MTUs when available, without depending on them


### Reading RSSI

Read the signal strength (RSSI) of a connected device.

```dart
int rssi = await bleDevice.readRssi();
```

> ⚠️ Note: The device must be connected before reading RSSI.

#### Platform Limitations

* **Android / iOS / macOS**: Fully supported.

* **Windows / Linux / Web**: Not supported.


## Command Queue

By default, all commands are executed in a global queue (`QueueType.global`), with each command waiting for the previous one to finish. While this method is slower it is the safest to avoid command exceptions and therefore is the default.

If you want to parallelize commands between multiple devices, you can set:

```dart
// Create a separate queue for each device.
UniversalBle.queueType = QueueType.perDevice;
```

You can also completely disable the queue and batch all commands, even for the same device, by using:

```dart
// Disable queue
UniversalBle.queueType = QueueType.none;
```

Keep in mind that some platforms (e.g. Android) may not handle well devices that fail to process consecutive commands without a minimum interval. Therefore, it is not advised to set `queueType` to `none`.

You can get queue updates by setting:

```dart
// Get queue state updates
UniversalBle.onQueueUpdate = (String id, int remainingItems) {
  debugPrint("Queue: $id Remaining: $remainingItems");
};
```

To clear the queue:

```dart
  /// Use [BleCommandQueue.globalQueueId] to clear the global queue.
  /// To clear the queue of a specific device, use `deviceId` as [id].
  /// If no [id] is provided, all queues will be cleared.
  UniversalBle.clearQueue(BleCommandQueue.globalQueueId);
```

## Timeout

By default, all commands have a global timeout of 10 seconds.

```dart
// Change timeout
UniversalBle.timeout = const Duration(seconds: 10);

// Disable timeout
UniversalBle.timeout = null;
```

You can also specify the `timeout` parameter when sending a command. This will override the global timeout.

## Error Handling

Universal BLE provides a unified and type-safe error handling system across all platforms. All errors are represented using the `UniversalBleException` base class with typed error codes from the `UniversalBleErrorCode` enum.

### Exception Types

- **`UniversalBleException`**: Base exception class for all BLE errors
- **`ConnectionException`**: Thrown for connection-related errors
- **`PairingException`**: Thrown for pairing-related errors
- **`WebBluetoothGloballyDisabled`**: Thrown when Web Bluetooth is globally disabled

### Error Codes

All errors are categorized using the `UniversalBleErrorCode` enum, which includes codes for:

- Connection errors (timeout, failed, rejected, etc.)
- Pairing errors (failed, cancelled, not allowed, etc.)
- Operation errors (not supported, timeout, cancelled, etc.)
- Permission errors (not allowed, unauthorized, access denied, etc.)
- Device errors (not found, disconnected, etc.)
- Service/Characteristic errors (not found, invalid UUID, etc.)
- And many more...

### Usage

```dart
try {
  await bleDevice.connect();
} on ConnectionException catch (e) {
  // Handle connection-specific errors
  switch (e.code) {
    case UniversalBleErrorCode.connectionTimeout:
      // Handle timeout
      break;
    case UniversalBleErrorCode.connectionFailed:
      // Handle connection failure
      break;
    case UniversalBleErrorCode.deviceDisconnected:
      // Handle disconnection
      break;
    default:
      // Handle other connection errors
  }
} on UniversalBleException catch (e) {
  // Handle other BLE errors
  print('Error code: ${e.code}, Message: ${e.message}');
}
```

The error parser automatically converts platform-specific error formats (strings, numeric codes, PlatformExceptions) into the unified `UniversalBleErrorCode` enum, ensuring consistent error handling across all platforms.

## UUID Format Agnostic

Universal BLE is agnostic to the UUID format of services and characteristics regardless of the platform the app runs on. When passing a UUID, you can pass it in any format (long/short) or character case (upper/lower case) you want. Universal BLE will take care of necessary conversions, across all platforms, so that you don't need to worry about underlying platform differences.

For consistency, all characteristic and service UUIDs will be returned in **lowercase 128-bit format**, across all platforms, e.g. `0000180a-0000-1000-8000-00805f9b34fb`.

### Utility Methods

If you need to convert any UUIDs in your app you can use the following methods.

- `BleUuidParser.string()` converts a string to a 128-bit UUID formatted string:

```dart
BleUuidParser.string("180A"); // "0000180a-0000-1000-8000-00805f9b34fb"

BleUuidParser.string("0000180A-0000-1000-8000-00805F9B34FB"); // "0000180a-0000-1000-8000-00805f9b34fb"
```

- `BleUuidParser.number()` converts a number to a 128-bit UUID formatted string:

```dart
BleUuidParser.number(0x180A); // "0000180a-0000-1000-8000-00805f9b34fb"
```

- `BleUuidParser.compare()` compares two differently formatted UUIDs:

```dart
BleUuidParser.compare("180a","0000180A-0000-1000-8000-00805F9B34FB"); // true
```

## Permissions

You need to perform the following setups:

### Android

#### Manifest Permissions

Add the following permissions to your AndroidManifest.xml file:

```xml
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" android:maxSdkVersion="28" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
```

If your app uses iBeacons or BLUETOOTH_SCAN to determine location, change the last 2 permissions to:

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
```

#### Android Location Permission

The `withAndroidFineLocation` parameter in `requestPermissions()` controls location permission requests on Android:

- **Android 12+ (API 31+)**:
  - `withAndroidFineLocation: true` → Requests `ACCESS_FINE_LOCATION` permission
  - `withAndroidFineLocation: false` → Only requests Bluetooth permissions (no location permission)
- **Android 11 and below**:
  - Location permission is always requested if declared in your manifest (required for BLE scanning)
  - The `withAndroidFineLocation` parameter is ignored

### iOS / macOS

Add `NSBluetoothPeripheralUsageDescription` and `NSBluetoothAlwaysUsageDescription` to Info.plist of your iOS and macOS app.

Add the `Bluetooth` capability to the macOS app from Xcode.

**Permissions are automatically requested when calling `startScan()`.** You can also manually call `requestPermissions()` if needed.

### Windows

Your Bluetooth adapter needs to support at least Bluetooth 4.0. If you have more than 1 adapters, the first one returned from the system will be picked.

When publishing on Windows, you need to declare the following [capabilities](https://learn.microsoft.com/en-us/windows/uwp/packaging/app-capability-declarations): `bluetooth, radios`.

### Linux

Your Bluetooth adapter needs to support at least Bluetooth 4.0. If you have more than 1 adapters, the first one returned from the system will be picked.

When publishing on Linux as a snap, you need to declare the `bluez` plug in `snapcraft.yaml`.

```
...
  plugs:
    - bluez
```

### Web

On web, the `withServices` parameter in the ScanFilter is used as [optional_services](https://developer.mozilla.org/en-US/docs/Web/API/Bluetooth/requestDevice#optionalservices) as well as a services filter. You have to set this parameter to ensure that you can access the specified services after connecting to the device. You can leave it empty for the rest of the platforms if your device does not advertise services.

```dart
ScanFilter(
  withServices: kIsWeb ?  ["SERVICE_UUID"] : [],
)
```

If you don't want to apply any filter for these services but still want to access them, after connection, use `PlatformConfig`.

```dart
UniversalBle.startScan(
  platformConfig: PlatformConfig(
    web: WebOptions(
      optionalServices: ["SERVICE_UUID"]
    )
  )
)
```

**No runtime permissions are required.** The `requestPermissions()` method always succeeds on Web.

### Manually Requesting Permissions

**Calling `requestPermissions()` is optional.** Permissions are automatically requested when calling `startScan()`. However, you can manually call `requestPermissions()` if you want to:

- Request permissions before scanning (e.g., to handle permission errors separately)
- Ensure permissions are granted before other operations like `connect()`, `read()`, `write()`, etc., which don't automatically request permissions

The `requestPermissions()` method:

- Returns successfully if all permissions are already granted or accepted by the user
- Throws a `UniversalBleException` if permissions are denied by the user
- Always succeeds on `Windows`, `Linux`, and `Web` (no runtime permissions required)

```dart
// Optional: Manually request permissions
UniversalBle.requestPermissions(
  withAndroidFineLocation: false,
);
```

> **Note**: When calling `startScan()`, permissions are automatically requested. To configure location permission requests during scanning, use the `platformConfig` parameter:

```dart
UniversalBle.startScan(
  platformConfig: PlatformConfig(
    android: AndroidOptions(
      requestLocationPermission: false,
    ),
  ),
);
```

**No runtime permissions are required.** The `requestPermissions()` method always succeeds on Windows and Linux platforms.

## Customizing Platform Implementation of Universal Ble

```dart
// Create a class that extends UniversalBlePlatform
class UniversalBleMock extends UniversalBlePlatform {
  // Implement all commands
}

UniversalBle.setInstance(UniversalBleMock());
```

## Logging

Configure logging to help debug Ble operations

### Usage

Set the log level during app initialization, default level is `none`

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Enable verbose logging to see all BLE operations
  await UniversalBle.setLogLevel(BleLogLevel.verbose);
  runApp(MyApp());
}
```

## Resetting State on Hot Restart

During Flutter hot restart in debug mode, the app state is reset but native Bluetooth connections and scan operations may persist. This can lead to connection issues or stale state.

<details> 
<summary>Use the following helper function to properly clean up BLE state before your app restarts.</summary>

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Reset BLE state before app initialization
  await resetBleState();
  runApp(MyApp());
}

/// Resets BLE state by stopping scans and disconnecting all devices.
/// Make sure you have Bluetooth permissions before calling this function.
Future<void> resetBleState() async {
  // Skip reset in release mode or on web
  if (!kDebugMode || kIsWeb) return;

  // Check Bluetooth availability
  AvailabilityState availabilityState =
      await UniversalBle.getBluetoothAvailabilityState();

  // Skip if Bluetooth is not powered on
  if (availabilityState != AvailabilityState.poweredOn) {
    debugPrint('Reset: Bluetooth is not powered on');
    return;
  }

  // Stop scanning
  if (await UniversalBle.isScanning()) {
    debugPrint('Reset: Stopping scan');
    await UniversalBle.stopScan();
  }

  // Disconnect all connected devices
  List<String> withServices = [];

  // On Apple platforms, you must specify services to discover connected devices
  if (defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS) {
    // Replace with your known device service UUIDs
    withServices = ["0x180A"];
  }

  List<BleDevice> connectedDevices =
      await UniversalBle.getSystemDevices(withServices: withServices);

  for (var device in connectedDevices) {
    debugPrint('Reset: Disconnecting device: ${device.deviceId}');
    await UniversalBle.disconnect(device.deviceId);
  }

  debugPrint('Reset: Done');
}
```

</details>

## Low level API

For more granular control, you can use the [Low-Level API](README.low_level.md). This API is "Device ID"-based, offering greater flexibility by enabling direct calls without the need for object instances.

## App showcase

Here are some of the apps leveraging the power of `universal_ble`:

- [**Universal BLE**](https://apps.apple.com/app/id6756538573) ([App Store](https://apps.apple.com/app/id6756538573) | [Play Store](https://play.google.com/store/apps/details?id=com.navideck.universalble)) - A comprehensive developer tool for exploring and testing Bluetooth Low Energy (BLE) devices. It enables scanning for nearby BLE devices, connecting to peripherals, discovering and exploring services, characteristics, and descriptors. Supports reading and writing characteristic values, enabling notifications and indications, viewing device information and signal strength, and provides detailed logging of BLE operations. Perfect for developers, engineers, and hobbyist tinkerers working with BLE-enabled devices across iOS, Android, macOS, Windows, Linux & Web.
- [**BT Cam**](https://btcam.app) - A Bluetooth remote app for DSLR and mirrorless cameras. Compatible with Canon, Nikon, Sony, Fujifilm, GoPro, Olympus, Panasonic, Pentax, and Blackmagic. Built using Universal BLE to connect and control cameras across iOS, Android, macOS, Windows, Linux & Web.
- [**TukToro**](https://tuktoro.com/en/pages/download-math-learning-app) - Interactive math learning app for kids. Available on iPad and Android tablets, featuring hand-drawn levels, didactic learning games, and ad-free child-safe environment.
- [**BikeControl**](https://github.com/jonasbark/swiftcontrol) - Control your favorite trainer app using Zwift Click, Zwift Ride, Zwift Play, Shimano Di2, or other similar devices. Enables virtual gear shifting, steering, workout intensity adjustment, and more across iOS, Android, macOS, Windows, and Linux.
- [**Roll Feathers**](https://github.com/cliftbar/roll_feathers) - Companion app for Bluetooth enabled dice. Connect multiple supported dice (Pixel Dice, GoDice, Virtual Dice), track roll history, and integrate with Home Assistant. Available on Android, iOS, macOS, Windows, Linux, and Web.
- [**OpenEarable**](https://open-earable.teco.edu/) - Fully open-source AI platform for ear-based sensing applications with true wireless audio. Features high-precision sensors for biosensing, cardiac monitoring, and motion tracking. Cross-platform support for iOS, Android, and desktop platforms.
- [**Ledger Flutter Plus**](https://github.com/vespr-wallet/ledger-flutter-plus) - A Flutter plugin to scan, connect & sign transactions using Ledger Nano devices via USB & BLE. Supports Android, iOS, and Web platforms for secure cryptocurrency wallet management.
- [**Flutter MIDI Command**](https://pub.dev/packages/flutter_midi_command) - Flutter plugin for sending and receiving MIDI messages between Flutter and physical/virtual MIDI devices. Supports USB and BLE transports across iOS, macOS, Android, Linux, and Windows.
- [**NT Helper**](https://github.com/thorinside/nt_helper) - Cross-platform Flutter application for editing presets on the Expert Sleepers Disting NT module. Provides comprehensive preset management, algorithm editing, parameter mapping, and routing analysis. Available on Windows, macOS, Linux, iOS, and Android.
- [**MOCs Train Controller**](https://github.com/sonnny/mocs_train_controller) - Model train controller using Raspberry Pi Pico W and Flutter. Control trains via Bluetooth Low Energy with support for Android, iOS, and Linux platforms.


> 💡 **Built something cool with Universal BLE?**  
> We'd love to showcase your app here!  
> Open a pull request and add it to this section.
