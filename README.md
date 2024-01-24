# Universal Ble

A cross-platform (Android/iOS/MacOS/Windows/Linux/Web) BluetoothLE plugin for Flutter

# Usage

- [Receive BLE availability changes](#receive-ble-availability-changes)
- [Scan BLE peripheral](#scan-ble-peripheral)
- [Connect BLE peripheral](#connect-ble-peripheral)
- [Discover services of BLE peripheral](#discover-services-of-ble-peripheral)
- [Transfer data between BLE central & peripheral](#transfer-data-between-ble-central--peripheral)
- [Pair BLE peripheral](#pair-ble-central--peripheral)

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
| requestMtu           |   ✔️    | ✔️  |  ✔️   |   ✔️    |  ❌   | ❌  |

## Getting Started

### Android

You need to add the following permissions to your AndroidManifest.xml file:

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

If you use location services in your app, remove `android:maxSdkVersion="30"` from the location permission tags

### iOS / MacOS

Add `NSBluetoothPeripheralUsageDescription` and `NSBluetoothAlwaysUsageDescription` in Info.plist of your iOS and MacOS app,

Add `Bluetooth` capability to MacOS app from Xcode

## Scan BLE peripheral

Android/iOS/macOS/Windows/Linux

```dart
UniversalBle.onScanResult = (scanResult) {
  // Handle scan result
}

UniversalBle.startScan();

// To scan on web, you can optionally add filters, and `optionalServices` required to discover those services after connection, for more info check [this](https://developer.mozilla.org/en-US/docs/Web/API/Bluetooth/requestDevice)
UniversalBle.startScan(
  webRequestOptions: WebRequestOptionsBuilder.acceptAllDevices(
    optionalServices: [
      "SERVICE_UUID",
    ],
  )
);

UniversalBle.stopScan();
```

## Connect to BLE peripheral

Connect to `deviceId`, received from `UniversalBle.onScanResult`

```dart
UniversalBle.onConnectionChanged = (String deviceId, BleConnectionState state) {
  print('onConnectionChanged $deviceId, $state');
}

UniversalBle.connect(deviceId);

UniversalBle.disconnect(deviceId);
```

Get connected devices ( These devices might be connected through another applications, connect using `connect` method to use in your application ), use `withServices` to filter devices

```dart
await UniversalBle.getConnectedDevices(withServices: []);
```

## Discover services of BLE peripheral

Discover services of `deviceId`

```dart
UniversalBle.discoverServices(deviceId);
```

## Transfer data between BLE central & peripheral

- Pull data from peripheral of `deviceId`

```dart
UniversalBle.readValue(deviceId, serviceId, characteristicId);
```

- Send data to peripheral of `deviceId`

```dart
UniversalBle.writeValue(deviceId, serviceId, characteristicId, value);
```

- Receive data from peripheral of `deviceId`

```dart
UniversalBle.onValueChanged = (String deviceId, String characteristicId, Uint8List value) {
  print('onValueChanged $deviceId, $characteristicId, ${hex.encode(value)}');
}

// To get characteristic updates in `onValueChanged`
UniversalBle.setNotifiable(deviceId, serviceId, characteristicId, BleInputProperty.notification);

// To stop updates
UniversalBle.setNotifiable(deviceId, serviceId, characteristicId, BleInputProperty.disabled);
```

## Pair BLE central & peripheral

- Pair apis

```dart
UniversalBle.onPairStateChange = (String deviceId, bool isPaired, String? error) {
  // Handle Pairing state change
}

// Get result in [onPairStateChange]
UniversalBle.pair(deviceId);

UniversalBle.unPair(deviceId);

UniversalBle.isPaired(deviceId);
```

## Enable bluetooth programatically

```dart
UniversalBle.enableBluetooth();
```

## Receive BLE availability changes

```dart
UniversalBle.onAvailabilityChange = (state) {
  // Handle ble availability states
  // e.g. poweredOff or poweredOn,
};
```

## To set your own implementation of UniversalBle for any specific platform

```dart
// Create a class which extends `UniversalBlePlatform`
class UniversalBleMock extends UniversalBlePlatform {
  // Implement all methods
}

UniversalBle.setInstance(UniversalBleMock());
```
