// Device ids are lower-case throughout the Dart layer (see UniversalBlePlatform /
// UniversalBlePeripheralPlatform), but some native sides want the upper-case form —
// Android's BluetoothAdapter.getRemoteDevice REQUIRES upper case, and Apple's peripheral
// cache and Linux's BlueZ address are upper-case too. Windows formats MACs lower-case but
// parses and compares them case-insensitively, so upper-case is safe there as well.
// Convert here, at the pigeon boundary.
String nativeDeviceId(String deviceId) => deviceId.toUpperCase();
