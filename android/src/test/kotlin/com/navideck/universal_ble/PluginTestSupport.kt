package com.navideck.universal_ble

import android.bluetooth.BluetoothGatt

/**
 * Shared access to [UniversalBlePlugin]'s private state for unit tests. Kept in
 * one place so a renamed field breaks a single helper instead of every test.
 */
internal fun UniversalBlePlugin.setField(name: String, value: Any?) {
    val field = UniversalBlePlugin::class.java.getDeclaredField(name)
    field.isAccessible = true
    field.set(this, value)
}

@Suppress("UNCHECKED_CAST")
internal fun <T> UniversalBlePlugin.getField(name: String): T {
    val field = UniversalBlePlugin::class.java.getDeclaredField(name)
    field.isAccessible = true
    return field.get(this) as T
}

internal fun UniversalBlePlugin.gattRegistry(): GattRegistry = getField("gattRegistry")

@Suppress("UNCHECKED_CAST")
internal fun UniversalBlePlugin.connectedGatts(): MutableSet<BluetoothGatt> =
    getField("connectedGatts")

@Suppress("UNCHECKED_CAST")
internal fun UniversalBlePlugin.awaitingReconnectGatts(): MutableSet<BluetoothGatt> =
    getField("awaitingReconnectGatts")

@Suppress("UNCHECKED_CAST")
internal fun UniversalBlePlugin.autoConnectDevices(): MutableSet<String> =
    getField("autoConnectDevices")

/**
 * Registers [gatt] as the plugin's client and marks its link up, as a
 * `STATE_CONNECTED` callback does. Requests submitted through the public API
 * require both: without a live link they are refused with `deviceDisconnected`
 * instead of reaching the stack (#394).
 */
internal fun UniversalBlePlugin.attachConnectedGatt(gatt: BluetoothGatt) {
    gattRegistry().put(gatt)
    connectedGatts().add(gatt)
}
