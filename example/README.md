# universal_ble_example

Demonstrates how to use the universal_ble plugin.

## iOS: deployment target and Bluetooth permission

The iOS app targets 15.0 because Xcode 26 no longer builds the 13.1 minimum
that the plugin itself supports.

The app deliberately omits the `NSAccessorySetupKitSupports`,
`NSAccessorySetupBluetoothServices` and `NSAccessorySetupBluetoothNames`
keys. On a fresh install with those keys present, iPadOS 26.6.1 did not show
the broad Bluetooth permission prompt at all, so `CBCentralManager` stayed
`poweredOff` and scanning found nothing. Without them the prompt appears and
the scan works. To try the AccessorySetupKit picker instead, add the keys
described in the plugin README's picker section to this app's `Info.plist`
and run the app again; a build with them cannot also obtain the broad
permission on a first install.
