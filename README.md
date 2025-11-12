# Universal BLE

[![universal_ble version](https://img.shields.io/pub/v/universal_ble?label=universal_ble)](https://pub.dev/packages/universal_ble)

A cross-platform (Android/iOS/macOS/Windows/Linux/Web) Bluetooth Low Energy (BLE) plugin for Flutter.

[Try it online](https://navideck.github.io/universal_ble/), provided your browser supports [Web Bluetooth](https://caniuse.com/web-bluetooth).

## Features

- [Scanning](#scanning)
- [Connecting](#connecting)
- [Discovering Services](#discovering-services)
- [Reading & Writing data](#reading--writing-data)
- [Pairing](#pairing)
- [Bluetooth Availability](#bluetooth-availability)
- [Requesting MTU](#requesting-mtu)
- [Command Queue](#command-queue)
- [Timeout](#timeout)
- [Error Handling](#error-handling)
- [UUID Format Agnostic](#uuid-format-agnostic)

## API Support

|                      | Android | iOS | macOS | Windows | Linux | Web |
| :------------------- | :-----: | :-: | :---: | :-----: | :----------: | :-: |
| startScan/stopScan   |   ✔️    | ✔️  |  ✔️   |   ✔️    |      ✔️      | ✔️  |
| connect/disconnect   |   ✔️    | ✔️  |  ✔️   |   ✔️    |      ✔️      | ✔️  |
| getSystemDevices     |   ✔️    | ✔️  |  ✔️   |   ✔️    |      ✔️      | ❌  |
| discoverServices     |   ✔️    | ✔️  |  ✔️   |   ✔️    |      ✔️      | ✔️  |
| read                 |   ✔️    | ✔️  |  ✔️   |   ✔️    |      ✔️      | ✔️  |
| write                |   ✔️    | ✔️  |  ✔️   |   ✔️    |      ✔️      | ✔️  |
| subscriptions        |   ✔️    | ✔️  |  ✔️   |   ✔️    |      ✔️      | ✔️  |
| pair                 |   ✔️    | ✔️  |  ✔️   |   ✔️    |      ✔️      | ⏺  |
| unpair               |   ✔️    | ❌  |  ❌   |   ✔️    |      ✔️      | ❌  |
| isPaired           |   ✔️    | ✔️  |  ✔️   |   ✔️    |      ✔️      | ✔️  |
| onPairingStateChange |   ✔️    | ⏺  |  ⏺   |   ✔️    |      ✔️      | ⏺  |
| getBluetoothAvailabilityState |   ✔️    | ✔️  |  ✔️   |   ✔️    |      ✔️      | ❌  |
| enable/disable Bluetooth      |   ✔️    | ❌  |  ❌   |   ✔️    |      ✔️      | ❌  |
| onAvailabilityChange |   ✔️    | ✔️  |  ✔️   |   ✔️    |      ✔️      | ✔️  |
| requestMtu           |   ✔️    | ✔️  |  ✔️   |   ✔️    |      ✔️      | ❌  |

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

### Scanning

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

Calling `bleDevice.pair()` will only trigger pairing if the device has an *encrypted read characteristic*.

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

#### Platform Limitations

On most platforms, the MTU can only be queried but not manually set:

- **iOS/macOS**: System automatically sets MTU to 185 bytes maximum
- **Android 14+**: System automatically sets MTU to 517 bytes for the first GATT client
- **Windows**: MTU can only be queried
- **Linux**: MTU can only be queried
- **Web**: No mechanism to query or modify MTU size

#### Best Practices

When developing cross-platform BLE applications and devices:

- Design for default MTU size (23 bytes) as default
- Dynamically adapt to use larger packet sizes when the system provides them
- Take advantage of the increased throughput when available without requiring it
- Implement data fragmentation for larger transfers
- Handle platform-specific MTU size based on current value

#### Resetting State on Hot Restart

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

## Platform-specific Setup

### Android

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

You need to programmatically request permissions on runtime. You could use a package such as [permission_handler](https://pub.dev/packages/permission_handler).
For Android 12+, request `Permission.bluetoothScan` and `Permission.bluetoothConnect`.
For Android 11 and below, request `Permission.location`.

### iOS / macOS

Add `NSBluetoothPeripheralUsageDescription` and `NSBluetoothAlwaysUsageDescription` to Info.plist of your iOS and macOS app.

Add the `Bluetooth` capability to the macOS app from Xcode.

### Windows / Linux

Your Bluetooth adapter needs to support at least Bluetooth 4.0. If you have more than 1 adapters, the first one returned from the system will be picked.

When publishing on Windows, you need to declare the following [capabilities](https://learn.microsoft.com/en-us/windows/uwp/packaging/app-capability-declarations): `bluetooth, radios`.

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

## Customizing Platform Implementation of Universal Ble

```dart
// Create a class that extends UniversalBlePlatform
class UniversalBleMock extends UniversalBlePlatform {
  // Implement all commands
}

UniversalBle.setInstance(UniversalBleMock());
```

## Low level API

For more granular control, you can use the [Low-Level API](README.low_level.md). This API is "Device ID"-based, offering greater flexibility by enabling direct calls without the need for object instances.

## 🧩 Apps using Universal BLE

Here are some of the apps leveraging the power of `universal_ble` in production:

| <img src="assets/bt_cam_icon.svg" alt="BT Cam Icon" width="224" height="224"> | [**BT Cam**](https://btcam.app)<br>A Bluetooth remote app for DSLR and mirrorless cameras. Compatible with Canon, Nikon, Sony, Fujifilm, GoPro, Olympus, Panasonic, Pentax, and Blackmagic. Built using Universal BLE to connect and control cameras across iOS, Android, macOS, Windows, Linux & Web. |
|:--:|:--|
> 💡 **Built something cool with Universal BLE?**  
> We'd love to showcase your app here!  
> Open a pull request and add it to this section. Please include your app icon in svg!