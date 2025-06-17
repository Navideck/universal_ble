# Low Level API

### Connecting

```dart
// Connect to a device using the `deviceId` of the BleDevice received from `UniversalBle.onScanResult`
String deviceId = bleDevice.deviceId;
UniversalBle.connect(deviceId);

// Disconnect from a device
UniversalBle.disconnect(deviceId);

// Get connection/disconnection updates using stream
UniversalBle.connectionStream(deviceId).listen((bool isConnected) {
  debugPrint('OnConnectionChange $deviceId, $isConnected');
});

// Or set a handler to get updates of all devices
UniversalBle.onConnectionChange = (String deviceId, bool isConnected, String? error) {
  debugPrint('OnConnectionChange $deviceId, $isConnected Error: $error');
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
UniversalBle.read(deviceId, serviceId, characteristicId);

// Write data to a characteristic
UniversalBle.write(deviceId, serviceId, characteristicId, value);

// Subscribe to a characteristic notifications
UniversalBle.subscribeNotifications(deviceId, serviceId, characteristicId);

// Subscribe to a characteristic indications
UniversalBle.subscribeIndications(deviceId, serviceId, characteristicId);

// Get characteristic notifications/indications updates using stream
UniversalBle.characteristicValueStream(deviceId, characteristicId).listen((Uint8List value) {
  debugPrint('OnValueChange $deviceId, $characteristicId, ${hex.encode(value)}');
});

// Or set a handler to get updates of all characteristics
UniversalBle.onValueChange = (String deviceId, String characteristicId, Uint8List value) {
  debugPrint('onValueChange $deviceId, $characteristicId, ${hex.encode(value)}');
}

// Unsubscribe from notifications/indications
UniversalBle.unsubscribe(deviceId, serviceId, characteristicId);
```

### Pairing

#### Trigger pairing

##### Pair on Android, Windows, Linux

```dart
await UniversalBle.pair(deviceId);
```

##### Pair on Apple and web

For Apple and Web, pairing support depends on the device. Pairing is triggered automatically by the OS when you try to read/write from/to an encrypted characteristic.

Calling `UniversalBle.pair(deviceId)` will only trigger pairing if the device has an _encrypted read characteristic_.

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
UniversalBle.pairingStateStream(deviceId).listen((bool paired) {
  // Handle pairing state change
});

// Or set a handler to get pairing state updates of all devices
UniversalBle.onPairingStateChange = (String deviceId, bool paired) {}
```

#### Unpair

```dart
UniversalBle.unpair(deviceId);
```

### Request MTU

This method will **attempt** to set the MTU (Maximum Transmission Unit) but it is not guaranteed to succeed due to platform limitations. It will always return the current MTU.

```dart
int mtu = await UniversalBle.requestMtu(widget.deviceId, 247);
```
