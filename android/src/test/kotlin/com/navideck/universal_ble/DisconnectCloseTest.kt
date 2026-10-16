package com.navideck.universal_ble

import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.os.Handler
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertSame
import kotlin.test.assertTrue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
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

    // Callbacks are delivered through `Dispatchers.Main`; the JVM test dispatcher
    // stands in for Android's main looper.
    @BeforeTest
    fun setUpMainDispatcher() {
        Dispatchers.setMain(Dispatchers.Unconfined)
    }

    @AfterTest
    fun tearDownMainDispatcher() {
        Dispatchers.resetMain()
    }

    // (deviceId, connected, error, errorCode, nativeErrorCode) of every onConnectionChanged
    // delivered to Dart.
    private val connectionChanges = mutableListOf<List<Any?>>()
    private val callbackChannel: UniversalBleCallbackChannel =
        Mockito.mock(UniversalBleCallbackChannel::class.java) { invocation ->
            if (invocation.method.name == "onConnectionChanged") {
                connectionChanges.add(invocation.arguments.take(5))
            }
            null
        }

    private fun plugin(): UniversalBlePlugin {
        val plugin = UniversalBlePlugin()
        // Callbacks are posted to the main looper; run them inline.
        val handler = Mockito.mock(Handler::class.java)
        Mockito.doAnswer { invocation ->
            invocation.getArgument<Runnable>(0).run()
            true
        }.`when`(handler).post(any())
        plugin.setField("mainThreadHandler", handler)
        plugin.setField("callbackChannel", callbackChannel)
        return plugin
    }

    private fun closingGatts(plugin: UniversalBlePlugin): MutableSet<BluetoothGatt> =
        plugin.getField("closingGatts")

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
        assertEquals(listOf(listOf<Any?>(deviceAddress, false, null, null, null)), connectionChanges)
        assertTrue(closingGatts(plugin).isEmpty())
    }

    @Test
    fun peerDisconnectAfterConnectReportsDeviceDisconnected() {
        val plugin = plugin()
        val gatt = mockGatt()
        plugin.gattRegistry().put(gatt)

        plugin.onConnectionStateChange(
            gatt, BluetoothGatt.GATT_SUCCESS, BluetoothGatt.STATE_CONNECTED
        )
        plugin.onConnectionStateChange(
            gatt, BluetoothGatt.GATT_FAILURE, BluetoothGatt.STATE_DISCONNECTED
        )

        assertEquals(
            listOf(
                listOf<Any?>(deviceAddress, true, null, null, null),
                listOf<Any?>(
                    deviceAddress,
                    false,
                    "Unknown Error 257",
                    UniversalBleErrorCode.DEVICE_DISCONNECTED,
                    257L,
                ),
            ),
            connectionChanges,
        )
    }

    @Test
    fun disconnectBeforeConnectReportsConnectionFailed() {
        val plugin = plugin()
        val gatt = mockGatt()
        plugin.gattRegistry().put(gatt)

        plugin.onConnectionStateChange(
            gatt, BluetoothGatt.GATT_FAILURE, BluetoothGatt.STATE_DISCONNECTED
        )

        assertEquals(
            listOf(
                listOf<Any?>(
                    deviceAddress,
                    false,
                    "Unknown Error 257",
                    UniversalBleErrorCode.CONNECTION_FAILED,
                    257L,
                )
            ),
            connectionChanges,
        )
    }

    @Test
    fun supersededClientClosesWithoutTouchingTheNewOne() {
        val plugin = plugin()
        val oldGatt = mockGatt()
        val newGatt = mockGatt()
        closingGatts(plugin).add(oldGatt)
        plugin.gattRegistry().put(newGatt)

        plugin.onConnectionStateChange(
            oldGatt, BluetoothGatt.GATT_SUCCESS, BluetoothGatt.STATE_DISCONNECTED
        )

        Mockito.verify(oldGatt).close()
        assertTrue(connectionChanges.isEmpty())
        assertSame(newGatt, plugin.gattRegistry().find(deviceAddress))
    }
}
