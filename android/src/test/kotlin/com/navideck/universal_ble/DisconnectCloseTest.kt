package com.navideck.universal_ble

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothManager
import android.content.Context
import android.os.Handler
import java.util.UUID
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
    private val serviceUuid = UUID.fromString("0000fff0-0000-1000-8000-00805f9b34fb")
    private val charUuid = UUID.fromString("0000fff1-0000-1000-8000-00805f9b34fb")

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

    private fun plugin(): UniversalBlePlugin =
        pluginWithInlineLooper().also { it.setField("callbackChannel", callbackChannel) }

    private fun closingGatts(plugin: UniversalBlePlugin): MutableSet<BluetoothGatt> =
        plugin.getField("closingGatts")



    @Test
    fun closingClientIsClosedAndReportedOnDisconnect() {
        val plugin = plugin()
        val gatt = mockGatt(deviceAddress)
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
        val gatt = mockGatt(deviceAddress)
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
        val gatt = mockGatt(deviceAddress)
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
    fun supersededClientConnectIsNotReported() {
        val plugin = plugin()
        val oldGatt = mockGatt(deviceAddress)
        val newGatt = mockGatt(deviceAddress)
        plugin.gattRegistry().put(newGatt)

        plugin.onConnectionStateChange(
            oldGatt, BluetoothGatt.GATT_SUCCESS, BluetoothGatt.STATE_CONNECTED
        )

        assertTrue(connectionChanges.isEmpty(), "a replaced client cannot report a connection")
    }

    @Test
    fun supersededClientClosesWithoutTouchingTheNewOne() {
        val plugin = plugin()
        val oldGatt = mockGatt(deviceAddress)
        val newGatt = mockGatt(deviceAddress)
        closingGatts(plugin).add(oldGatt)
        plugin.gattRegistry().put(newGatt)

        plugin.onConnectionStateChange(
            oldGatt, BluetoothGatt.GATT_SUCCESS, BluetoothGatt.STATE_DISCONNECTED
        )

        Mockito.verify(oldGatt).close()
        assertTrue(connectionChanges.isEmpty())
        assertSame(newGatt, plugin.gattRegistry().find(deviceAddress))
    }

    @Test
    fun connectThatReportsBeforeItIsRegisteredIsStillDelivered() {
        val plugin = plugin()
        val gatt = mockGatt(deviceAddress)
        val device = Mockito.mock(BluetoothDevice::class.java)
        Mockito.`when`(device.address).thenReturn(deviceAddress)
        // connectGatt() is given no Handler, so the stack can report CONNECTED
        // on a binder thread before connectGatt() returns — i.e. before
        // connect() has published the client it just created.
        Mockito.`when`(
            device.connectGatt(
                Mockito.any(Context::class.java),
                Mockito.anyBoolean(),
                Mockito.any(BluetoothGattCallback::class.java),
            )
        ).thenAnswer {
            plugin.onConnectionStateChange(
                gatt, BluetoothGatt.GATT_SUCCESS, BluetoothGatt.STATE_CONNECTED
            )
            gatt
        }
        val adapter = Mockito.mock(BluetoothAdapter::class.java)
        Mockito.`when`(adapter.getRemoteDevice(deviceAddress)).thenReturn(device)
        val manager = Mockito.mock(BluetoothManager::class.java)
        Mockito.`when`(manager.adapter).thenReturn(adapter)
        plugin.setField("bluetoothManager", manager)
        plugin.setField("context", Mockito.mock(Context::class.java))

        plugin.connect(deviceAddress, null, null)

        assertEquals(
            listOf(listOf<Any?>(deviceAddress, true, null, null, null)),
            connectionChanges,
            "a link that reports before it is registered still belongs to this connect()",
        )
        assertSame(gatt, plugin.gattRegistry().find(deviceAddress))
    }

    @Test
    fun connectStateFromAClientBeingClosedIsDropped() {
        val plugin = plugin()
        val gatt = mockGatt(deviceAddress)
        // disconnect() is tearing this client down; it must not come back as a
        // connection for the address.
        closingGatts(plugin).add(gatt)

        plugin.onConnectionStateChange(
            gatt, BluetoothGatt.GATT_SUCCESS, BluetoothGatt.STATE_CONNECTED
        )

        assertTrue(connectionChanges.isEmpty())
    }

    @Test
    fun replacedClientDisconnectDoesNotReportOrFailTheNewConnection() {
        val plugin = plugin()
        // connect() replaced the client, so the old one is never in closingGatts.
        val replaced = mockGatt(deviceAddress)
        val current = mockGatt(deviceAddress)
        plugin.gattRegistry().put(current)
        val reads = mutableListOf<Result<ByteArray>>()
        plugin.pendingReads().add(
            ReadResultFuture(current, deviceAddress, charUuid.toString(), serviceUuid.toString()) {
                reads.add(it)
            }
        )

        plugin.onConnectionStateChange(
            replaced, BluetoothGatt.GATT_SUCCESS, BluetoothGatt.STATE_DISCONNECTED
        )

        assertTrue(
            connectionChanges.isEmpty(),
            "the replaced client's disconnect is not the current connection's"
        )
        assertTrue(reads.isEmpty(), "the current connection's read is still in flight")
        assertEquals(
            1,
            plugin.pendingReads().size
        )
        Mockito.verify(replaced).close()
    }
}
