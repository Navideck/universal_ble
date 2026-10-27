package com.navideck.universal_ble

import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattService
import android.content.Context
import android.content.SharedPreferences
import android.os.Handler
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.mockito.Mockito

/*
 * BluetoothGattCallback methods arrive on binder threads while the pending
 * futures they consume are added from API entry points on the main thread, and
 * the result they carry is a platform-channel reply, which must be sent from
 * the main thread too.
 *
 * Adding without the list's lock lets the two threads corrupt the list (a lost
 * or duplicated future means a Dart await that never returns), and completing
 * inline replies off the platform thread. Reads, RSSI, service discovery and
 * subscriptions were the only pending-future lists that still did either; the
 * write and descriptor paths were already converted.
 *
 * These tests drive the real plugin callbacks against seeded pending futures.
 */
internal class GattCallbackCompletionTest {
    private val deviceAddress = "AA:BB:CC:DD:EE:FF"
    private val serviceUuid = UUID.fromString("0000fff0-0000-1000-8000-00805f9b34fb")
    private val charUuid = UUID.fromString("0000fff1-0000-1000-8000-00805f9b34fb")

    /** Runnables the plugin posted to the main looper, in submission order. */
    private val mainLooper = mutableListOf<Runnable>()

    private fun plugin(): UniversalBlePlugin {
        val plugin = UniversalBlePlugin()
        // Record instead of running: a completion must not be delivered on the
        // thread the callback arrived on.
        val handler = Mockito.mock(Handler::class.java)
        Mockito.doAnswer { invocation ->
            mainLooper.add(invocation.getArgument(0))
            true
        }.`when`(handler).post(Mockito.any())
        plugin.setField("mainThreadHandler", handler)
        return plugin
    }

    private fun drainMainLooper() {
        while (mainLooper.isNotEmpty()) {
            mainLooper.removeAt(0).run()
        }
    }

    private fun mockGatt(): BluetoothGatt {
        val device = Mockito.mock(BluetoothDevice::class.java)
        Mockito.`when`(device.address).thenReturn(deviceAddress)
        val gatt = Mockito.mock(BluetoothGatt::class.java)
        Mockito.`when`(gatt.device).thenReturn(device)
        return gatt
    }

    private fun mockCharacteristic(): BluetoothGattCharacteristic {
        val service = Mockito.mock(BluetoothGattService::class.java)
        Mockito.`when`(service.uuid).thenReturn(serviceUuid)
        val characteristic = Mockito.mock(BluetoothGattCharacteristic::class.java)
        Mockito.`when`(characteristic.uuid).thenReturn(charUuid)
        Mockito.`when`(characteristic.service).thenReturn(service)
        return characteristic
    }

    private fun pluginWithPreferences(): UniversalBlePlugin {
        // Service discovery caches the discovered UUIDs in SharedPreferences.
        val editor = Mockito.mock(SharedPreferences.Editor::class.java)
        val preferences = Mockito.mock(SharedPreferences::class.java)
        Mockito.`when`(preferences.edit()).thenReturn(editor)
        val context = Mockito.mock(Context::class.java)
        Mockito.`when`(
            context.getSharedPreferences(Mockito.anyString(), Mockito.anyInt())
        ).thenReturn(preferences)
        val plugin = plugin()
        plugin.setField("context", context)
        return plugin
    }

    @Test
    fun readCompletionMustNotAcknowledgeAnotherPendingRead() {
        val plugin = plugin()
        val firstReads = mutableListOf<Result<ByteArray>>()
        val secondReads = mutableListOf<Result<ByteArray>>()
        val pending = plugin.getField<MutableList<ReadResultFuture>>("readResultFutureList")
        pending.add(readFuture(firstReads))
        pending.add(readFuture(secondReads))

        plugin.onCharacteristicRead(
            mockGatt(),
            mockCharacteristic(),
            byteArrayOf(0x2A),
            BluetoothGatt.GATT_SUCCESS
        )

        assertEquals(
            0,
            firstReads.size,
            "the reply must be sent from the main looper, not the binder thread"
        )
        drainMainLooper()

        assertEquals(1, firstReads.size, "the oldest pending read gets this response")
        assertTrue(firstReads[0].isSuccess)
        assertEquals(
            0,
            secondReads.size,
            "the second read is still in flight: completing it with the first " +
                "response reports the wrong value"
        )

        // Its own response completes the remaining read, exactly once.
        plugin.onCharacteristicRead(
            mockGatt(),
            mockCharacteristic(),
            byteArrayOf(0x2B),
            BluetoothGatt.GATT_SUCCESS
        )
        drainMainLooper()

        assertEquals(1, secondReads.size)
        assertEquals(0x2B.toByte(), secondReads[0].getOrThrow().single())
    }

    @Test
    fun failedReadCompletesOnlyTheOldestPendingRead() {
        val plugin = plugin()
        val firstReads = mutableListOf<Result<ByteArray>>()
        val secondReads = mutableListOf<Result<ByteArray>>()
        val pending = plugin.getField<MutableList<ReadResultFuture>>("readResultFutureList")
        pending.add(readFuture(firstReads))
        pending.add(readFuture(secondReads))

        plugin.onCharacteristicRead(
            mockGatt(),
            mockCharacteristic(),
            byteArrayOf(),
            BluetoothGatt.GATT_FAILURE
        )
        drainMainLooper()

        assertEquals(1, firstReads.size)
        assertTrue(firstReads[0].isFailure)
        assertEquals(
            0,
            secondReads.size,
            "an error of the first read must not be reported to the second"
        )
    }

    @Test
    fun rssiCompletionBelongsToOneRequestAndIsPostedToTheMainLooper() {
        val plugin = plugin()
        val firstReadings = mutableListOf<Result<Long>>()
        val secondReadings = mutableListOf<Result<Long>>()
        val pending = plugin.getField<MutableList<RssiResultFuture>>("rssiResultFutureList")
        pending.add(RssiResultFuture(deviceAddress) { firstReadings.add(it) })
        pending.add(RssiResultFuture(deviceAddress) { secondReadings.add(it) })

        plugin.onReadRemoteRssi(mockGatt(), -60, BluetoothGatt.GATT_SUCCESS)

        assertEquals(0, firstReadings.size, "RSSI must not be replied on the binder thread")
        drainMainLooper()

        assertEquals(1, firstReadings.size)
        assertEquals(-60L, firstReadings[0].getOrThrow())
        assertEquals(0, secondReadings.size, "one reading answers one request")
    }

    @Test
    fun discoveryFailureCompletesEveryPendingCallerOnTheMainLooper() {
        val plugin = plugin()
        val firstDiscoveries = mutableListOf<Result<List<UniversalBleService>>>()
        val secondDiscoveries = mutableListOf<Result<List<UniversalBleService>>>()
        val pending = plugin.getField<MutableList<DiscoverServicesFuture>>(
            "discoverServicesFutureList"
        )
        pending.add(DiscoverServicesFuture(deviceAddress, false) { firstDiscoveries.add(it) })
        pending.add(DiscoverServicesFuture(deviceAddress, true) { secondDiscoveries.add(it) })

        plugin.onServicesDiscovered(mockGatt(), BluetoothGatt.GATT_FAILURE)

        assertEquals(0, firstDiscoveries.size, "discovery must not fail on the binder thread")
        drainMainLooper()

        assertEquals(1, firstDiscoveries.size)
        assertEquals(1, secondDiscoveries.size, "a discovery result belongs to the device")
        assertTrue(firstDiscoveries[0].isFailure)
        assertTrue(secondDiscoveries[0].isFailure)
    }

    @Test
    fun discoverySuccessCompletesEveryPendingCallerOnTheMainLooper() {
        val plugin = pluginWithPreferences()
        val gatt = mockGatt()
        val service = Mockito.mock(BluetoothGattService::class.java)
        Mockito.`when`(service.uuid).thenReturn(serviceUuid)
        Mockito.`when`(service.characteristics).thenReturn(listOf())
        Mockito.`when`(gatt.services).thenReturn(listOf(service))

        val firstDiscoveries = mutableListOf<Result<List<UniversalBleService>>>()
        val secondDiscoveries = mutableListOf<Result<List<UniversalBleService>>>()
        val pending = plugin.getField<MutableList<DiscoverServicesFuture>>(
            "discoverServicesFutureList"
        )
        pending.add(DiscoverServicesFuture(deviceAddress, false) { firstDiscoveries.add(it) })
        pending.add(DiscoverServicesFuture(deviceAddress, false) { secondDiscoveries.add(it) })

        plugin.onServicesDiscovered(gatt, BluetoothGatt.GATT_SUCCESS)

        assertEquals(0, firstDiscoveries.size, "discovery must not reply on the binder thread")
        drainMainLooper()

        assertEquals(1, firstDiscoveries.size)
        assertEquals(1, secondDiscoveries.size)
        assertEquals(
            listOf(serviceUuid.toString()),
            firstDiscoveries[0].getOrThrow().map { it.uuid }
        )
    }

    @Test
    fun subscriptionCompletionIsPostedToTheMainLooper() {
        val plugin = plugin()
        val gatt = mockGatt()
        val characteristic = mockCharacteristic()
        val descriptor = Mockito.mock(BluetoothGattDescriptor::class.java)
        Mockito.`when`(descriptor.uuid).thenReturn(ccdCharacteristic)
        Mockito.`when`(descriptor.characteristic).thenReturn(characteristic)

        val subscriptions = mutableListOf<Result<Unit>>()
        val pending = plugin.getField<MutableList<SubscriptionResultFuture>>(
            "subscriptionResultFutureList"
        )
        pending.add(
            SubscriptionResultFuture(
                deviceAddress,
                charUuid.toString(),
                serviceUuid.toString()
            ) { subscriptions.add(it) }
        )

        plugin.onDescriptorWrite(gatt, descriptor, BluetoothGatt.GATT_SUCCESS)

        assertEquals(
            0,
            subscriptions.size,
            "the CCCD write reply must be sent from the main looper"
        )
        drainMainLooper()

        assertEquals(1, subscriptions.size)
        assertTrue(subscriptions[0].isSuccess)
        assertTrue(
            pending.isEmpty(),
            "a completed subscription must leave the pending list"
        )
    }

    @Test
    fun disconnectCompletesPendingFuturesOnTheMainLooper() {
        val plugin = plugin()
        val reads = mutableListOf<Result<ByteArray>>()
        val discoveries = mutableListOf<Result<List<UniversalBleService>>>()
        val subscriptions = mutableListOf<Result<Unit>>()
        val rssis = mutableListOf<Result<Long>>()
        plugin.getField<MutableList<ReadResultFuture>>("readResultFutureList")
            .add(readFuture(reads))
        plugin.getField<MutableList<DiscoverServicesFuture>>("discoverServicesFutureList")
            .add(DiscoverServicesFuture(deviceAddress, false) { discoveries.add(it) })
        plugin.getField<MutableList<SubscriptionResultFuture>>("subscriptionResultFutureList")
            .add(
                SubscriptionResultFuture(
                    deviceAddress,
                    charUuid.toString(),
                    serviceUuid.toString()
                ) { subscriptions.add(it) }
            )
        plugin.getField<MutableList<RssiResultFuture>>("rssiResultFutureList")
            .add(RssiResultFuture(deviceAddress) { rssis.add(it) })

        plugin.disconnect(deviceAddress)

        assertEquals(0, reads.size, "disconnect must fail pending work on the main looper")
        drainMainLooper()

        assertEquals(1, reads.size)
        assertTrue(reads[0].isFailure)
        assertEquals(1, discoveries.size)
        assertTrue(discoveries[0].isFailure)
        assertEquals(1, subscriptions.size)
        assertTrue(subscriptions[0].isFailure)
        assertEquals(1, rssis.size)
        assertTrue(rssis[0].isFailure)
    }

    private fun readFuture(reads: MutableList<Result<ByteArray>>) = ReadResultFuture(
        deviceAddress,
        charUuid.toString(),
        serviceUuid.toString(),
    ) { reads.add(it) }
}
