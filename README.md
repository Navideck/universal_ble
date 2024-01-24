# Universal BLE

A cross-platform (Android/iOS/macOS/Windows/Linux/Web) Bluetooth Low Energy (BLE) plugin for Flutter

## Features

- [Scanning for BLE Peripherals](#scanning-for-ble-peripherals)
- [Connecting to BLE Peripheral](#connecting-to-ble-peripheral)
- [Discovering Services of BLE Peripheral](#discovering-services-of-ble-peripheral)
- [Transferring Data between BLE Central & Peripheral](#transferring-data-between-ble-central--peripheral)
- [Pairing BLE Peripheral](#pairing-ble-central--peripheral)
- [Receiving BLE Availability Changes](#receiving-ble-availability-changes)

### API Support Matrix

| API                  | Android | iOS | macOS | Windows (beta) | Linux (beta) | Web |
| :------------------- | :-----: | :-: | :---: | :-----: | :---: | :-: |
| startScan/stopScan   |   ✔️    | ✔️  |  ✔️   |   ✔️    |  ✔️   | ✔️  |
| connect/disconnect   |   ✔️    | ✔️  |  ✔️   |   ✔️    |  ✔️   | ✔️  |
| getConnectedDevices  |   ✔️    | ✔️  |  ✔️   |   ✔️    |  ✔️   | ❌  |
| discoverServices     |   ✔️    | ✔️  |  ✔️   |   ✔️    |  ✔️   | ✔️  |
| readValue            |   ✔️    | ✔️  |  ✔️   |   ✔️    |  ✔️   | ✔️  |
| writeValue           |   ✔️    | ✔️  |  ✔️   |   ✔️    |  ✔️   | ✔️  |
| setNotifiable        |   ✔️    | ✔️  |  ✔️   |   ✔️    |  ✔️   | ✔️  |
| pair/unPair          |   ✔️    | ❌  |  ❌   |   ✔️    |  ✔️   | ❌  |
| onPairStateChange    |   ✔️    | ❌  |  ❌   |   ✔️    |  ✔️   | ❌  |
| enableBluetooth      |   ✔️    | ❌  |  ❌   |   ✔️    |  ✔️   | ❌  |
| onAvailabilityChange |   ✔️    | ✔️  |  ✔️   |   ✔️    |  ✔️   | ✔️  |
| requestMtu           |   ✔️    | ✔️  |  ✔️   |   ✔️    |  ❌   | 🚧  |

## Getting Started

### Scanning for BLE Peripherals

```dart
// Set a scan result handler
UniversalBle.onScanResult = (scanResult) {
  // e.g. Use scan result to connect
}

// Perform a scan
UniversalBle.startScan();

// On web, you can add filters and specify optional services to discover after connection. The parameter is ignored on other platforms.
UniversalBle.startScan(
  webRequestOptions: WebRequestOptionsBuilder.acceptAllDevices(
    optionalServices: ["SERVICE_UUID"],
  ),
);

// Stop scanning
UniversalBle.stopScan();
```

Already connected devices won't show up as scan results.
You can list the already connected devices using `getConnectedDevices()`. You still need to explicitly connect before using them.

```dart
// You can set `withServices` to narrow down the results
await UniversalBle.getConnectedDevices(withServices: []);
```

### Connecting to BLE Peripheral

```dart
// Connect to a peripheral using the `deviceId` of the scanResult received from `UniversalBle.onScanResult`
String deviceId = scanResult.deviceId;
UniversalBle.connect(deviceId);

// Disconnect from a peripheral
UniversalBle.disconnect(deviceId);

// Get notified for connection state changes
UniversalBle.onConnectionChanged = (String deviceId, BleConnectionState state) {
  print('OnConnectionChanged $deviceId, $state');
}
```

### Discovering Services of BLE Peripheral

```dart
// Discover services of a specific `deviceId`
UniversalBle.discoverServices(deviceId);
```

### Transferring Data between BLE Central & Peripheral

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

### Pairing BLE Central & Peripheral

```dart
// Pair
UniversalBle.pair(deviceId);

// Get the pairing result
UniversalBle.onPairStateChange = (String deviceId, bool isPaired, String? error) {
  // Handle Pairing state change
}

// Unpair
UniversalBle.unPair(deviceId);

// Check current pairing status
bool isPaired = UniversalBle.isPaired(deviceId);
```

### Enable Bluetooth Programmatically

```dart
UniversalBle.enableBluetooth();
```

### Receiving BLE Availability Changes

```dart
UniversalBle.onAvailabilityChange = (state) {
  // Handle BLE availability states
  // e.g. poweredOff or poweredOn,
};
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

## Customizing Platform Implementation of UniversalBle

```dart
// Create a class that extends UniversalBlePlatform
class UniversalBleMock extends UniversalBlePlatform {
  // Implement all methods
}