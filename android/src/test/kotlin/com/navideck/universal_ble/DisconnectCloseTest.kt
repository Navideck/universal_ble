package com.navideck.universal_ble

import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.os.Handler
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertSame
import kotlin.test.assertTrue
import org.mockito.ArgumentMatchers.any
import org.mockito.Mockito

/*
 * disconnect() keeps the GATT client registered until STATE_DISCONNECTED
 * arrives (or the fallback timer fires). A connect() issued in the meantime
 * registers a new client for the same address; the old one must then close
 * without failing the new client's operations, evicting it from the cache or
 * reporting a disconnect the new client would take for its own.
 */
internal class DisconnectCloseTest {
    private val deviceAddress = "AA:BB:CC:DD:EE:FF"

    // (deviceId, connected, error) of every onConnectionChanged delivered to Dart.
    private val connectionChanges = mutableListOf<List<Any?>>()
    private val callbackChannel: UniversalBleCallbackChannel =
        Mockito.mock(UniversalBleCallbackChannel::class.java) { invocation ->
            if (invocation.method.name == "onConnectionChanged") {
                connectionChanges.add(invocation.arguments.take(3))
            }
            null
        }

    @AfterTest
    fun clearCache() {
        deviceAddress.findGatt()?.removeCache()
    }

    private fun plugin(): UniversalBlePlugin {
        val plugin = UniversalBlePlugin()
        // Callbacks are posted to the main looper; run them inline.
        val handler = Mockito.mock(Handler::class.java)
        Mockito.doAnswer { invocation ->
            invocation.getArgument<Runnable>(0).run()
            true
        }.`when`(handler).post(any())
        setField(plugin, "mainThreadHandler", handler)
        setField(plugin, "callbackChannel", callbackChannel)
        return plugin
    }

    private fun setField(plugin: UniversalBlePlugin, name: String, value: Any) {
        val field = UniversalBlePlugin::class.java.getDeclaredField(name)
        field.isAccessible = true
        field.set(plugin, value)
    }

    @Suppress("UNCHECKED_CAST")
    private fun closingGatts(plugin: UniversalBlePlugin): MutableSet<BluetoothGatt> {
        val field = UniversalBlePlugin::class.java.getDeclaredField("closingGatts")
        field.isAccessible = true
        return field.get(plugin) as MutableSet<BluetoothGatt>
    }

    private fun mockGatt(): BluetoothGatt {
        val device = Mockito.mock(BluetoothDevice::class.java)
        Mockito.`when`(device.address).thenReturn(deviceAddress)
        val gatt = Mockito.mock(BluetoothGatt::class.java)
        Mockito.`when`(gatt.device).thenReturn(device)
        return gatt
    }

    @Test
    fun closingClientIsClosedAndReportedOnDisconnect() {
        val plugin = plugin()
        val gatt = mockGatt()
        closingGatts(plugin).add(gatt)

        plugin.onConnectionStateChange(
            gatt, BluetoothGatt.GATT_SUCCESS, BluetoothGatt.STATE_DISCONNECTED
        )

        Mockito.verify(gatt).close()
        assertEquals(listOf(listOf<Any?>(deviceAddress, false, null)), connectionChanges)
        assertTrue(closingGatts(plugin).isEmpty())
    }

    @Test
    fun supersededClientClosesWithoutTouchingTheNewOne() {
        val plugin = plugin()
        val oldGatt = mockGatt()
        val newGatt = mockGatt()
        closingGatts(plugin).add(oldGatt)
        newGatt.saveCacheIfNeeded()

        plugin.onConnectionStateChange(
            oldGatt, BluetoothGatt.GATT_SUCCESS, BluetoothGatt.STATE_DISCONNECTED
        )

        Mockito.verify(oldGatt).close()
        assertTrue(connectionChanges.isEmpty())
        assertSame(newGatt, deviceAddress.findGatt())
    }
}
