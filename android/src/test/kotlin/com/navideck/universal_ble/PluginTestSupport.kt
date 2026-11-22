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

internal fun UniversalBlePlugin.pendingReads(): PendingOperations<ReadResultFuture> =
    getField("readOperations")

internal fun UniversalBlePlugin.pendingWrites(): PendingOperations<WriteResultFuture> =
    getField("writeOperations")

internal fun UniversalBlePlugin.pendingDescriptorReads(): PendingOperations<ReadDescriptorResultFuture> =
    getField("descriptorReadOperations")

internal fun UniversalBlePlugin.pendingDescriptorWrites(): PendingOperations<WriteDescriptorResultFuture> =
    getField("descriptorWriteOperations")

internal fun UniversalBlePlugin.pendingSubscriptions(): PendingOperations<SubscriptionResultFuture> =
    getField("subscriptionOperations")

internal fun UniversalBlePlugin.pendingMtus(): PendingOperations<MtuResultFuture> =
    getField("mtuOperations")

internal fun UniversalBlePlugin.pendingRssis(): PendingOperations<RssiResultFuture> =
    getField("rssiOperations")

internal fun UniversalBlePlugin.pendingDiscoveries(): PendingOperations<DiscoverServicesFuture> =
    getField("discoveryOperations")
