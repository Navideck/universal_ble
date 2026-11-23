package com.navideck.universal_ble

import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattService
import android.os.Handler
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
    private val deviceAddress = "AA:BB:CC:DD:EE:FF"
    private val serviceUuid = UUID.fromString("0000fff0-0000-1000-8000-00805f9b34fb")
    private val charUuid = UUID.fromString("0000fff1-0000-1000-8000-00805f9b34fb")
    private val cccdUuid = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    private val descriptorUuid = UUID.fromString("00002901-0000-1000-8000-00805f9b34fb")

    private val service = Mockito.mock(BluetoothGattService::class.java)
    private val characteristic = Mockito.mock(BluetoothGattCharacteristic::class.java)
    private val gatt = Mockito.mock(BluetoothGatt::class.java)

    init {
        val device = Mockito.mock(BluetoothDevice::class.java)
        Mockito.`when`(device.address).thenReturn(deviceAddress)
        Mockito.`when`(gatt.device).thenReturn(device)

        Mockito.`when`(service.uuid).thenReturn(serviceUuid)
        Mockito.`when`(characteristic.uuid).thenReturn(charUuid)
        Mockito.`when`(characteristic.service).thenReturn(service)
        Mockito.`when`(characteristic.properties).thenReturn(
            BluetoothGattCharacteristic.PROPERTY_READ or
                BluetoothGattCharacteristic.PROPERTY_WRITE or
                BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE,
        )
        Mockito.`when`(service.getCharacteristic(charUuid)).thenReturn(characteristic)
        Mockito.`when`(gatt.getService(serviceUuid)).thenReturn(service)
        // JVM tests run with Build.VERSION.SDK_INT == 0, so the pre-33 overloads
        // are the ones reached. The stack accepts each operation unless a test
        // says otherwise, as it does on a live link.
        Mockito.`when`(
            gatt.writeCharacteristic(Mockito.any(BluetoothGattCharacteristic::class.java))
        ).thenReturn(true)
        Mockito.`when`(
            gatt.readCharacteristic(Mockito.any(BluetoothGattCharacteristic::class.java))
        ).thenReturn(true)
        Mockito.`when`(
            gatt.readDescriptor(Mockito.any(BluetoothGattDescriptor::class.java))
        ).thenReturn(true)
        Mockito.`when`(
            gatt.writeDescriptor(Mockito.any(BluetoothGattDescriptor::class.java))
        ).thenReturn(true)
        Mockito.`when`(
            gatt.setCharacteristicNotification(
                Mockito.any(BluetoothGattCharacteristic::class.java),
                Mockito.anyBoolean(),
            )
        ).thenReturn(true)
    }

    private fun plugin(): UniversalBlePlugin {
        val plugin = UniversalBlePlugin()
        // Completions are posted to the main looper; run them inline so the test
        // observes them synchronously.
        val handler = Mockito.mock(Handler::class.java)
        Mockito.doAnswer { invocation ->
            invocation.getArgument<Runnable>(0).run()
            true
        }.`when`(handler).post(Mockito.any())
        plugin.setField("mainThreadHandler", handler)
        return plugin
    }

    /** A plugin with an autoConnect client that has reported STATE_CONNECTED. */
    private fun connectedAutoConnectPlugin(): UniversalBlePlugin {
        val plugin = plugin()
        plugin.autoConnectDevices().add(deviceAddress)
        plugin.gattRegistry().put(gatt)
        report(plugin, BluetoothGatt.STATE_CONNECTED)
        return plugin
    }

    private fun report(plugin: UniversalBlePlugin, state: Int, status: Int = BluetoothGatt.GATT_SUCCESS) {
        plugin.onConnectionStateChange(gatt, status, state)
    }

    private fun UniversalBlePlugin.pendingWrites(): MutableList<WriteResultFuture> =
        getField("writeResultFutureList")

    private fun UniversalBlePlugin.pendingDescriptorWrites(): MutableList<WriteDescriptorResultFuture> =
        getField("writeDescriptorResultFutureList")

    private fun UniversalBlePlugin.pendingReads(): MutableList<ReadResultFuture> =
        getField("readResultFutureList")

    private fun UniversalBlePlugin.pendingDescriptorReads(): MutableList<ReadDescriptorResultFuture> =
        getField("readDescriptorResultFutureList")

    private fun UniversalBlePlugin.pendingSubscriptions(): MutableList<SubscriptionResultFuture> =
        getField("subscriptionResultFutureList")

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
        val plugin = plugin()
        val reconnecting = gatt
        val other = Mockito.mock(BluetoothGatt::class.java)
        val otherDevice = Mockito.mock(BluetoothDevice::class.java)
        val otherAddress = "11:22:33:44:55:66"
        Mockito.`when`(otherDevice.address).thenReturn(otherAddress)
        Mockito.`when`(other.device).thenReturn(otherDevice)
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

        report(plugin, BluetoothGatt.STATE_DISCONNECTED)

        // Registered after the disconnect sweep, so only the reconnect backstop
        // can fail it. A write registered before the sweep would be failed by
        // cleanUpConnection and would not exercise the backstop at all.
        val reconnectingResult = mutableListOf<Result<Unit>>()
        plugin.pendingWrites().add(
            WriteResultFuture(
                reconnecting, deviceAddress, charUuid.toString(), serviceUuid.toString()
            ) { reconnectingResult.add(it) }
        )
        assertEquals(0, reconnectingResult.size, "the entry must outlive the disconnect sweep")

        report(plugin, BluetoothGatt.STATE_CONNECTED)

        assertEquals(0, otherResult.size, "another device's write is still in flight")
        assertEquals(1, plugin.pendingWrites().size)
        assertEquals(1, reconnectingResult.size)
        assertDeviceDisconnected(reconnectingResult.single())
    }

    @Test
    fun theBackstopRunsBeforeTheNewLinkAcceptsRequests() {
        val plugin = connectedAutoConnectPlugin()
        report(plugin, BluetoothGatt.STATE_DISCONNECTED)

        // A request submitted while the sweep holds the list lock must still be
        // refused: the link may only be marked up after the stale entries are
        // gone, or the sweep would also fail a write the stack just accepted.
        val stale = mutableListOf<ReadResultFuture>()
        stale.add(
            ReadResultFuture(gatt, deviceAddress, charUuid.toString(), serviceUuid.toString()) {}
        )
        val linkUpDuringSweep = mutableListOf<Boolean>()
        plugin.setField("readResultFutureList", object : MutableList<ReadResultFuture> by stale {
            override fun iterator(): MutableIterator<ReadResultFuture> {
                linkUpDuringSweep.add(plugin.connectedGatts().contains(gatt))
                return stale.iterator()
            }
        })

        report(plugin, BluetoothGatt.STATE_CONNECTED)

        assertTrue(linkUpDuringSweep.isNotEmpty(), "the reconnect must sweep the stale entry")
        assertTrue(
            linkUpDuringSweep.none { it },
            "the backstop must sweep before marking the link up",
        )
        assertTrue(plugin.connectedGatts().contains(gatt), "the new link is up afterwards")
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
        val cccd = Mockito.mock(BluetoothGattDescriptor::class.java)
        Mockito.`when`(cccd.uuid).thenReturn(cccdUuid)
        Mockito.`when`(cccd.characteristic).thenReturn(characteristic)
        Mockito.`when`(characteristic.getDescriptor(cccdUuid)).thenReturn(cccd)
        val descriptor = Mockito.mock(BluetoothGattDescriptor::class.java)
        Mockito.`when`(descriptor.uuid).thenReturn(descriptorUuid)
        Mockito.`when`(descriptor.characteristic).thenReturn(characteristic)
        Mockito.`when`(characteristic.getDescriptor(descriptorUuid)).thenReturn(descriptor)

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

    @Test
    fun aSubscriptionWithoutACccdIsAlsoRefusedAfterALinkLoss() {
        // No CCCD is stubbed, so setNotifiable() takes its "some devices do not
        // need CCCD" path: there is no pending result to sweep, and the local
        // setCharacteristicNotification() would report success on a linkless
        // client.
        val plugin = connectedAutoConnectPlugin()
        report(plugin, BluetoothGatt.STATE_DISCONNECTED)

        val subscriptions = mutableListOf<Result<Unit>>()
        plugin.setNotifiable(
            deviceAddress,
            serviceUuid.toString(),
            charUuid.toString(),
            BleInputProperty.NOTIFICATION,
        ) { subscriptions.add(it) }

        assertEquals(1, subscriptions.size)
        assertDeviceDisconnected(subscriptions.single())
        Mockito.verify(gatt, Mockito.never()).setCharacteristicNotification(
            Mockito.any(BluetoothGattCharacteristic::class.java),
            Mockito.anyBoolean(),
        )
    }

    @Test
    fun mtuDiscoveryAndRssiAreRefusedAfterALinkLoss() {
        val plugin = connectedAutoConnectPlugin()
        report(plugin, BluetoothGatt.STATE_DISCONNECTED)

        val mtus = mutableListOf<Result<Long>>()
        plugin.requestMtu(deviceAddress, 247L) { mtus.add(it) }
        assertEquals(1, mtus.size)
        assertDeviceDisconnected(mtus.single())

        val rssis = mutableListOf<Result<Long>>()
        plugin.readRssi(deviceAddress) { rssis.add(it) }
        assertEquals(1, rssis.size)
        assertDeviceDisconnected(rssis.single())

        val discoveries = mutableListOf<Result<List<UniversalBleService>>>()
        plugin.discoverServices(deviceAddress, false, null) { discoveries.add(it) }
        assertEquals(1, discoveries.size)
        assertDeviceDisconnected(discoveries.single())

        Mockito.verify(gatt, Mockito.never()).requestMtu(Mockito.anyInt())
        Mockito.verify(gatt, Mockito.never()).readRemoteRssi()
        Mockito.verify(gatt, Mockito.never()).discoverServices()
    }
}
