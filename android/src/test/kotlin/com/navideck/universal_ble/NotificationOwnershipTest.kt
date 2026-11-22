package com.navideck.universal_ble

import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattService
import android.os.Handler
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.mockito.Mockito

/*
 * A notification carries no pending request to match against, so delivery is a
 * policy question: only the client registered for the address owns the
 * connection the app sees. A client replaced by a newer connect() can keep
 * reporting during its teardown, and those values must not be presented as the
 * current connection's (#381).
 */
internal class NotificationOwnershipTest {
    private val address = "AA:BB:CC:DD:EE:FF"
    private val charUuid = UUID.fromString("0000fff1-0000-1000-8000-00805f9b34fb")
    private val serviceUuid = UUID.fromString("0000fff0-0000-1000-8000-00805f9b34fb")

    /** Runnables the plugin posted to the main looper, in submission order. */
    private val mainLooper = mutableListOf<Runnable>()

    // (deviceId, characteristicId, serviceId) of every onValueChanged delivered
    // to Dart.
    private val delivered = mutableListOf<Triple<String, String, String?>>()

    private val callbackChannel: UniversalBleCallbackChannel =
        Mockito.mock(UniversalBleCallbackChannel::class.java) { invocation ->
            if (invocation.method.name == "onValueChanged") {
                delivered.add(
                    Triple(
                        invocation.getArgument<String>(0),
                        invocation.getArgument<String>(1),
                        invocation.getArgument<String?>(2)
                    )
                )
            }
            null
        }

    private fun plugin(): UniversalBlePlugin =
        pluginWithRecordedLooper(mainLooper).also {
            it.setField("callbackChannel", callbackChannel)
        }

    private fun drainMainLooper() = drainPosts(mainLooper)



    private fun characteristic(): BluetoothGattCharacteristic =
        mockCharacteristic(serviceUuid, charUuid)

    @Test
    fun registeredClientDeliversItsNotifications() {
        val plugin = plugin()
        val gatt = mockGatt(address)
        plugin.gattRegistry().put(gatt)

        plugin.onCharacteristicChanged(gatt, characteristic(), byteArrayOf(0x01))
        drainMainLooper()

        // The owning service is reported too: the same characteristic UUID can
        // exist in several services and only the handle tells them apart (#391).
        val expected = listOf<Triple<String, String, String?>>(
            Triple(address, charUuid.toString(), serviceUuid.toString())
        )
        assertEquals(expected, delivered)
    }

    @Test
    fun supersededClientNotificationsAreDropped() {
        val plugin = plugin()
        val current = mockGatt(address)
        // Same address, not the registered client: a connect() replaced it.
        val superseded = mockGatt(address)
        plugin.gattRegistry().put(current)

        plugin.onCharacteristicChanged(superseded, characteristic(), byteArrayOf(0x01))
        drainMainLooper()
        assertTrue(delivered.isEmpty(), "a replaced client cannot report values for the address")

        plugin.onCharacteristicChanged(current, characteristic(), byteArrayOf(0x02))
        drainMainLooper()
        assertEquals(1, delivered.size, "the registered client still delivers")
    }

    @Test
    fun notificationsAfterDisconnectAreDropped() {
        val plugin = plugin()
        val gatt = mockGatt(address)
        plugin.gattRegistry().put(gatt)

        plugin.disconnect(address)
        drainMainLooper()

        plugin.onCharacteristicChanged(gatt, characteristic(), byteArrayOf(0x01))
        drainMainLooper()
        assertTrue(delivered.isEmpty(), "the app closed this connection; no client owns it now")
    }

    @Test
    fun autoConnectClientKeepsDeliveringAcrossALinkLoss() {
        val plugin = plugin()
        val gatt = mockGatt(address)
        plugin.gattRegistry().put(gatt, autoConnect = true)

        // autoConnect keeps the client registered so Android can reconnect it.
        plugin.onConnectionStateChange(
            gatt, BluetoothGatt.GATT_SUCCESS, BluetoothGatt.STATE_DISCONNECTED
        )
        drainMainLooper()
        plugin.onCharacteristicChanged(gatt, characteristic(), byteArrayOf(0x01))
        drainMainLooper()

        assertEquals(1, delivered.size)
    }
}
