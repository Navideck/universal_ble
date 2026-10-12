package com.navideck.universal_ble

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
