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
import kotlin.test.assertNull
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

    @Test
    fun closingClientIsClosedAndReportedOnDisconnect() {
        val plugin = plugin()
        val gatt = mockGatt(deviceAddress)
        plugin.gattRegistry().beginClose(plugin.gattRegistry().put(gatt))

        plugin.onConnectionStateChange(
            gatt, BluetoothGatt.GATT_SUCCESS, BluetoothGatt.STATE_DISCONNECTED
        )

        Mockito.verify(gatt).close()
        assertEquals(listOf(listOf<Any?>(deviceAddress, false, null, null, null)), connectionChanges)
        assertNull(plugin.gattRegistry().find(gatt))
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
    fun explicitDisconnectAfterConnectReportsDeviceDisconnected() {
        val plugin = plugin()
        val gatt = mockGatt(deviceAddress)
        plugin.gattRegistry().put(gatt)
        plugin.onConnectionStateChange(
            gatt, BluetoothGatt.GATT_SUCCESS, BluetoothGatt.STATE_CONNECTED
        )

        // disconnect() moves the client to CLOSING before the stack answers, and
        // a locally initiated teardown can still carry a non-zero status. The
        // report belongs to a link that was up, so it keeps its specific code.
        plugin.disconnect(deviceAddress)
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
    fun connectClosesTheClientItReplaces() {
        val plugin = plugin()
        val previous = mockGatt(deviceAddress)
        val replacement = mockGatt(deviceAddress)
        // A link loss left this client open for autoConnect to reconnect it: it
        // is no longer connected, and nothing will ever report on it again.
        plugin.gattRegistry().put(previous, autoConnect = true)

        val device = Mockito.mock(BluetoothDevice::class.java)
        Mockito.`when`(device.address).thenReturn(deviceAddress)
        Mockito.`when`(
            device.connectGatt(
                Mockito.any(Context::class.java),
                Mockito.anyBoolean(),
                Mockito.any(BluetoothGattCallback::class.java),
            )
        ).thenReturn(replacement)
        val adapter = Mockito.mock(BluetoothAdapter::class.java)
        Mockito.`when`(adapter.getRemoteDevice(deviceAddress)).thenReturn(device)
        val manager = Mockito.mock(BluetoothManager::class.java)
        Mockito.`when`(manager.adapter).thenReturn(adapter)
        plugin.setField("bluetoothManager", manager)
        plugin.setField("context", Mockito.mock(Context::class.java))

        plugin.connect(deviceAddress, null, null)

        assertSame(replacement, plugin.gattRegistry().find(deviceAddress)?.gatt)
        Mockito.verify(previous).disconnect()
        plugin.onConnectionStateChange(
            previous, BluetoothGatt.GATT_SUCCESS, BluetoothGatt.STATE_DISCONNECTED
        )
        Mockito.verify(previous).close()
        assertNull(plugin.gattRegistry().find(previous), "the replaced client is released")
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
        plugin.gattRegistry().beginClose(plugin.gattRegistry().put(oldGatt))
        plugin.gattRegistry().put(newGatt)

        plugin.onConnectionStateChange(
            oldGatt, BluetoothGatt.GATT_SUCCESS, BluetoothGatt.STATE_DISCONNECTED
        )

        Mockito.verify(oldGatt).close()
        assertTrue(connectionChanges.isEmpty())
        assertSame(newGatt, plugin.gattRegistry().find(deviceAddress)?.gatt)
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
        assertSame(gatt, plugin.gattRegistry().find(deviceAddress)?.gatt)
    }

    @Test
    fun connectStateFromAClientBeingClosedIsDropped() {
        val plugin = plugin()
        val gatt = mockGatt(deviceAddress)
        // disconnect() is tearing this client down; it must not come back as a
        // connection for the address.
        plugin.gattRegistry().beginClose(plugin.gattRegistry().put(gatt))

        plugin.onConnectionStateChange(
            gatt, BluetoothGatt.GATT_SUCCESS, BluetoothGatt.STATE_CONNECTED
        )

        assertTrue(connectionChanges.isEmpty())
    }

    @Test
    fun replacedClientDisconnectDoesNotReportOrFailTheNewConnection() {
        val plugin = plugin()
        // connect() replaced the client, so the old one is never tracked as closing.
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
