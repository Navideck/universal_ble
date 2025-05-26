# Advanced Usage

## BleDevice Extensions

The `BleDeviceExtension` provides a set of extension methods that enhance the functionality of the `BleDevice` class, simplifying common BLE operations.

Get `BleDevice` from ScanResults

```dart
UniversalBle.scanStream.listen((BleDevice bleDevice) {
  // Get the bleDevice object
});
```

### `Connection Stream`

```dart
device.connectionStream.listen((isConnected) {
  print('Device is connected: $isConnected');
});
```

### `IsConnected`

```dart
bool connected = await device.isConnected;
print('Device is connected: $connected');
```

### `Connect`

Connects to the BLE device. This method initiates a connection to the Bluetooth device.

```dart
await device.connect();
print('Device connected');
```

### `Disconnect`

Disconnects from the BLE device. This method terminates the connection to the Bluetooth device.

```dart
await device.disconnect();
print('Device disconnected');
```

### `RequestMtu`

Requests a specific MTU (Maximum Transmission Unit) size for the connection. Returns a `Future<int>` with the negotiated MTU size.

- `expectedMtu`: The desired MTU size.

```dart
int mtu = await device.requestMtu(256);
print('MTU size: $mtu');
```

### `DiscoverServices`

Discovers the services offered by the device. Returns a `Future<List<BleService>>`.

- `cached`: If `true` (default), cached services are returned if available. The cache is reset on disconnect. If `false`, fresh services are always discovered.

```dart
List<BleService> services = await device.discoverServices();
for (var service in services) {
  print('Service UUID: ${service.uuid}');
}
```

### `GetService`

Retrieves a specific service. Returns a `Future<BleService>`.

- `service`: The UUID of the service.
- `cached`: If `true` (default), cached services are used.

```dart
BleService service = await device.getService('180a');
```

### `GetCharacteristic`

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

## BleCharacteristic Extensions

The `BleCharacteristicExtension` provides a set of extension methods that enhance the functionality of the `BleCharacteristic` class, simplifying common characteristic operations.

Get `BleCharacteristic` using `bleDevice.getCharacteristic`

### `OnValueReceived`

A stream of `Uint8List` that emits values received from the characteristic. Listen to this stream to receive updates whenever the characteristic's value changes.

```dart
characteristic.onValueReceived.listen((value) {
  print('Received value: ${value.toString()}');
});
```

### `DisableNotify`

Disables notifications for this characteristic.

```dart
await characteristic.disableNotify();
print('Notifications disabled');
```

### `SetNotify`

Enables notifications for this characteristic. Throws an exception if the characteristic does not support notifications.

```dart
await characteristic.setNotify();
```

### `SetIndication`

Enables indications for this characteristic. Throws an exception if the characteristic does not support indications.

```dart
await characteristic.setIndication();
```

### `Read`

Reads the current value of the characteristic. Returns a `Future<Uint8List>`.

```dart
Uint8List value = await characteristic.read();
print('Value: ${value.toString()}');
```

### `Write`

Writes a value to the characteristic.

- `value`: The list of bytes to write.
- `withoutResponse`: If `true`, the write is performed without a response from the peripheral.

```dart
await characteristic.write([0x01, 0x02, 0x03]);
print('Value written');

await characteristic.write([0x01, 0x02, 0x03], withoutResponse: true);
print('Value written without response');
```
