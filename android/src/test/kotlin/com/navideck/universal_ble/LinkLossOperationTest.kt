package com.navideck.universal_ble

import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.mockito.Mockito

/*
 * An autoConnect client stays open after a link loss, so between the
 * STATE_DISCONNECTED callback and the reconnect the stack still hands the plugin
 * a live BluetoothGatt with its cached service tree. A request submitted in that
 * window can be accepted by the stack and then dropped without any callback
 * (below API 33 `writeCharacteristic` returns true for a disconnected client).
 * The orphaned pending entry would then be completed by the first callback of
 * the reconnected link, so every later request would lag by one and the
 * per-device Dart queue would time out at about one write per timeout (#394).
 *
 * The plugin must therefore refuse a request whose client has no live link, and
 * as a backstop fail anything still pending when a client that lost its link
 * reports STATE_CONNECTED again. Tests drive the real plugin through its
 * connection callbacks.
 */
internal class LinkLossOperationTest {
    private val deviceAddress = GattIds.ADDRESS
    private val serviceUuid = GattIds.SERVICE
    private val charUuid = GattIds.CHARACTERISTIC
    private val cccdUuid = GattIds.CCCD
    private val descriptorUuid = GattIds.DESCRIPTOR

    private val fixture = GattFixture().also { it.acceptOperations() }
    private val gatt get() = fixture.gatt
    private val characteristic get() = fixture.characteristic

    /** A plugin with an autoConnect client that has reported STATE_CONNECTED. */
    private fun connectedAutoConnectPlugin(): UniversalBlePlugin {
        val plugin = pluginWithInlineLooper()
        plugin.autoConnectDevices().add(deviceAddress)
        plugin.gattRegistry().put(gatt)
        report(plugin, BluetoothGatt.STATE_CONNECTED)
        return plugin
    }

    private fun report(plugin: UniversalBlePlugin, state: Int, status: Int = BluetoothGatt.GATT_SUCCESS) {
        plugin.onConnectionStateChange(gatt, status, state)
    }

    private fun errorCode(result: Result<*>): String? =
        (result.exceptionOrNull() as? FlutterError)?.code

    private fun assertDeviceDisconnected(result: Result<*>) {
        assertEquals(
            UniversalBleErrorCode.DEVICE_DISCONNECTED.raw.toString(),
            errorCode(result),
        )
    }

    private fun write(plugin: UniversalBlePlugin, acks: MutableList<Result<Unit>>) {
        plugin.writeValue(
            deviceAddress,
            serviceUuid.toString(),
            charUuid.toString(),
            ByteArray(12),
            BleOutputProperty.WITHOUT_RESPONSE,
        ) { acks.add(it) }
    }

    private fun writeWithResponse(plugin: UniversalBlePlugin, acks: MutableList<Result<Unit>>) {
        plugin.writeValue(
            deviceAddress,
            serviceUuid.toString(),
            charUuid.toString(),
            ByteArray(12),
            BleOutputProperty.WITH_RESPONSE,
        ) { acks.add(it) }
    }

    @Test
    fun aWriteAfterALinkLossFailsImmediatelyAndNeverReachesTheStack() {
        val plugin = connectedAutoConnectPlugin()
        // The link drops; autoConnect keeps the client open and its services
        // cached, so writeValue can still find the characteristic.
        report(plugin, BluetoothGatt.STATE_DISCONNECTED)

        val acks = mutableListOf<Result<Unit>>()
        write(plugin, acks)

        assertEquals(1, acks.size, "the write must fail instead of waiting for the Dart timeout")
        assertDeviceDisconnected(acks.single())
        assertTrue(plugin.pendingWrites().isEmpty(), "a refused write must not stay pending")
        assertTrue(
            plugin.awaitingReconnectGatts().contains(gatt),
            "autoConnect keeps the client open for the system to reconnect",
        )
        Mockito.verify(gatt, Mockito.never())
            .writeCharacteristic(Mockito.any(BluetoothGattCharacteristic::class.java))
    }

    @Test
    fun aWriteAfterTheAutoReconnectCompletesOnItsOwnCallback() {
        val plugin = connectedAutoConnectPlugin()
        report(plugin, BluetoothGatt.STATE_DISCONNECTED)
        val refused = mutableListOf<Result<Unit>>()
        write(plugin, refused)
        assertTrue(refused.single().isFailure)

        // Android reconnects the same BluetoothGatt instance.
        report(plugin, BluetoothGatt.STATE_CONNECTED)
        assertTrue(
            plugin.awaitingReconnectGatts().isEmpty(),
            "the client is connected again, so nothing is waiting for a reconnect",
        )
        val acks = mutableListOf<Result<Unit>>()
        writeWithResponse(plugin, acks)

        assertEquals(1, plugin.pendingWrites().size, "the write must await its own callback")
        plugin.onCharacteristicWrite(gatt, characteristic, BluetoothGatt.GATT_SUCCESS)

        assertEquals(1, acks.size)
        assertTrue(acks.single().isSuccess, "the write must complete, not lag by one")
        assertTrue(plugin.pendingWrites().isEmpty())
    }

    @Test
    fun aRequestLeftFromThePreviousLinkIsFailedOnReconnect() {
        val plugin = connectedAutoConnectPlugin()
        report(plugin, BluetoothGatt.STATE_DISCONNECTED)
        // A request that the submission gate cannot cover (or one that slipped
        // in before the disconnect was processed) outlives its link.
        val stale = mutableListOf<Result<Unit>>()
        plugin.pendingWrites().add(
            WriteResultFuture(gatt, deviceAddress, charUuid.toString(), serviceUuid.toString()) {
                stale.add(it)
            }
        )

        report(plugin, BluetoothGatt.STATE_CONNECTED)

        assertEquals(1, stale.size, "the new link must not inherit the previous one's request")
        assertDeviceDisconnected(stale.single())
        assertTrue(
            plugin.pendingWrites().isEmpty(),
            "a stale entry must not consume the new link's first write completion",
        )

        val acks = mutableListOf<Result<Unit>>()
        writeWithResponse(plugin, acks)
        plugin.onCharacteristicWrite(gatt, characteristic, BluetoothGatt.GATT_SUCCESS)
        assertEquals(1, acks.size)
        assertTrue(acks.single().isSuccess)
    }

    @Test
    fun theBackstopTouchesOnlyTheReconnectingClient() {
        val plugin = pluginWithInlineLooper()
        val reconnecting = gatt
        val otherAddress = GattIds.OTHER_ADDRESS
        val other = mockGatt(otherAddress)
        plugin.autoConnectDevices().add(deviceAddress)
        plugin.gattRegistry().put(other)
        plugin.connectedGatts().add(other)
        plugin.gattRegistry().put(reconnecting)
        plugin.connectedGatts().add(reconnecting)

        val otherResult = mutableListOf<Result<Unit>>()
        plugin.pendingWrites().add(
            WriteResultFuture(other, otherAddress, charUuid.toString(), serviceUuid.toString()) {
                otherResult.add(it)
            }
        )
        val reconnectingResult = mutableListOf<Result<Unit>>()
        plugin.pendingWrites().add(
            WriteResultFuture(
                reconnecting, deviceAddress, charUuid.toString(), serviceUuid.toString()
            ) { reconnectingResult.add(it) }
        )

        report(plugin, BluetoothGatt.STATE_DISCONNECTED)
        report(plugin, BluetoothGatt.STATE_CONNECTED)

        assertEquals(0, otherResult.size, "another device's write is still in flight")
        assertEquals(1, plugin.pendingWrites().size)
        assertEquals(1, reconnectingResult.size)
        assertDeviceDisconnected(reconnectingResult.single())
    }

    @Test
    fun aDuplicateConnectedCallbackDoesNotFailRequestsInFlight() {
        val plugin = connectedAutoConnectPlugin()
        val acks = mutableListOf<Result<Unit>>()
        writeWithResponse(plugin, acks)

        // No link loss in between: a repeated STATE_CONNECTED is not a new link.
        report(plugin, BluetoothGatt.STATE_CONNECTED)

        assertTrue(acks.isEmpty(), "a write in flight must not be failed by a repeated event")
        assertEquals(1, plugin.pendingWrites().size)
    }

    @Test
    fun readsDescriptorWritesAndSubscriptionsAreRefusedAfterALinkLoss() {
        val plugin = connectedAutoConnectPlugin()
        fixture.descriptor(cccdUuid)
        fixture.descriptor(descriptorUuid)

        report(plugin, BluetoothGatt.STATE_DISCONNECTED)

        val reads = mutableListOf<Result<ByteArray>>()
        plugin.readValue(deviceAddress, serviceUuid.toString(), charUuid.toString()) {
            reads.add(it)
        }
        assertEquals(1, reads.size)
        assertDeviceDisconnected(reads.single())

        val descriptorReads = mutableListOf<Result<ByteArray>>()
        plugin.readDescriptorValue(
            deviceAddress,
            serviceUuid.toString(),
            charUuid.toString(),
            descriptorUuid.toString(),
        ) { descriptorReads.add(it) }
        assertEquals(1, descriptorReads.size)
        assertDeviceDisconnected(descriptorReads.single())

        val descriptorWrites = mutableListOf<Result<Unit>>()
        plugin.writeDescriptorValue(
            deviceAddress,
            serviceUuid.toString(),
            charUuid.toString(),
            descriptorUuid.toString(),
            ByteArray(4),
        ) { descriptorWrites.add(it) }
        assertEquals(1, descriptorWrites.size)
        assertDeviceDisconnected(descriptorWrites.single())

        val subscriptions = mutableListOf<Result<Unit>>()
        plugin.setNotifiable(
            deviceAddress,
            serviceUuid.toString(),
            charUuid.toString(),
            BleInputProperty.NOTIFICATION,
        ) { subscriptions.add(it) }
        assertEquals(1, subscriptions.size)
        assertDeviceDisconnected(subscriptions.single())

        assertTrue(plugin.pendingReads().isEmpty())
        assertTrue(plugin.pendingDescriptorReads().isEmpty())
        assertTrue(plugin.pendingDescriptorWrites().isEmpty())
        assertTrue(plugin.pendingSubscriptions().isEmpty())
        Mockito.verify(gatt, Mockito.never())
            .readCharacteristic(Mockito.any(BluetoothGattCharacteristic::class.java))
        Mockito.verify(gatt, Mockito.never())
            .readDescriptor(Mockito.any(BluetoothGattDescriptor::class.java))
        Mockito.verify(gatt, Mockito.never())
            .writeDescriptor(Mockito.any(BluetoothGattDescriptor::class.java))
    }
}
