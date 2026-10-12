package com.navideck.universal_ble

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.os.Handler
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue
import org.mockito.ArgumentMatchers.any
import org.mockito.Mockito

/*
 * Each FlutterEngine gets its own UniversalBlePlugin, so GATT client ownership
 * must be per instance. A background engine's client must not be visible to the
 * UI engine: a stale cache hit would make connect() short-circuit onto a client
 * whose callbacks are wired to an engine that no longer exists (#309).
 */
internal class GattOwnershipTest {
    private val address = "AA:BB:CC:DD:EE:FF"

    private fun plugin(): UniversalBlePlugin {
        val plugin = UniversalBlePlugin()
        // Callbacks are posted to the main looper; run them inline.
        val handler = Mockito.mock(Handler::class.java)
        Mockito.doAnswer { invocation ->
            invocation.getArgument<Runnable>(0).run()
            true
        }.`when`(handler).post(any())
        setField(plugin, "mainThreadHandler", handler)
        setField(plugin, "bluetoothManager", bluetoothManager())
        return plugin
    }

    // Reports the device as connected at the OS level (as if another engine had
    // opened the link), which is exactly when the stale cache used to win.
    private fun bluetoothManager(): BluetoothManager {
        val device = Mockito.mock(BluetoothDevice::class.java)
        val adapter = Mockito.mock(BluetoothAdapter::class.java)
        Mockito.`when`(adapter.getRemoteDevice(address)).thenReturn(device)
        val manager = Mockito.mock(BluetoothManager::class.java)
        Mockito.`when`(manager.adapter).thenReturn(adapter)
        Mockito.`when`(manager.getConnectionState(device, BluetoothProfile.GATT))
            .thenReturn(BluetoothGatt.STATE_CONNECTED)
        return manager
    }

    private fun setField(plugin: UniversalBlePlugin, name: String, value: Any) {
        val field = UniversalBlePlugin::class.java.getDeclaredField(name)
        field.isAccessible = true
        field.set(plugin, value)
    }

    private fun mockGatt(): BluetoothGatt {
        val device = Mockito.mock(BluetoothDevice::class.java)
        Mockito.`when`(device.address).thenReturn(address)
        val gatt = Mockito.mock(BluetoothGatt::class.java)
        Mockito.`when`(gatt.device).thenReturn(device)
        return gatt
    }

    @Test
    fun anotherEnginesClientIsNotKnownToThisEngine() {
        val backgroundEngine = plugin()
        val uiEngine = plugin()
        val gatt = mockGatt()
        with(backgroundEngine) { gatt.saveCacheIfNeeded() }

        with(backgroundEngine) {
            assertTrue(address.isKnownGatt())
            assertSame(gatt, address.findGatt())
        }
        with(uiEngine) {
            assertFalse(address.isKnownGatt())
            assertNull(address.findGatt())
        }
    }

    @Test
    fun connectionStateIgnoresAClientOwnedByAnotherEngine() {
        val backgroundEngine = plugin()
        val uiEngine = plugin()
        val gatt = mockGatt()
        with(backgroundEngine) { gatt.saveCacheIfNeeded() }

        // The OS reports CONNECTED for both, but only the owning engine may
        // claim it; the other reports DISCONNECTED instead of a dead client.
        assertEquals(BleConnectionState.CONNECTED, backgroundEngine.getConnectionState(address))
        assertEquals(BleConnectionState.DISCONNECTED, uiEngine.getConnectionState(address))
    }

    @Test
    fun releasingOneEnginesClientsLeavesAnotherEnginesUntouched() {
        val firstEngine = plugin()
        val secondEngine = plugin()
        val firstGatt = mockGatt()
        val secondGatt = mockGatt()
        with(firstEngine) { firstGatt.saveCacheIfNeeded() }
        with(secondEngine) { secondGatt.saveCacheIfNeeded() }

        with(firstEngine) { firstGatt.removeCache() }

        assertNull(firstEngine.knownGatts[address])
        assertSame(secondGatt, secondEngine.knownGatts[address])
    }
}
