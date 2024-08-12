## 0.12.0
* BREAKING CHANGE: `unPair` is now `unpair`
* Add `pair()` support for Apple and web
* Add `isPaired` support for Apple and web
* `pair()` now returns the pairing result
* `connect` will now return the connection result
* Add `PlatformConfig` property in `StartScan`
* Add `WebConfig` property in `PlatformConfig`
* Fix notifications for characteristics without cccd on Android
* Add `connectionStream` API to get connection updates as stream

## 0.11.1
* Trim spaces in UUIDs
* Receive advertisement events on web
* Improve cleanup after disconnection on web

## 0.11.0
* Unify UUID format across all platforms, 128-bit lowercase
* Add BleUuidParser utility methods for UUID parsing

## 0.10.1
* Improve Android error handling
* Fix Android disconnection events sometimes missed
* Improve cleanup after disconnection on Apple and Android
* Support pairing on Apple
* Improve code level documentation

## 0.10.0
* BREAKING CHANGE: `ScanResult` is now `BleDevice`
* BREAKING CHANGE: `getConnectedDevices` is now `getSystemDevices`
* BREAKING CHANGE: `isPaired` is now nullable
* BREAKING CHANGE: `onValueChanged` is now `onValueChange`
* BREAKING CHANGE: `onConnectionChanged` is now `onConnectionChange`
* Add `connectionState` property to BleDevice
* Add `isSystemDevice` property to BleDevice
* Add `.perDevice` queue
* Support "ProvidePin" pairing on Windows 10/11
* Get RRSI updates on Apple platforms
* Improve enum parsing performance
* Improve code level documentation

## 0.9.11
* Add device name prefix filtering

## 0.9.10
* Fix Windows scan filter
* Remove scan result caching on Windows
* Improve service discovery on Linux
* Use asynchronous callbacks for SetNotifiable
* Remove dependency on `convert`
* Remove dependency on `collection`
* Update Android example app Gradle

## 0.9.9
* Improve service discovery on Apple
* Improve reconnection on Apple
* Persist long scan result name on Windows
* Fix Android serviceUuids in scanResults
* Example app improvements

## 0.9.8
* Improve manufacturer data discovery on Windows
* Example app improvements

## 0.9.7
* Fix characteristic keying on linux allowing receiving data from multiple BLE devices at the same time

## 0.9.6
* Fix a Windows issue where characteristics of certain services would not be discovered
* Improve readme

## 0.9.5
* Windows support has graduated from beta to stable
* Support filtering by manufacturer data
* Unify web's optionalServices API with filtering API
* Implement requestMtu in Linux 
* Fix wrong manufacturer data in Windows release builds
* Improve logging

## 0.9.4
* Fix Windows crash when no Bluetooth adapter is present

## 0.9.3
* Add scan filter (withServices:) in `startScan()`
* Add service UUIDs from advertisements in `BleScanResult`
* Fix Windows release build compilation

## 0.9.2
* Add command queue
* Improve error handling on Android, iOS, macOS, Windows, Linux and web

## 0.9.1
* Improve logging

## 0.9.0
* Improve windows device name discovery
* Improve linux implementation
* Improve titles in example app

## 0.8.4
* Add `WebRequestOptionsBuilder.defaultServices` for convenience when setting `optionalServices` when scanning on web
* Add "try online" URL in readme
* Improve readme
* Improve example app

## 0.8.3
* Rename onPairStateChange *> onPairingStateChange
* Improve readme

## 0.8.2
* Improve readme

## 0.8.1
* Update supported platforms

## 0.8.0
* Initial release
