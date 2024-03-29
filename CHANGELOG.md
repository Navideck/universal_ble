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
