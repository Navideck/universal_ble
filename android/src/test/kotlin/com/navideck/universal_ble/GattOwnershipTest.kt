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

    private fun plugin(): UniversalBlePlugin =
        pluginWithInlineLooper().also { it.setField("bluetoothManager", bluetoothManager()) }

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



    @Test
    fun aClientRegisteredInOneRegistryIsUnknownToAnother() {
        val background = GattRegistry()
        val ui = GattRegistry()
        val gatt = mockGatt(address)
        background.put(gatt)

        assertTrue(background.isKnown(address))
        assertSame(gatt, background.find(address)?.gatt)
        assertFalse(ui.isKnown(address))
        assertNull(ui.find(address))
    }

    @Test
    fun connectionStateIgnoresAClientOwnedByAnotherEngine() {
        val backgroundEngine = plugin()
        val uiEngine = plugin()
        backgroundEngine.gattRegistry().put(mockGatt(address))

        // The OS reports CONNECTED for both, but only the owning engine may
        // claim it; the other reports DISCONNECTED instead of a dead client.
        assertEquals(BleConnectionState.CONNECTED, backgroundEngine.getConnectionState(address))
        assertEquals(BleConnectionState.DISCONNECTED, uiEngine.getConnectionState(address))
    }

    @Test
    fun releasingOneRegistrysClientLeavesAnothersUntouched() {
        val first = GattRegistry()
        val second = GattRegistry()
        val firstGatt = mockGatt(address)
        val secondGatt = mockGatt(address)
        first.put(firstGatt)
        second.put(secondGatt)

        first.finishClose(first.find(firstGatt)!!)

        assertNull(first.find(address))
        assertSame(secondGatt, second.find(address)?.gatt)
    }

    @Test
    fun removingAReplacedClientDoesNotEvictTheNewerOne() {
        val registry = GattRegistry()
        val oldGatt = mockGatt(address)
        val newGatt = mockGatt(address)
        registry.put(oldGatt)
        registry.put(newGatt)

        registry.finishClose(registry.find(oldGatt)!!)

        assertSame(newGatt, registry.find(address)?.gatt)
    }

    @Test
    fun getFailsForAnUnknownDevice() {
        val error = assertFailsWith<FlutterError> { GattRegistry().get(address) }

        assertEquals(UniversalBleErrorCode.DEVICE_NOT_FOUND.raw.toString(), error.code)
    }
}
