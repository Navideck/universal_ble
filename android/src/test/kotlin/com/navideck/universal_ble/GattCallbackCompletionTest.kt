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
import kotlin.test.assertSame
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

    private val requestGatt by lazy { mockGatt(deviceAddress) }

    /** Runnables the plugin posted to the main looper, in submission order. */
    private val mainLooper = mutableListOf<Runnable>()

    private fun plugin(): UniversalBlePlugin =
        // Record instead of running: a completion must not be delivered on the
        // thread the callback arrived on.
        pluginWithRecordedLooper(mainLooper)

    private fun drainMainLooper() = drainPosts(mainLooper)

    private fun pluginWithPreferences(): UniversalBlePlugin {
        // Service discovery caches the discovered UUIDs in SharedPreferences.
        val preferences = Mockito.mock(SharedPreferences::class.java)
        Mockito.`when`(preferences.edit()).thenReturn(preferencesEditor)
        val context = Mockito.mock(Context::class.java)
        Mockito.`when`(
            context.getSharedPreferences(Mockito.anyString(), Mockito.anyInt())
        ).thenReturn(preferences)
        val plugin = plugin()
        plugin.setField("context", context)
        return plugin
    }

    /** The editor a cached-services write would use; a test can assert it stays untouched. */
    private val preferencesEditor: SharedPreferences.Editor by lazy {
        Mockito.mock(SharedPreferences.Editor::class.java)
    }

    @Test
    fun readCompletionMustNotAcknowledgeAnotherPendingRead() {
        val plugin = plugin()
        val firstReads = mutableListOf<Result<ByteArray>>()
        val secondReads = mutableListOf<Result<ByteArray>>()
        val pending = plugin.pendingReads()
        pending.add(readFuture(firstReads))
        pending.add(readFuture(secondReads))

        plugin.onCharacteristicRead(
            requestGatt,
            mockCharacteristic(serviceUuid, charUuid),
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
            requestGatt,
            mockCharacteristic(serviceUuid, charUuid),
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
        val pending = plugin.pendingReads()
        pending.add(readFuture(firstReads))
        pending.add(readFuture(secondReads))

        plugin.onCharacteristicRead(
            requestGatt,
            mockCharacteristic(serviceUuid, charUuid),
            byteArrayOf(),
            BluetoothGatt.GATT_FAILURE
        )
        assertEquals(
            0,
            firstReads.size,
            "the reply must be sent from the main looper, not the binder thread"
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
        val pending = plugin.pendingRssis()
        pending.add(RssiResultFuture(requestGatt, deviceAddress) { firstReadings.add(it) })
        pending.add(RssiResultFuture(requestGatt, deviceAddress) { secondReadings.add(it) })

        plugin.onReadRemoteRssi(requestGatt, -60, BluetoothGatt.GATT_SUCCESS)

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
        val pending = plugin.pendingDiscoveries()
        pending.add(DiscoverServicesFuture(requestGatt, deviceAddress, false) { firstDiscoveries.add(it) })
        pending.add(DiscoverServicesFuture(requestGatt, deviceAddress, true) { secondDiscoveries.add(it) })

        plugin.onServicesDiscovered(requestGatt, BluetoothGatt.GATT_FAILURE)

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
        val gatt = requestGatt
        val service = Mockito.mock(BluetoothGattService::class.java)
        Mockito.`when`(service.uuid).thenReturn(serviceUuid)
        Mockito.`when`(service.characteristics).thenReturn(listOf())
        Mockito.`when`(gatt.services).thenReturn(listOf(service))

        val firstDiscoveries = mutableListOf<Result<List<UniversalBleService>>>()
        val secondDiscoveries = mutableListOf<Result<List<UniversalBleService>>>()
        val pending = plugin.pendingDiscoveries()
        pending.add(DiscoverServicesFuture(requestGatt, deviceAddress, false) { firstDiscoveries.add(it) })
        pending.add(DiscoverServicesFuture(requestGatt, deviceAddress, false) { secondDiscoveries.add(it) })
        // Only the client the registry holds may publish the service cache, so
        // register the gatt that reports the discovery.
        plugin.gattRegistry().put(gatt)

        plugin.onServicesDiscovered(gatt, BluetoothGatt.GATT_SUCCESS)

        assertEquals(0, firstDiscoveries.size, "discovery must not reply on the binder thread")
        drainMainLooper()

        assertEquals(1, firstDiscoveries.size)
        assertEquals(1, secondDiscoveries.size)
        assertEquals(
            listOf(serviceUuid.toString()),
            firstDiscoveries[0].getOrThrow().map { it.uuid }
        )
        Mockito.verify(preferencesEditor)
            .putStringSet(deviceAddress, setOf(serviceUuid.toString()))
    }

    @Test
    fun subscriptionCompletionIsPostedToTheMainLooper() {
        val plugin = plugin()
        val gatt = mockGatt(deviceAddress)
        val characteristic = mockCharacteristic(serviceUuid, charUuid)
        val descriptor = Mockito.mock(BluetoothGattDescriptor::class.java)
        Mockito.`when`(descriptor.uuid).thenReturn(ccdCharacteristic)
        Mockito.`when`(descriptor.characteristic).thenReturn(characteristic)

        val subscriptions = mutableListOf<Result<Unit>>()
        val pending = plugin.pendingSubscriptions()
        pending.add(
            SubscriptionResultFuture(
                gatt,
                descriptor,
                deviceAddress
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
    fun staleSubscriptionCallbackCannotCompleteReplacementConnection() {
        val plugin = plugin()
        val oldGatt = mockGatt(deviceAddress)
        val currentGatt = mockGatt(deviceAddress)
        val characteristic = mockCharacteristic(serviceUuid, charUuid)
        fun descriptor(): BluetoothGattDescriptor {
            val descriptor = Mockito.mock(BluetoothGattDescriptor::class.java)
            Mockito.`when`(descriptor.uuid).thenReturn(ccdCharacteristic)
            Mockito.`when`(descriptor.characteristic).thenReturn(characteristic)
            return descriptor
        }
        val oldDescriptor = descriptor()
        val currentDescriptor = descriptor()
        val subscriptions = mutableListOf<Result<Unit>>()
        val pending = plugin.pendingSubscriptions()
        pending.add(
            SubscriptionResultFuture(
                currentGatt, currentDescriptor, deviceAddress
            ) { subscriptions.add(it) }
        )

        // Same address and UUIDs, but callbacks from a previous connection
        // must not consume the current request.
        plugin.onDescriptorWrite(oldGatt, oldDescriptor, BluetoothGatt.GATT_SUCCESS)
        plugin.onDescriptorWrite(oldGatt, currentDescriptor, BluetoothGatt.GATT_FAILURE)
        drainMainLooper()
        assertTrue(subscriptions.isEmpty())
        assertEquals(1, pending.size)

        plugin.onDescriptorWrite(currentGatt, currentDescriptor, BluetoothGatt.GATT_SUCCESS)
        drainMainLooper()
        assertEquals(1, subscriptions.size)
        assertTrue(subscriptions.single().isSuccess)
        assertTrue(pending.isEmpty())

        plugin.onDescriptorWrite(currentGatt, currentDescriptor, BluetoothGatt.GATT_SUCCESS)
        drainMainLooper()
        assertEquals(1, subscriptions.size, "a duplicate callback cannot complete twice")
    }

    @Test
    fun rebuiltDescriptorStillCompletesItsSubscription() {
        val plugin = plugin()
        val gatt = mockGatt(deviceAddress)
        val characteristic = mockCharacteristic(serviceUuid, charUuid)
        val submitted = mockDescriptor(characteristic, "00002902-0000-1000-8000-00805f9b34fb")
        // A discoverServices() completing between the CCCD write and its
        // callback rebuilds the service tree, so the framework reports a new
        // descriptor object for the same attribute.
        val rebuilt = mockDescriptor(characteristic, "00002902-0000-1000-8000-00805f9b34fb")
        val results = mutableListOf<Result<Unit>>()
        val pending = plugin.pendingSubscriptions()
        pending.add(SubscriptionResultFuture(gatt, submitted, deviceAddress) { results.add(it) })

        // The CCCD of another characteristic carries the same descriptor UUID
        // and is a different attribute.
        val otherCharacteristic = Mockito.mock(BluetoothGattCharacteristic::class.java)
        Mockito.`when`(otherCharacteristic.uuid)
            .thenReturn(UUID.fromString("0000fff2-0000-1000-8000-00805f9b34fb"))
        Mockito.`when`(otherCharacteristic.service).thenReturn(
            Mockito.mock(BluetoothGattService::class.java)
        )
        plugin.onDescriptorWrite(
            gatt,
            mockDescriptor(otherCharacteristic, "00002902-0000-1000-8000-00805f9b34fb"),
            BluetoothGatt.GATT_SUCCESS
        )
        drainMainLooper()
        assertTrue(results.isEmpty(), "another characteristic's CCCD is not this request")

        plugin.onDescriptorWrite(gatt, rebuilt, BluetoothGatt.GATT_SUCCESS)
        drainMainLooper()
        assertEquals(1, results.size)
        assertTrue(results.single().isSuccess)
        assertTrue(pending.isEmpty())
    }

    @Test
    fun disconnectCompletesPendingFuturesOnTheMainLooper() {
        val plugin = plugin()
        val reads = mutableListOf<Result<ByteArray>>()
        val discoveries = mutableListOf<Result<List<UniversalBleService>>>()
        val subscriptions = mutableListOf<Result<Unit>>()
        val rssis = mutableListOf<Result<Long>>()
        plugin.pendingReads()
            .add(readFuture(reads))
        plugin.pendingDiscoveries()
            .add(DiscoverServicesFuture(requestGatt, deviceAddress, false) { discoveries.add(it) })
        plugin.pendingSubscriptions()
            .add(
                SubscriptionResultFuture(
                    mockGatt(deviceAddress),
                    Mockito.mock(BluetoothGattDescriptor::class.java),
                    deviceAddress
                ) { subscriptions.add(it) }
            )
        plugin.pendingRssis()
            .add(RssiResultFuture(requestGatt, deviceAddress) { rssis.add(it) })

        plugin.disconnect(deviceAddress)

        assertEquals(0, reads.size, "disconnect must fail pending work on the main looper")
        assertEquals(
            0,
            discoveries.size,
            "disconnect must fail pending work on the main looper"
        )
        assertEquals(
            0,
            subscriptions.size,
            "disconnect must fail pending work on the main looper"
        )
        assertEquals(0, rssis.size, "disconnect must fail pending work on the main looper")
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

    @Test
    fun readValueRegistersTheFutureBeforeTheReadCanRespond() {
        val plugin = plugin()
        val reads = mutableListOf<Result<ByteArray>>()
        val characteristic = mockCharacteristic(serviceUuid, charUuid)
        val gatt = mockGattWithService(characteristic)
        // The stack can answer on a binder thread before readCharacteristic()
        // returns; a future registered only afterwards would never be matched
        // and the Dart call would await forever.
        Mockito.`when`(gatt.readCharacteristic(characteristic)).thenAnswer {
            plugin.onCharacteristicRead(
                gatt,
                characteristic,
                byteArrayOf(0x2A),
                BluetoothGatt.GATT_SUCCESS
            )
            true
        }
        plugin.attachConnectedGatt(gatt)

        plugin.readValue(deviceAddress, serviceUuid.toString(), charUuid.toString()) {
            reads.add(it)
        }
        drainMainLooper()

        assertEquals(1, reads.size, "a response must complete the read that was in flight")
        assertTrue(reads[0].isSuccess)
        assertEquals(0x2A.toByte(), reads[0].getOrThrow().single())
        assertTrue(
            plugin.pendingReads().isEmpty(),
            "a completed read must leave the pending list"
        )
    }

    @Test
    fun rejectedReadLeavesNoPendingFuture() {
        val plugin = plugin()
        val reads = mutableListOf<Result<ByteArray>>()
        val characteristic = mockCharacteristic(serviceUuid, charUuid)
        val gatt = mockGattWithService(characteristic)
        Mockito.`when`(gatt.readCharacteristic(characteristic)).thenReturn(false)
        plugin.attachConnectedGatt(gatt)

        plugin.readValue(deviceAddress, serviceUuid.toString(), charUuid.toString()) {
            reads.add(it)
        }

        assertEquals(1, reads.size)
        assertTrue(reads[0].isFailure)
        assertTrue(
            plugin.pendingReads().isEmpty(),
            "a read the stack refused must not stay registered for a later callback"
        )
    }

    @Test
    fun readFailureAfterDisconnectMustNotReplyTwice() {
        for (throwsOnRead in listOf(false, true)) {
            val plugin = plugin()
            val reads = mutableListOf<Result<ByteArray>>()
            val characteristic = mockCharacteristic(serviceUuid, charUuid)
            val gatt = mockGattWithService(characteristic)
            Mockito.`when`(gatt.readCharacteristic(characteristic)).thenAnswer {
                // A binder-thread disconnect can close the client before the read starts.
                plugin.onConnectionStateChange(
                    gatt, BluetoothGatt.GATT_SUCCESS, BluetoothGatt.STATE_DISCONNECTED
                )
                if (throwsOnRead) throw IllegalStateException("GATT client closed")
                false
            }
            plugin.attachConnectedGatt(gatt)

            plugin.readValue(deviceAddress, serviceUuid.toString(), charUuid.toString()) {
                reads.add(it)
            }

            assertTrue(reads.isEmpty(), "disconnect owns the reply, including when the read throws")
            drainMainLooper()

            assertEquals(1, reads.size, "one read must send exactly one reply")
            assertEquals(
                UniversalBleErrorCode.DEVICE_DISCONNECTED.raw.toString(),
                (reads.single().exceptionOrNull() as FlutterError).code
            )
            assertTrue(plugin.pendingReads().isEmpty())
        }
    }

    @Test
    fun throwingReadLeavesNoPendingFuture() {
        val plugin = plugin()
        val reads = mutableListOf<Result<ByteArray>>()
        val characteristic = mockCharacteristic(serviceUuid, charUuid)
        val gatt = mockGattWithService(characteristic)
        Mockito.`when`(gatt.readCharacteristic(characteristic))
            .thenThrow(IllegalStateException("Read failed"))
        plugin.attachConnectedGatt(gatt)

        plugin.readValue(deviceAddress, serviceUuid.toString(), charUuid.toString()) {
            reads.add(it)
        }
        drainMainLooper()

        assertEquals(1, reads.size)
        assertEquals(
            UniversalBleErrorCode.READ_FAILED.raw.toString(),
            (reads.single().exceptionOrNull() as FlutterError).code
        )
        assertTrue(plugin.pendingReads().isEmpty())
    }

    @Test
    fun setNotifiableRegistersTheFutureBeforeTheCccdWriteCanRespond() {
        val plugin = plugin()
        val results = mutableListOf<Result<Unit>>()
        val characteristic = mockCharacteristic(serviceUuid, charUuid)
        val cccd = mockDescriptor(characteristic, "00002902-0000-1000-8000-00805f9b34fb")
        Mockito.`when`(characteristic.getDescriptor(ccdCharacteristic)).thenReturn(cccd)
        val gatt = mockGattWithService(characteristic)
        Mockito.`when`(gatt.setCharacteristicNotification(characteristic, true)).thenReturn(true)
        // The stack can answer on a binder thread before writeDescriptor()
        // returns; a future registered only afterwards would never be matched
        // and the Dart call would await forever.
        Mockito.`when`(gatt.writeDescriptor(cccd)).thenAnswer {
            plugin.onDescriptorWrite(gatt, cccd, BluetoothGatt.GATT_SUCCESS)
            true
        }
        plugin.attachConnectedGatt(gatt)
        val pending = plugin.pendingSubscriptions()

        plugin.setNotifiable(
            deviceAddress,
            serviceUuid.toString(),
            charUuid.toString(),
            BleInputProperty.NOTIFICATION,
        ) { results.add(it) }
        drainMainLooper()

        assertEquals(1, results.size, "a response must complete the subscription in flight")
        assertTrue(results[0].isSuccess)
        assertTrue(
            pending.isEmpty(),
            "the completed future must leave the list, and must not be registered twice"
        )
    }

    @Test
    fun aThrowingCccdWriteFailsTheSubscriptionExactlyOnce() {
        val plugin = plugin()
        val results = mutableListOf<Result<Unit>>()
        val characteristic = mockCharacteristic(serviceUuid, charUuid)
        val cccd = mockDescriptor(characteristic, "00002902-0000-1000-8000-00805f9b34fb")
        Mockito.`when`(characteristic.getDescriptor(ccdCharacteristic)).thenReturn(cccd)
        val gatt = mockGattWithService(characteristic)
        // A descriptor the framework has rebuilt out from under the call, or a
        // closed client, throws instead of returning a status.
        Mockito.`when`(gatt.writeDescriptor(cccd))
            .thenThrow(IllegalStateException("GATT client closed"))
        plugin.attachConnectedGatt(gatt)

        plugin.setNotifiable(
            deviceAddress,
            serviceUuid.toString(),
            charUuid.toString(),
            BleInputProperty.NOTIFICATION,
        ) { results.add(it) }
        drainMainLooper()

        assertEquals(1, results.size, "a throwing CCCD write must answer the call once")
        assertTrue(results.single().isFailure)
        assertTrue(
            plugin.pendingSubscriptions().isEmpty(),
            "the withdraw happens before the reply, not instead of it"
        )
    }

    @Test
    fun aWriteSweptWhileTheStackRefusesItIsNotAnsweredTwice() {
        val plugin = plugin()
        val writes = mutableListOf<Result<Unit>>()
        val characteristic = mockCharacteristic(serviceUuid, charUuid)
        Mockito.`when`(characteristic.properties).thenReturn(
            BluetoothGattCharacteristic.PROPERTY_WRITE,
        )
        val gatt = mockGattWithService(characteristic)
        // A binder-thread disconnect can sweep the write before the synchronous
        // refusal is handled. The sweep owns the reply from then on.
        Mockito.`when`(gatt.writeCharacteristic(characteristic)).thenAnswer {
            plugin.onConnectionStateChange(
                gatt, BluetoothGatt.GATT_SUCCESS, BluetoothGatt.STATE_DISCONNECTED
            )
            false
        }
        plugin.attachConnectedGatt(gatt)

        plugin.writeValue(
            deviceAddress,
            serviceUuid.toString(),
            charUuid.toString(),
            ByteArray(4),
            BleOutputProperty.WITH_RESPONSE,
        ) { writes.add(it) }

        drainMainLooper()
        assertEquals(1, writes.size, "one write must send exactly one reply")
        assertEquals(
            UniversalBleErrorCode.DEVICE_DISCONNECTED.raw.toString(),
            (writes.single().exceptionOrNull() as FlutterError).code,
        )
    }

    @Test
    fun rejectedSubscriptionLeavesNoPendingFuture() {
        val plugin = plugin()
        val results = mutableListOf<Result<Unit>>()
        val characteristic = mockCharacteristic(serviceUuid, charUuid)
        val cccd = mockDescriptor(characteristic, "00002902-0000-1000-8000-00805f9b34fb")
        Mockito.`when`(characteristic.getDescriptor(ccdCharacteristic)).thenReturn(cccd)
        val gatt = mockGattWithService(characteristic)
        Mockito.`when`(gatt.writeDescriptor(cccd)).thenReturn(false)
        plugin.attachConnectedGatt(gatt)

        plugin.setNotifiable(
            deviceAddress,
            serviceUuid.toString(),
            charUuid.toString(),
            BleInputProperty.NOTIFICATION,
        ) { results.add(it) }

        assertEquals(1, results.size)
        assertTrue(results[0].isFailure)
        assertTrue(
            plugin.pendingSubscriptions().isEmpty(),
            "a write the stack refused must not stay registered for a later callback"
        )
    }

    @Test
    fun oldGattCallbacksDoNotConsumeReplacementRequests() {
        for (status in listOf(BluetoothGatt.GATT_SUCCESS, BluetoothGatt.GATT_FAILURE)) {
            val plugin = plugin()
            val old = mockGatt(deviceAddress)
            val current = mockGatt(deviceAddress)
            val characteristic = mockCharacteristic(serviceUuid, charUuid)
            val descriptor = mockDescriptor(characteristic, "00002901-0000-1000-8000-00805f9b34fb")
            val cccd = mockDescriptor(characteristic, "00002902-0000-1000-8000-00805f9b34fb")
            val results = mutableListOf<Boolean>()
            seedOperations(plugin, current, descriptor, cccd, results)
            fun deliver(gatt: BluetoothGatt) {
                plugin.onCharacteristicRead(gatt, characteristic, byteArrayOf(1), status)
                plugin.onCharacteristicWrite(gatt, characteristic, status)
                plugin.onReadRemoteRssi(gatt, -60, status)
                plugin.onServicesDiscovered(gatt, status)
                plugin.onDescriptorRead(gatt, descriptor, status, byteArrayOf(1))
                plugin.onDescriptorWrite(gatt, descriptor, status)
                plugin.onDescriptorWrite(gatt, cccd, status)
                drainMainLooper()
            }
            deliver(old)
            assertTrue(results.isEmpty(), "same-address old callbacks cannot consume new requests")
            deliver(current)
            assertEquals(7, results.size)
            assertTrue(results.all { it == (status == BluetoothGatt.GATT_SUCCESS) })
            deliver(current)
            assertEquals(7, results.size, "duplicate callbacks cannot reply twice")
        }
    }

    @Test
    fun oldGattCleanupPreservesReplacementRequests() {
        val plugin = plugin()
        val old = mockGatt(deviceAddress)
        val current = mockGatt(deviceAddress)
        plugin.gattRegistry().put(current)
        val characteristic = mockCharacteristic(serviceUuid, charUuid)
        val descriptor = mockDescriptor(characteristic, "00002901-0000-1000-8000-00805f9b34fb")
        val cccd = mockDescriptor(characteristic, "00002902-0000-1000-8000-00805f9b34fb")
        val oldResults = mutableListOf<Boolean>()
        val currentResults = mutableListOf<Boolean>()
        seedOperations(plugin, old, descriptor, cccd, oldResults)
        seedOperations(plugin, current, descriptor, cccd, currentResults)
        val cleanup = UniversalBlePlugin::class.java.getDeclaredMethod(
            "cleanUpConnection", String::class.java, BluetoothGatt::class.java
        ).apply { isAccessible = true }
        cleanup.invoke(plugin, deviceAddress, old)
        drainMainLooper()
        assertEquals(List(7) { false }, oldResults)
        assertTrue(currentResults.isEmpty(), "old disconnect cannot fail the replacement's work")
        cleanup.invoke(plugin, deviceAddress, null)
        drainMainLooper()
        assertEquals(List(7) { false }, currentResults, "explicit device cleanup still clears all owners")
        assertEquals(7, oldResults.size)
    }

    @Test
    fun cleanupKeepsARequestWhoseClientIsRegisteredWhileItIsSwept() {
        // Completions run inline, so the read fails while the sweep is still
        // going. Its callback publishes the replacement, and the write that
        // client owns is swept afterwards: the registry has to be read at match
        // time rather than once when the sweep starts.
        val plugin = pluginWithInlineLooper()
        val old = mockGatt(deviceAddress)
        val current = mockGatt(deviceAddress)
        val oldReads = mutableListOf<Result<ByteArray>>()
        val currentWrites = mutableListOf<Result<Unit>>()
        plugin.pendingReads().add(
            ReadResultFuture(
                old, deviceAddress, charUuid.toString(), serviceUuid.toString()
            ) { result ->
                oldReads.add(result)
                // A connect() publishes the replacement mid-sweep.
                plugin.gattRegistry().put(current)
            }
        )
        plugin.pendingWrites().add(
            WriteResultFuture(
                current, deviceAddress, charUuid.toString(), serviceUuid.toString()
            ) { currentWrites.add(it) }
        )
        val cleanup = UniversalBlePlugin::class.java.getDeclaredMethod(
            "cleanUpConnection", String::class.java, BluetoothGatt::class.java
        ).apply { isAccessible = true }

        cleanup.invoke(plugin, deviceAddress, old)

        assertEquals(1, oldReads.size, "the old client's read is failed")
        assertTrue(oldReads.single().isFailure)
        assertTrue(currentWrites.isEmpty(), "the replacement's write is still in flight")
        assertEquals(1, plugin.pendingWrites().size)
        assertSame(current, plugin.gattRegistry().find(deviceAddress)?.gatt)
    }

    @Test
    fun cleanupFailsOperationsLeftByAClientThatIsNoLongerRegistered() {
        val plugin = plugin()
        val current = mockGatt(deviceAddress)
        val superseded = mockGatt(deviceAddress)
        plugin.gattRegistry().put(current)
        val characteristic = mockCharacteristic(serviceUuid, charUuid)
        val cccd = mockDescriptor(characteristic, "00002902-0000-1000-8000-00805f9b34fb")
        // A client replaced by a newer connect() that never reported
        // STATE_DISCONNECTED keeps its futures registered (#277).
        val orphanResults = mutableListOf<Boolean>()
        plugin.pendingReads()
            .add(
                ReadResultFuture(
                    superseded, deviceAddress, charUuid.toString(), serviceUuid.toString()
                ) { orphanResults.add(it.isSuccess) }
            )
        plugin.pendingSubscriptions()
            .add(SubscriptionResultFuture(superseded, cccd, deviceAddress) {
                orphanResults.add(it.isSuccess)
            })

        plugin.disconnect(deviceAddress)
        drainMainLooper()

        assertEquals(
            List(2) { false },
            orphanResults,
            "cleanup for the address must not leave a superseded client's operations pending"
        )
        assertTrue(plugin.pendingReads().isEmpty())
        assertTrue(
            plugin.pendingSubscriptions().isEmpty()
        )
    }

    @Test
    fun oldDiscoveryCannotOverwriteReplacementServiceCache() {
        val plugin = pluginWithPreferences()
        val current = mockGatt(deviceAddress)
        val old = mockGatt(deviceAddress)
        plugin.gattRegistry().put(current)
        // Stub the discovered services: Mockito's default empty list would make
        // the cache guard look exercised when it is not.
        val discovered = Mockito.mock(BluetoothGattService::class.java)
        Mockito.`when`(discovered.uuid).thenReturn(serviceUuid)
        Mockito.`when`(old.services).thenReturn(listOf(discovered))
        val cache = plugin.getField<MutableMap<String, List<String>>>("cachedServicesMap")
        cache[deviceAddress] = listOf("current-service")
        plugin.onServicesDiscovered(old, BluetoothGatt.GATT_SUCCESS)
        drainMainLooper()
        assertEquals(listOf("current-service"), cache[deviceAddress])
        Mockito.verifyNoInteractions(preferencesEditor)
    }

    private fun mockDescriptor(characteristic: BluetoothGattCharacteristic, uuid: String): BluetoothGattDescriptor {
        val descriptor = Mockito.mock(BluetoothGattDescriptor::class.java)
        Mockito.`when`(descriptor.uuid).thenReturn(UUID.fromString(uuid))
        Mockito.`when`(descriptor.characteristic).thenReturn(characteristic)
        return descriptor
    }

    private fun seedOperations(
        plugin: UniversalBlePlugin,
        gatt: BluetoothGatt,
        descriptor: BluetoothGattDescriptor,
        cccd: BluetoothGattDescriptor,
        results: MutableList<Boolean>,
    ) {
        plugin.pendingReads()
            .add(ReadResultFuture(gatt, deviceAddress, charUuid.toString(), serviceUuid.toString()) { results.add(it.isSuccess) })
        plugin.pendingWrites()
            .add(WriteResultFuture(gatt, deviceAddress, charUuid.toString(), serviceUuid.toString()) { results.add(it.isSuccess) })
        plugin.pendingRssis()
            .add(RssiResultFuture(gatt, deviceAddress) { results.add(it.isSuccess) })
        plugin.pendingDiscoveries()
            .add(DiscoverServicesFuture(gatt, deviceAddress, false) { results.add(it.isSuccess) })
        plugin.pendingDescriptorReads()
            .add(ReadDescriptorResultFuture(gatt, deviceAddress, descriptor.uuid.toString(), charUuid.toString(), serviceUuid.toString()) { results.add(it.isSuccess) })
        plugin.pendingDescriptorWrites()
            .add(WriteDescriptorResultFuture(gatt, deviceAddress, descriptor.uuid.toString(), charUuid.toString(), serviceUuid.toString()) { results.add(it.isSuccess) })
        plugin.pendingSubscriptions()
            .add(SubscriptionResultFuture(gatt, cccd, deviceAddress) { results.add(it.isSuccess) })
    }

    /** A gatt whose [serviceUuid] service exposes [characteristic] under [charUuid]. */
    private fun mockGattWithService(
        characteristic: BluetoothGattCharacteristic
    ): BluetoothGatt {
        val service = Mockito.mock(BluetoothGattService::class.java)
        Mockito.`when`(service.uuid).thenReturn(serviceUuid)
        Mockito.`when`(service.getCharacteristic(charUuid)).thenReturn(characteristic)
        val gatt = mockGatt(deviceAddress)
        Mockito.`when`(gatt.getService(serviceUuid)).thenReturn(service)
        return gatt
    }

    private fun readFuture(reads: MutableList<Result<ByteArray>>) = ReadResultFuture(
        requestGatt,
        deviceAddress,
        charUuid.toString(),
        serviceUuid.toString(),
    ) { reads.add(it) }
}
