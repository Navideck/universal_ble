package com.navideck.universal_ble

import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.os.Handler
import java.util.concurrent.ConcurrentLinkedQueue
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.mockito.Mockito

internal class MtuCompletionTest {
    private val address = "AA:BB:CC:DD:EE:FF"
    private val posted = ConcurrentLinkedQueue<Runnable>()
    private val plugin = UniversalBlePlugin().also {
        val handler = Mockito.mock(Handler::class.java)
        Mockito.doAnswer { call ->
            posted.add(call.getArgument<Runnable>(0))
            true
        }.`when`(handler).post(Mockito.any())
        val field = UniversalBlePlugin::class.java.getDeclaredField("mainThreadHandler")
        field.isAccessible = true
        field.set(it, handler)
    }

    private fun gatt(id: String = address): BluetoothGatt {
        val device = Mockito.mock(BluetoothDevice::class.java)
        Mockito.`when`(device.address).thenReturn(id)
        return Mockito.mock(BluetoothGatt::class.java).also {
            Mockito.`when`(it.device).thenReturn(device)
            Mockito.`when`(it.requestMtu(Mockito.anyInt())).thenReturn(true)
            it.saveCacheIfNeeded()
        }
    }

    private fun drainMain() {
        while (true) (posted.poll() ?: return).run()
    }

    @AfterTest
    fun clearConnections() {
        connectedGatts().forEach { it.removeCache() }
    }

    @Test
    fun binderReplyIsDeliveredOnMainThreadExactlyOnce() {
        val gatt = gatt()
        val values = mutableListOf<Result<Long>>()
        plugin.requestMtu(address, 247L) { values.add(it) }
        Thread { plugin.onMtuChanged(gatt, 247, BluetoothGatt.GATT_SUCCESS) }.apply { start(); join() }
        assertTrue(values.isEmpty(), "MTU replies should use the main-looper delivery shared by other BLE completions")
        drainMain()
        assertEquals(247L, values.single().getOrThrow())
        plugin.onMtuChanged(gatt, 247, BluetoothGatt.GATT_SUCCESS)
        drainMain()
        assertEquals(1, values.size)
    }

    @Test
    fun waiterIsRegisteredBeforeStartingTheNativeRequest() {
        val gatt = gatt()
        Mockito.doAnswer {
            plugin.onMtuChanged(gatt, 247, BluetoothGatt.GATT_SUCCESS)
            true
        }.`when`(gatt).requestMtu(247)
        val values = mutableListOf<Result<Long>>()
        plugin.requestMtu(address, 247L) { values.add(it) }
        drainMain()
        assertEquals(247L, values.single().getOrThrow())
    }

    @Test
    fun peerNegotiatedMtuIsReusedWithoutAnotherNativeRequest() {
        val gatt = gatt()
        plugin.onMtuChanged(gatt, 247, BluetoothGatt.GATT_SUCCESS)
        val values = mutableListOf<Result<Long>>()
        plugin.requestMtu(address, 247L) { values.add(it) }
        drainMain()
        assertEquals(247L, values.single().getOrThrow())
        Mockito.verify(gatt, Mockito.never()).requestMtu(Mockito.anyInt())
    }

    @Test
    fun insufficientNegotiatedMtuIsReportedWithoutInventingTheRequestedSize() {
        val gatt = gatt()
        val values = mutableListOf<Result<Long>>()
        plugin.requestMtu(address, 247L) { values.add(it) }
        plugin.onMtuChanged(gatt, 23, BluetoothGatt.GATT_SUCCESS)
        drainMain()
        assertEquals(23L, values.single().getOrThrow())
    }

    @Test
    fun onlyAndroid14AndLaterReuseAnInsufficientObservedMtu() {
        assertTrue(canReuseNegotiatedMtu(23, 247, 34))
        assertTrue(canReuseNegotiatedMtu(23, 247, 37))
        assertFalse(canReuseNegotiatedMtu(23, 247, 33))
        assertTrue(canReuseNegotiatedMtu(247, 247, 21))
    }

    @Test
    fun olderAndroidCanRequestAnIncreaseAfterAnEarlierNegotiation() {
        // The local Android test stub reports SDK_INT=0 (the pre-14 path).
        val gatt = gatt()
        plugin.onMtuChanged(gatt, 23, BluetoothGatt.GATT_SUCCESS)
        val values = mutableListOf<Result<Long>>()
        plugin.requestMtu(address, 247L) { values.add(it) }
        drainMain()
        assertTrue(values.isEmpty())
        Mockito.verify(gatt).requestMtu(247)
        plugin.onMtuChanged(gatt, 247, BluetoothGatt.GATT_SUCCESS)
        drainMain()
        assertEquals(247L, values.single().getOrThrow())
    }

    @Test
    fun rejectedNativeRequestFailsImmediatelyAndCanBeRetried() {
        val gatt = gatt()
        Mockito.`when`(gatt.requestMtu(247)).thenReturn(false, true)
        val values = mutableListOf<Result<Long>>()
        plugin.requestMtu(address, 247L) { values.add(it) }
        drainMain()
        assertTrue(values.single().isFailure)
        plugin.requestMtu(address, 247L) { values.add(it) }
        plugin.onMtuChanged(gatt, 247, BluetoothGatt.GATT_SUCCESS)
        drainMain()
        assertEquals(2, values.size)
        assertEquals(247L, values.last().getOrThrow())
    }

    @Test
    fun simultaneousRequestsShareOneNegotiation() {
        val gatt = gatt()
        val values = mutableListOf<Result<Long>>()
        plugin.requestMtu(address, 247L) { values.add(it) }
        plugin.requestMtu(address, 517L) { values.add(it) }
        plugin.onMtuChanged(gatt, 247, BluetoothGatt.GATT_SUCCESS)
        drainMain()
        assertEquals(listOf(247L, 247L), values.map { it.getOrThrow() })
        Mockito.verify(gatt, Mockito.times(1)).requestMtu(Mockito.anyInt())
    }

    @Test
    fun oldGattCallbackCannotCompleteOrPopulateTheReconnectedGatt() {
        val old = gatt()
        plugin.onMtuChanged(old, 247, BluetoothGatt.GATT_SUCCESS)
        plugin.disconnect(address)
        drainMain()
        val current = gatt()
        val values = mutableListOf<Result<Long>>()
        plugin.requestMtu(address, 247L) { values.add(it) }
        plugin.onMtuChanged(old, 247, BluetoothGatt.GATT_SUCCESS)
        drainMain()
        assertTrue(values.isEmpty())
        plugin.onMtuChanged(current, 185, BluetoothGatt.GATT_SUCCESS)
        drainMain()
        assertEquals(185L, values.single().getOrThrow())
        Mockito.verify(current).requestMtu(247)
    }

    @Test
    fun disconnectFailsPendingMtuAndLateSuccessCannotAcknowledgeIt() {
        val gatt = gatt()
        val values = mutableListOf<Result<Long>>()
        plugin.requestMtu(address, 247L) { values.add(it) }
        plugin.disconnect(address)
        plugin.onMtuChanged(gatt, 247, BluetoothGatt.GATT_SUCCESS)
        drainMain()
        assertTrue(values.single().isFailure)
    }

    @Test
    fun failedMtuStatusDoesNotBecomeACachedValue() {
        val gatt = gatt()
        val values = mutableListOf<Result<Long>>()
        plugin.requestMtu(address, 247L) { values.add(it) }
        plugin.onMtuChanged(gatt, 247, BluetoothGatt.GATT_FAILURE)
        drainMain()
        assertTrue(values.single().isFailure)
        plugin.requestMtu(address, 247L) { values.add(it) }
        plugin.onMtuChanged(gatt, 185, BluetoothGatt.GATT_SUCCESS)
        drainMain()
        assertEquals(185L, values.last().getOrThrow())
        Mockito.verify(gatt, Mockito.times(2)).requestMtu(247)
    }
}
