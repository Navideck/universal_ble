package com.navideck.universal_ble

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.os.Handler
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue
import org.mockito.ArgumentMatchers.any
import org.mockito.Mockito

/*
 * Each FlutterEngine gets its own UniversalBlePlugin, so GATT clients must be owned
 * per instance: a background engine's client must not be visible to the UI engine,
 * or connect() would short-circuit onto a client whose callbacks are wired to an
 * engine that no longer exists (#309).
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
        plugin.setField("mainThreadHandler", handler)
        plugin.setField("bluetoothManager", bluetoothManager())
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

    private fun mockGatt(): BluetoothGatt {
        val device = Mockito.mock(BluetoothDevice::class.java)
        Mockito.`when`(device.address).thenReturn(address)
        val gatt = Mockito.mock(BluetoothGatt::class.java)
        Mockito.`when`(gatt.device).thenReturn(device)
        return gatt
    }

    @Test
    fun aClientRegisteredInOneRegistryIsUnknownToAnother() {
        val background = GattRegistry()
        val ui = GattRegistry()
        val gatt = mockGatt()
        background.put(gatt)

        assertTrue(background.isKnown(address))
        assertSame(gatt, background.find(address))
        assertFalse(ui.isKnown(address))
        assertNull(ui.find(address))
    }

    @Test
    fun connectionStateIgnoresAClientOwnedByAnotherEngine() {
        val backgroundEngine = plugin()
        val uiEngine = plugin()
        backgroundEngine.gattRegistry().put(mockGatt())

        // The OS reports CONNECTED for both, but only the owning engine may
        // claim it; the other reports DISCONNECTED instead of a dead client.
        assertEquals(BleConnectionState.CONNECTED, backgroundEngine.getConnectionState(address))
        assertEquals(BleConnectionState.DISCONNECTED, uiEngine.getConnectionState(address))
    }

    @Test
    fun releasingOneRegistrysClientLeavesAnothersUntouched() {
        val first = GattRegistry()
        val second = GattRegistry()
        val firstGatt = mockGatt()
        val secondGatt = mockGatt()
        first.put(firstGatt)
        second.put(secondGatt)

        first.remove(firstGatt)

        assertNull(first.find(address))
        assertSame(secondGatt, second.find(address))
    }

    @Test
    fun removingAReplacedClientDoesNotEvictTheNewerOne() {
        val registry = GattRegistry()
        val oldGatt = mockGatt()
        val newGatt = mockGatt()
        registry.put(oldGatt)
        registry.put(newGatt)

        registry.remove(oldGatt)

        assertSame(newGatt, registry.find(address))
    }

    @Test
    fun getFailsForAnUnknownDevice() {
        val error = assertFailsWith<FlutterError> { GattRegistry().get(address) }

        assertEquals(UniversalBleErrorCode.DEVICE_NOT_FOUND.raw.toString(), error.code)
    }
}
