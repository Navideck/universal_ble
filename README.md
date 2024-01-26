# Universal BLE

[![universal_ble version](https://img.shields.io/pub/v/universal_ble?label=universal_ble)](https://pub.dev/packages/universal_ble)

A cross-platform (Android/iOS/macOS/Windows/Linux/Web) Bluetooth Low Energy (BLE) plugin for Flutter

## Features

- [Scanning](#scanning)
- [Connecting](#connecting)
- [Discovering Services](#discovering-services)
- [Reading & Writing data](#reading--writing-data)
- [Pairing](#pairing)
- [Bluetooth Availability](#bluetooth-availability)

The example code in this project is hosted on Github pages. Checkout [WebApp Example](https://navideck.github.io/universal_ble/)

### API Support Matrix

| API                  | Android | iOS | macOS | Windows (beta) | Linux (beta) | Web |
| :------------------- | :-----: | :-: | :---: | :------------: | :----------: | :-: |
| startScan/stopScan   |   ✔️    | ✔️  |  ✔️   |       ✔️       |      ✔️      | ✔️  |
| connect/disconnect   |   ✔️    | ✔️  |  ✔️   |       ✔️       |      ✔️      | ✔️  |
| getConnectedDevices  |   ✔️    | ✔️  |  ✔️   |       ✔️       |      ✔️      | ❌  |
| discoverServices     |   ✔️    | ✔️  |  ✔️   |       ✔️       |      ✔️      | ✔️  |
| readValue            |   ✔️    | ✔️  |  ✔️   |       ✔️       |      ✔️      | ✔️  |
| writeValue           |   ✔️    | ✔️  |  ✔️   |       ✔️       |      ✔️      | ✔️  |
| setNotifiable        |   ✔️    | ✔️  |  ✔️   |       ✔️       |      ✔️      | ✔️  |
| pair/unPair          |   ✔️    | ❌  |  ❌   |       ✔️       |      ✔️      | ❌  |
| onPairingStateChange |   ✔️    | ❌  |  ❌   |       ✔️       |      ✔️      | ❌  |
| enableBluetooth      |   ✔️    | ❌  |  ❌   |       ✔️       |      ✔️      | ❌  |
| onAvailabilityChange |   ✔️    | ✔️  |  ✔️   |       ✔️       |      ✔️      | ✔️  |
| requestMtu           |   ✔️    | ✔️  |  ✔️   |       ✔️       |      🚧      | ❌  |

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
UniversalBle.onScanResult = (scanResult) {
  // e.g. Use scan result to connect
}

// Perform a scan
UniversalBle.startScan();

// Stop scanning
UniversalBle.stopScan();
```

Already connected devices, either through previous sessions or connected through system settings, won't show up as scan results.
You can list those devices using `getConnectedDevices()`. You still need to explicitly connect before using them.

```dart
// You can set `withServices` to narrow down the results
await UniversalBle.getConnectedDevices(withServices: []);
```

### Connecting

```dart
// Connect to a device using the `deviceId` of the scanResult received from `UniversalBle.onScanResult`
String deviceId = scanResult.deviceId;
UniversalBle.connect(deviceId);

// Disconnect from a device
UniversalBle.disconnect(deviceId);

// Get notified for connection state changes
UniversalBle.onConnectionChanged = (String deviceId, BleConnectionState state) {
  print('OnConnectionChanged $deviceId, $state');
}
```

### Discovering Services

```dart
// Discover services of a specific device
UniversalBle.discoverServices(deviceId);
```

### Reading & Writing data

```dart
// Read data from a characteristic
UniversalBle.readValue(deviceId, serviceId, characteristicId);

// Write data to a characteristic
UniversalBle.writeValue(deviceId, serviceId, characteristicId, value);

// Subscribe to a characteristic
UniversalBle.setNotifiable(deviceId, serviceId, characteristicId, BleInputProperty.notification);

// Get characteristic updates in `onValueChanged`
UniversalBle.onValueChanged = (String deviceId, String characteristicId, Uint8List value) {
  print('onValueChanged $deviceId, $characteristicId, ${hex.encode(value)}');
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

### Web

On web, you have to add filters and specify optional services when scanning for devices. The parameter is ignored on other platforms.

```dart
UniversalBle.startScan(
  webRequestOptions: WebRequestOptionsBuilder.acceptAllDevices(
    optionalServices: ["SERVICE_UUID"],
  ),
);
```

## Customizing Platform Implementation of UniversalBle

```dart
// Create a class that extends UniversalBlePlatform
class UniversalBleMock extends UniversalBlePlatform {
  // Implement all methods
}

UniversalBle.setInstance(UniversalBleMock());
```
