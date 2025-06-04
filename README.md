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
- [UUID Format Agnostic](#uuid-format-agnostic)

## API Support

|                      | Android | iOS | macOS | Windows | Linux | Web |
| :------------------- | :-----: | :-: | :---: | :-----: | :----------: | :-: |
| startScan/stopScan   |   ✔️    | ✔️  |  ✔️   |   ✔️    |      ✔️      | ✔️  |
| connect/disconnect   |   ✔️    | ✔️  |  ✔️   |   ✔️    |      ✔️      | ✔️  |
| getSystemDevices     |   ✔️    | ✔️  |  ✔️   |   ✔️    |      ✔️      | ❌  |
| discoverServices     |   ✔️    | ✔️  |  ✔️   |   ✔️    |      ✔️      | ✔️  |
| readValue            |   ✔️    | ✔️  |  ✔️   |   ✔️    |      ✔️      | ✔️  |
| writeValue           |   ✔️    | ✔️  |  ✔️   |   ✔️    |      ✔️      | ✔️  |
| setNotifiable        |   ✔️    | ✔️  |  ✔️   |   ✔️    |      ✔️      | ✔️  |
| pair                 |   ✔️    | ✔️  |  ✔️   |   ✔️    |      ✔️      | ⏺  |
| unpair               |   ✔️    | ❌  |  ❌   |   ✔️    |      ✔️      | ❌  |
| isPaired             |   ✔️    | ✔️  |  ✔️   |   ✔️    |      ✔️      | ✔️  |
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

### Connecting

#### Connect

Connects to the BLE device. This method initiates a connection to the Bluetooth device.

```dart
await device.connect();
print('Device connected');
```

#### Disconnect

Disconnects from the BLE device. This method terminates the connection to the Bluetooth device.

```dart
await device.disconnect();
print('Device disconnected');
```

#### Connection Stream

```dart
device.connectionStream.listen((isConnected) {
  print('Device is connected: $isConnected');
});
```

#### IsConnected

```dart
bool connected = await device.isConnected;
print('Device is connected: $connected');
```

### Discovering Services

After establishing a connection, you need to discover services. This method will discover all services and their characteristics.

#### DiscoverServices

Discovers the services offered by the device. Returns a `Future<List<BleService>>`.

- `cached`: If `true` (default), cached services are returned if available. The cache is reset on disconnect. If `false`, fresh services are always discovered.

```dart
List<BleService> services = await device.discoverServices();
for (var service in services) {
  print('Service UUID: ${service.uuid}');
}
```

#### GetService

Retrieves a specific service. Returns a `Future<BleService>`.

- `service`: The UUID of the service.
- `cached`: If `true` (default), cached services are used.

```dart
BleService service = await device.getService('180a');
```

#### GetCharacteristic

Retrieves a specific characteristic from a service. Returns a `Future<BleCharacteristic>`.

- `service`: The UUID of the service.
- `characteristic`: The UUID of the characteristic.
- `cached`: If `true` (default), cached services are used.

```dart
BleCharacteristic characteristic = await device.getCharacteristic('180a','2a56');
```

Or retrieve from `BleService`

```dart
BleCharacteristic characteristic = await service.getCharacteristic('2a56');
```

## Notifications

Get `BleCharacteristic` using `bleDevice.getCharacteristic`

### OnValueReceived

A stream of `Uint8List` that emits values received from the characteristic. Listen to this stream to receive updates whenever the characteristic's value changes.

```dart
characteristic.onValueReceived.listen((value) {
  print('Received value: ${value.toString()}');
});
```

### SetNotify

Enables notifications for this characteristic. Throws an exception if the characteristic does not support notifications.

```dart
await characteristic.setNotify();
```

### SetIndication

Enables indications for this characteristic. Throws an exception if the characteristic does not support indications.

```dart
await characteristic.setIndication();
```

### DisableNotify

Disables notifications for this characteristic.

```dart
await characteristic.disableNotify();
print('Notifications disabled');
```

### Reading & Writing data

You need to first [discover services](#discovering-services) before you are able to read and write to characteristics.

```dart
Uint8List value = await characteristic.read();
print('Value: ${value.toString()}');
```

```dart
await characteristic.write([0x01, 0x02, 0x03]);
print('Value written');

await characteristic.write([0x01, 0x02, 0x03], withoutResponse: true);
print('Value written without response');
```

```dart
// Write data to a characteristic
UniversalBle.writeValue(deviceId, serviceId, characteristicId, value);

// Subscribe to a characteristic
UniversalBle.setNotifiable(deviceId, serviceId, characteristicId, BleInputProperty.notification);

// Get characteristic updates using stream
UniversalBle.characteristicValueStream(deviceId, characteristicId).listen((Uint8List value) {
  debugPrint('OnValueChange $deviceId, $characteristicId, ${hex.encode(value)}');
});

// Or set a handler to get updates of all characteristics
UniversalBle.onValueChange = (String deviceId, String characteristicId, Uint8List value) {
  debugPrint('onValueChange $deviceId, $characteristicId, ${hex.encode(value)}');
}

// Unsubscribe from a characteristic
UniversalBle.setNotifiable(deviceId, serviceId, characteristicId, BleInputProperty.disabled);
```

### Pairing

#### Trigger pairing

##### Pair on Android, Windows, Linux

```dart
await UniversalBle.pair(deviceId);
```

##### Pair on Apple and web
For Apple and Web, pairing support depends on the device. Pairing is triggered automatically by the OS when you try to read/write from/to an encrypted characteristic.

Calling `UniversalBle.pair(deviceId)` will only trigger pairing if the device has an *encrypted read characteristic*.

If your device only has encrypted write characteristics or you happen to know which encrypted read characteristic you want to use, you can pass it with a `pairingCommand`.

```dart
UniversalBle.pair(deviceId, pairingCommand: BleCommand(service:"SERVICE", characteristic:"ENCRYPTED_CHARACTERISTIC"));
```
After pairing you can check the pairing status.

#### Pairing status

##### Pair on Android, Windows, Linux

```dart
// Check current pairing state
bool? isPaired = UniversalBle.isPaired(deviceId);
```

##### Pair on Apple and web

For `Apple` and `Web`, you have to pass a "pairingCommand" with an encrypted read or write characteristic. If you don't pass it then it will return `null`.

```dart
bool? isPaired = await UniversalBle.isPaired(deviceId, pairingCommand: BleCommand(service:"SERVICE", characteristic:"ENCRYPTED_CHARACTERISTIC"));
```

##### Discovering encrypted characteristic
To discover encrypted characteristics, make sure your device is not paired and use the example app to read/write to all discovered characteristics one by one. If one of them triggers pairing, that means it is encrypted and you can use it to construct `BleCommand(service:"SERVICE", characteristic:"ENCRYPTED_CHARACTERISTIC")`.

#### Pairing state changes

```dart
// Get pairing state updates using stream
UniversalBle.pairingStateStream(deviceId).listen((bool isPaired) {
  // Handle pairing state change
});

// Or set a handler to get pairing state updates of all devices
UniversalBle.onPairingStateChange = (String deviceId, bool isPaired) {}
```

#### Unpair
```dart
UniversalBle.unpair(deviceId);
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
int mtu = await device.requestMtu(256);
print('MTU size: $mtu');
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

## Timeout

By default, all commands have a timeout of 10 seconds.

```dart
// Change timeout
UniversalBle.timeout = const Duration(seconds: 10);

// Disable timeout
UniversalBle.timeout = null;
```

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


## 🧩 Apps using Universal BLE

Here are some of the apps leveraging the power of `universal_ble` in production:

| <img src="assets/bt_cam_icon.svg" alt="BT Cam Icon" width="224" height="224"> | [**BT Cam**](https://btcam.app)<br>A Bluetooth remote app for DSLR and mirrorless cameras. Compatible with Canon, Nikon, Sony, Fujifilm, GoPro, Olympus, Panasonic, Pentax, and Blackmagic. Built using Universal BLE to connect and control cameras across iOS, Android, macOS, Windows, Linux & Web. |
|:--:|:--|
> 💡 **Built something cool with Universal BLE?**  
> We'd love to showcase your app here!  
> Open a pull request and add it to this section. Please include your app icon in svg!