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

/** The plugin's tracked client for [gatt], if any. */
internal fun UniversalBlePlugin.gattClient(gatt: BluetoothGatt): GattClient? =
    gattRegistry().find(gatt)

/**
 * Registers [gatt] as the plugin's client and marks its link up, as a
 * `STATE_CONNECTED` callback does. Requests submitted through the public API
 * require both: without a live link they are refused with `deviceDisconnected`
 * instead of reaching the stack (#394).
 */
internal fun UniversalBlePlugin.attachConnectedGatt(gatt: BluetoothGatt) {
    gattRegistry().put(gatt).setState(GattClient.State.CONNECTED)
}

// The pending-operation lists, typed, so a test does not spell out a reflection
// key every time. They are the live lists, not copies.

internal fun UniversalBlePlugin.pendingReads(): MutableList<ReadResultFuture> =
    getField("readResultFutureList")

internal fun UniversalBlePlugin.pendingWrites(): MutableList<WriteResultFuture> =
    getField("writeResultFutureList")

internal fun UniversalBlePlugin.pendingDescriptorReads(): MutableList<ReadDescriptorResultFuture> =
    getField("readDescriptorResultFutureList")

internal fun UniversalBlePlugin.pendingDescriptorWrites(): MutableList<WriteDescriptorResultFuture> =
    getField("writeDescriptorResultFutureList")

internal fun UniversalBlePlugin.pendingSubscriptions(): MutableList<SubscriptionResultFuture> =
    getField("subscriptionResultFutureList")

internal fun UniversalBlePlugin.pendingMtus(): MutableList<MtuResultFuture> =
    getField("mtuResultFutureList")

internal fun UniversalBlePlugin.pendingRssis(): MutableList<RssiResultFuture> =
    getField("rssiResultFutureList")

internal fun UniversalBlePlugin.pendingDiscoveries(): MutableList<DiscoverServicesFuture> =
    getField("discoverServicesFutureList")
