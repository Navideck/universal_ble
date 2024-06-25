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
- [Command Queue](#command-queue)
- [Timeout](#timeout)

### API Support Matrix

| API                  | Android | iOS | macOS | Windows | Linux (beta) | Web |
| :------------------- | :-----: | :-: | :---: | :-----: | :----------: | :-: |
| startScan/stopScan   |   ✔️    | ✔️  |  ✔️   |   ✔️    |      ✔️      | ✔️  |
| connect/disconnect   |   ✔️    | ✔️  |  ✔️   |   ✔️    |      ✔️      | ✔️  |
| getSystemDevices     |   ✔️    | ✔️  |  ✔️   |   ✔️    |      ✔️      | ❌  |
| discoverServices     |   ✔️    | ✔️  |  ✔️   |   ✔️    |      ✔️      | ✔️  |
| readValue            |   ✔️    | ✔️  |  ✔️   |   ✔️    |      ✔️      | ✔️  |
| writeValue           |   ✔️    | ✔️  |  ✔️   |   ✔️    |      ✔️      | ✔️  |
| setNotifiable        |   ✔️    | ✔️  |  ✔️   |   ✔️    |      ✔️      | ✔️  |
| pair/unPair          |   ✔️    | ❌  |  ❌   |   ✔️    |      ✔️      | ❌  |
| onPairingStateChange |   ✔️    | ❌  |  ❌   |   ✔️    |      ✔️      | ❌  |
| enableBluetooth      |   ✔️    | ❌  |  ❌   |   ✔️    |      ✔️      | ❌  |
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
// Set a scan result handler
UniversalBle.onScanResult = (bleDevice) {
  // e.g. Use BleDevice ID to connect
}

// Perform a scan
UniversalBle.startScan();

// Or optionally add a scan filter
UniversalBle.startScan(
  scanFilter: ScanFilter(
    withServices: ["SERVICE_UUID"],
    withManufacturerData: ["MANUFACTURER_DATA"]
  )
);

// Stop scanning
UniversalBle.stopScan();
```

Before initiating a scan, ensure that Bluetooth is available:

```dart
AvailabilityState state = await UniversalBle.getBluetoothAvailabilityState();
// Start scan only if Bluetooth is powered on
if (state == AvailabilityState.poweredOn) {
  UniversalBle.startScan();
}

// Or listen to bluetooth availability changes
UniversalBle.onAvailabilityChange = (state) {
  if (state == AvailabilityState.poweredOn) {
    UniversalBle.startScan();
  }
};
```

See the [Bluetooth Availability](#bluetooth-availability) section for more.

#### System Devices

Already connected devices, connected either through previous sessions, other apps or through system settings, won't show up as scan results. You can get those using `getSystemDevices()`.

```dart
// Get already connected devices
// You can set `withServices` to narrow down the results
// On `Apple`, `withServices` is required to get connected devices, else [1800] service will be used as default filter.
List<BleDevice> devices = await UniversalBle.getSystemDevices(withServices: []);
```

For each such device the `isSystemDevice` property will be `true`.

You still need to explicitly [connect](#connecting) to them before being able to use them.

#### Scan Filter

You can optionally set filters when scanning.

##### With Services

When setting this parameter, the scan results will only include devices that advertize any of the specified services. This is the primary filter. All devices are first filtered by services, then further filtered by other criteria. This parameter is mandatory on [web](#web) if you want to access those services.

```dart
List<String> withServices;
```

##### With ManufacturerData

Use the `withManufacturerData` parameter to filter devices by manufacturer data. When you pass a list of `ManufacturerDataFilter` objects to this parameter, the scan results will only include devices that contain any of the specified manufacturer data.

```dart
List<ManufacturerDataFilter> withManufacturerData;
```

##### With namePrefix

Use the `withNamePrefix` parameter to filter devices by names (case sensitive). When you pass a list of names, the scan results will only include devices that have this name or start with the provided parameter.

```dart
List<String> withNamePrefix;
```

### Connecting

```dart
// Connect to a device using the `deviceId` of the BleDevice received from `UniversalBle.onScanResult`
String deviceId = bleDevice.deviceId;
UniversalBle.connect(deviceId);

// Disconnect from a device
UniversalBle.disconnect(deviceId);

// Get connection/disconnection updates
UniversalBle.onConnectionChange = (String deviceId, bool isConnected) {
  debugPrint('OnConnectionChange $deviceId, $isConnected');
}

// Get current connection state
// Can be connected, disconnected, connecting or disconnecting
BleConnectionState connectionState = await bleDevice.connectionState;
```

### Discovering Services

After establishing a connection, you need to discover services. This method will discover all services and their characteristics.

```dart
// Discover services of a specific device
UniversalBle.discoverServices(deviceId);
```

### Reading & Writing data

You need to first [discover services](#discovering-services) before you are able to read and write to characteristics.

```dart
// Read data from a characteristic
UniversalBle.readValue(deviceId, serviceId, characteristicId);

// Write data to a characteristic
UniversalBle.writeValue(deviceId, serviceId, characteristicId, value);

// Subscribe to a characteristic
UniversalBle.setNotifiable(deviceId, serviceId, characteristicId, BleInputProperty.notification);

// Get characteristic updates in `onValueChange`
UniversalBle.onValueChange = (String deviceId, String characteristicId, Uint8List value) {
  debugPrint('onValueChange $deviceId, $characteristicId, ${hex.encode(value)}');
}

// Unsubscribe from a characteristic
UniversalBle.setNotifiable(deviceId, serviceId, characteristicId, BleInputProperty.disabled);
```

### Pairing

```dart
// Pair
UniversalBle.pair(deviceId);

// Get the pairing result
UniversalBle.onPairingStateChange = (String deviceId, bool isPaired, String? error) {
  // Handle Pairing state change
}

// Unpair
UniversalBle.unPair(deviceId);

// Check current pairing state
bool isPaired = UniversalBle.isPaired(deviceId);
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
```

## Command Queue

By default, all commands are executed in a global queue (`QueueType.global`), with each command waiting for the previous one to finish.

If you want to parallelize commands between multiple devices, you can set:

```dart
// Create a separate queue for each device.
UniversalBle.queueType = QueueType.perDevice;
```

You can also disable the queue completely and parallelize all commands, even for the same device, by using:

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

## Timeout

By default, all commands have a timeout of 10 seconds.

```dart
// Change timeout
UniversalBle.timeout = const Duration(seconds: 10);

// Disable timeout
UniversalBle.timeout = null;
```

## Platform-Specific Setup

### Android

Add the following permissions to your AndroidManifest.xml file:

```xml
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" android:maxSdkVersion="30" />
```

If you use `BLUETOOTH_SCAN` to determine location, modify your AndroidManifest.xml file to include the following entry:

```xml
 <uses-permission android:name="android.permission.BLUETOOTH_SCAN" tools:remove="android:usesPermissionFlags" tools:targetApi="s" />
```

If your app uses location services, remove `android:maxSdkVersion="30"` from the location permission tags.

### iOS / macOS

Add `NSBluetoothPeripheralUsageDescription` and `NSBluetoothAlwaysUsageDescription` to Info.plist of your iOS and macOS app.

Add the `Bluetooth` capability to the macOS app from Xcode.

### Windows / Linux

Your Bluetooth adapter needs to support at least Bluetooth 4.0. If you have more than 1 adapters, the first one returned from the system will be picked.

When publishing on Windows you need to declare the following [capabilities](https://learn.microsoft.com/en-us/windows/uwp/packaging/app-capability-declarations): `bluetooth, radios`.

### Web

On web, the `withServices` parameter in the ScanFilter is used as [optional_services](https://developer.mozilla.org/en-US/docs/Web/API/Bluetooth/requestDevice#optionalservices) as well as a services filter. On web you have to set this parameter to ensure that you can access the specified services after connecting to the device. You can leave it empty for the rest of the platforms if your device does not advertize services.

```dart
ScanFilter(
      withServices: kIsWeb ?  ["SERVICE_UUID"] : [],
)
```

## Note

All Characteristic and Services UUID's will be in 128 bit format in lowercase across all platforms, so its best to always use 128 bit lowercase UUID strings with the plugin

You can also use `Uuid.parse` to convert a string to a valid 128 bit UUID string, or `Uuid.parseShort` to creates a valid 128 bit Bluetooth UUID from the short (16 or 32 bit) encoding.

## Customizing Platform Implementation of UniversalBle

```dart
// Create a class that extends UniversalBlePlatform
class UniversalBleMock extends UniversalBlePlatform {
  // Implement all commands
}

UniversalBle.setInstance(UniversalBleMock());
```
