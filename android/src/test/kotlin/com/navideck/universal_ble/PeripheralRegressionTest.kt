package com.navideck.universal_ble

import android.bluetooth.*
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.Context
import android.os.Handler
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import java.util.UUID
import kotlin.test.*
import org.mockito.Mockito

internal class PeripheralRegressionTest {
    private val report = "00002a4d-0000-1000-8000-00805f9b34fb"
    private val otherReport = "00002a4e-0000-1000-8000-00805f9b34fb"
    private val hid = "00001812-0000-1000-8000-00805f9b34fb"
    private val otherService = "0000180f-0000-1000-8000-00805f9b34fb"
    private val deviceAddress = "AA:BB:CC:DD:EE:FF"

    @Suppress("UNCHECKED_CAST")
    private fun characteristics(): MutableMap<String, BluetoothGattCharacteristic> {
        val field = Class.forName("com.navideck.universal_ble.UniversalBlePeripheralExtensionsKt")
            .getDeclaredField("bluetoothGattCharacteristics")
        field.isAccessible = true
        return field.get(null) as MutableMap<String, BluetoothGattCharacteristic>
    }

    @Suppress("UNCHECKED_CAST")
    private fun characteristicInstanceIds(): MutableMap<BluetoothGattCharacteristic, String> {
        val field = Class.forName("com.navideck.universal_ble.UniversalBlePeripheralExtensionsKt")
            .getDeclaredField("characteristicInstanceIds")
        field.isAccessible = true
        return field.get(null) as MutableMap<BluetoothGattCharacteristic, String>
    }

    @AfterTest fun cleanup() = clearPeripheralCaches()

    private fun mockService(uuid: String, vararg characteristics: BluetoothGattCharacteristic): BluetoothGattService {
        val service = Mockito.mock(BluetoothGattService::class.java)
        Mockito.`when`(service.uuid).thenReturn(UUID.fromString(uuid))
        Mockito.`when`(service.characteristics).thenReturn(characteristics.toList())
        return service
    }

    private fun mockCharacteristic(
        uuid: String,
        service: BluetoothGattService,
    ): BluetoothGattCharacteristic {
        val characteristic = Mockito.mock(BluetoothGattCharacteristic::class.java)
        Mockito.`when`(characteristic.uuid).thenReturn(UUID.fromString(uuid))
        Mockito.`when`(characteristic.service).thenReturn(service)
        return characteristic
    }

    private fun mockDescriptor(characteristic: BluetoothGattCharacteristic): BluetoothGattDescriptor {
        val descriptor = Mockito.mock(BluetoothGattDescriptor::class.java)
        Mockito.`when`(descriptor.uuid).thenReturn(UUID.fromString(peripheralDescriptorCCUUID))
        Mockito.`when`(descriptor.characteristic).thenReturn(characteristic)
        return descriptor
    }

    /**
     * The real plugin cannot be constructed in a unit test (its constructor needs
     * a main looper), so the fields the peripheral paths touch are seeded instead.
     * The seeded server counts as opened in the current adapter session
     * (`adapterSession` and `gattServerSession` both start at 0).
     */
    private fun peripheralPlugin(
        server: BluetoothGattServer,
        advertiser: BluetoothLeAdvertiser = Mockito.mock(BluetoothLeAdvertiser::class.java),
    ): UniversalBlePeripheralPlugin {
        val plugin = Mockito.mock(UniversalBlePeripheralPlugin::class.java, Mockito.CALLS_REAL_METHODS)
        val manager = Mockito.mock(BluetoothManager::class.java)
        // ensurePeripheralInitialized reads the adapter before it reuses the
        // already opened server.
        Mockito.`when`(manager.adapter).thenReturn(Mockito.mock(BluetoothAdapter::class.java))
        plugin.setField("applicationContext", Mockito.mock(Context::class.java))
        plugin.setField("bluetoothManager", manager)
        plugin.setField("bluetoothLeAdvertiser", advertiser)
        plugin.setField("gattServer", server)
        plugin.setField("advertisingState", PeripheralAdvertisingState.IDLE)
        plugin.setField("callback", Mockito.mock(UniversalBlePeripheralCallback::class.java))
        plugin.setField("handler", Mockito.mock(Handler::class.java))
        plugin.setField("bluetoothDevicesMap", HashMap<String, BluetoothDevice>())
        plugin.setField("mtuByDeviceId", HashMap<String, Int>())
        plugin.setField("pendingNotifications", ArrayDeque<Any>())
        plugin.setField("notificationsInFlight", HashMap<String, Any>())
        plugin.setField("notificationRetries", HashMap<String, Runnable>())
        plugin.setField("notificationRetryAttempts", HashMap<String, Int>())
        return plugin
    }

    /** Makes settlement (posted by the plugin) run immediately in unit tests. */
    private fun UniversalBlePeripheralPlugin.runPostedRunnablesImmediately() {
        val handler = field<Handler>("handler")
        Mockito.`when`(handler.post(Mockito.any(Runnable::class.java))).thenAnswer {
            (it.arguments[0] as Runnable).run()
            true
        }
    }

    /** A runnable the plugin posted with a delay, captured so a test can run it. */
    private data class DelayedPost(val delayMillis: Long, val runnable: Runnable)

    /**
     * Captures `handler.postDelayed` calls instead of waiting for a clock, so a
     * retry test decides when the retry happens. The returned list grows as the
     * plugin schedules more retries.
     */
    private fun UniversalBlePeripheralPlugin.captureDelayedRunnables(): MutableList<DelayedPost> {
        val posted = mutableListOf<DelayedPost>()
        val handler = field<Handler>("handler")
        Mockito.`when`(handler.postDelayed(Mockito.any(Runnable::class.java), Mockito.anyLong()))
            .thenAnswer {
                posted.add(DelayedPost(it.getArgument(1), it.getArgument(0)))
                true
            }
        return posted
    }

    private fun UniversalBlePeripheralPlugin.pendingRetries(): Map<String, Runnable> =
        field("notificationRetries")

    private fun UniversalBlePeripheralPlugin.retryAttempts(): Map<String, Int> =
        field("notificationRetryAttempts")

    /**
     * Drives the private disconnect cleanup directly: the callback that normally
     * reaches it also logs through `android.util.Log`, which the JVM unit tests
     * do not mock.
     */
    private fun UniversalBlePeripheralPlugin.cleanConnection(device: BluetoothDevice) {
        val method = UniversalBlePeripheralPlugin::class.java
            .getDeclaredMethod("cleanConnection", BluetoothDevice::class.java)
        method.isAccessible = true
        method.invoke(this, device)
    }

    private fun UniversalBlePeripheralPlugin.setField(name: String, value: Any?) {
        val field = UniversalBlePeripheralPlugin::class.java.getDeclaredField(name)
        field.isAccessible = true
        field.set(this, value)
    }

    private fun <T> UniversalBlePeripheralPlugin.field(name: String): T {
        val field = UniversalBlePeripheralPlugin::class.java.getDeclaredField(name)
        field.isAccessible = true
        @Suppress("UNCHECKED_CAST")
        return field.get(this) as T
    }

    private fun UniversalBlePeripheralPlugin.callback(): UniversalBlePeripheralCallback =
        field("callback")

    /**
     * The arguments of every call the plugin made to the Dart callback. Read from
     * the recorded invocations rather than through `verify`, because the callback
     * methods take lambda parameters that cannot be matched without a matcher.
     */
    private fun UniversalBlePeripheralPlugin.callbackCalls(method: String): List<List<Any?>> =
        Mockito.mockingDetails(callback()).invocations
            .filter { it.method.name == method }
            .map { it.arguments.toList() }

    /** Makes the seeded server look like it was opened before an adapter restart. */
    private fun UniversalBlePeripheralPlugin.serverFromAPreviousAdapterSession() {
        setField("adapterSession", 2L)
        setField("gattServerSession", 1L)
    }

    private fun UniversalBlePeripheralPlugin.connectedDevice(address: String = deviceAddress): BluetoothDevice {
        val device = Mockito.mock(BluetoothDevice::class.java)
        Mockito.`when`(device.address).thenReturn(address)
        field<MutableMap<String, BluetoothDevice>>("bluetoothDevicesMap")[address] = device
        return device
    }

    /** A notify characteristic subscribed by [deviceAddress], registered as "report-1". */
    private fun UniversalBlePeripheralPlugin.subscribedNotifyCharacteristic():
        BluetoothGattCharacteristic {
        val service = mockService(hid)
        val characteristic = Mockito.mock(BluetoothGattCharacteristic::class.java)
        Mockito.`when`(characteristic.uuid).thenReturn(UUID.fromString(report))
        Mockito.`when`(characteristic.service).thenReturn(service)
        Mockito.`when`(characteristic.properties)
            .thenReturn(BluetoothGattCharacteristic.PROPERTY_NOTIFY)
        characteristics()[report] = characteristic
        characteristics()["report-1"] = characteristic
        characteristicInstanceIds()[characteristic] = "report-1"
        subscribedCharDevicesMap[deviceAddress] = mutableSetOf("report-1")
        connectedDevice()
        return characteristic
    }

    /**
     * Two notify characteristics, each in its own service, subscribed by
     * [deviceAddress] as "report-1" and "report-2".
     */
    private fun UniversalBlePeripheralPlugin.subscribedNotifyCharacteristics():
        Pair<BluetoothGattCharacteristic, BluetoothGattCharacteristic> {
        val firstService = mockService(hid)
        val secondService = mockService(otherService)
        val first = mockCharacteristic(report, firstService)
        val second = mockCharacteristic(otherReport, secondService)
        listOf(first, second).forEach {
            Mockito.`when`(it.properties).thenReturn(BluetoothGattCharacteristic.PROPERTY_NOTIFY)
        }
        characteristics()[report] = first
        characteristics()["report-1"] = first
        characteristicInstanceIds()[first] = "report-1"
        characteristics()[otherReport] = second
        characteristics()["report-2"] = second
        characteristicInstanceIds()[second] = "report-2"
        subscribedCharDevicesMap[deviceAddress] = mutableSetOf("report-1", "report-2")
        connectedDevice()
        return first to second
    }

    /** The pre-API-33 path the JVM tests take: the stack accepts the notification. */
    private fun BluetoothGattServer.acceptNotifications() {
        Mockito.`when`(
            notifyCharacteristicChanged(
                Mockito.any(BluetoothDevice::class.java),
                Mockito.any(BluetoothGattCharacteristic::class.java),
                Mockito.anyBoolean(),
            ),
        ).thenReturn(true)
    }

    /** The client's native transmit queue is still busy, so the stack refuses. */
    private fun BluetoothGattServer.refuseNotifications() {
        Mockito.`when`(
            notifyCharacteristicChanged(
                Mockito.any(BluetoothDevice::class.java),
                Mockito.any(BluetoothGattCharacteristic::class.java),
                Mockito.anyBoolean(),
            ),
        ).thenReturn(false)
    }

    private fun BluetoothGattServer.notifyCalls(): Int =
        Mockito.mockingDetails(this).invocations
            .count { it.method.name == "notifyCharacteristicChanged" }

    /** Every value the plugin assigned to [characteristic], in order. */
    private fun valuesSetOn(characteristic: BluetoothGattCharacteristic): List<List<Int>> =
        Mockito.mockingDetails(characteristic).invocations
            .filter { it.method.name == "setValue" }
            .map { invocation -> (invocation.arguments[0] as ByteArray).map(Byte::toInt) }

    @Test fun findsServiceByItsServiceUuid() {
        val service = Mockito.mock(BluetoothGattService::class.java)
        Mockito.`when`(service.uuid).thenReturn(UUID.fromString(hid))
        val characteristic = Mockito.mock(BluetoothGattCharacteristic::class.java)
        Mockito.`when`(characteristic.service).thenReturn(service)
        Mockito.`when`(characteristic.uuid).thenReturn(UUID.fromString(report))
        characteristics()[report] = characteristic
        assertSame(service, hid.findService())
    }

    @Test fun newClientDoesNotInheritAnothersCccdValue() {
        val characteristic = Mockito.mock(BluetoothGattCharacteristic::class.java)
        Mockito.`when`(characteristic.uuid).thenReturn(UUID.fromString(report))
        val descriptor = Mockito.mock(BluetoothGattDescriptor::class.java)
        Mockito.`when`(descriptor.uuid).thenReturn(UUID.fromString(peripheralDescriptorCCUUID))
        Mockito.`when`(descriptor.characteristic).thenReturn(characteristic)
        // onDescriptorWriteRequest assigns this shared value before storing the client value.
        Mockito.`when`(descriptor.value).thenReturn(byteArrayOf(1, 0))
        descriptor.storeClientValue("AA:BB:CC:DD:EE:FF", byteArrayOf(1, 0))
        assertContentEquals(byteArrayOf(0, 0), descriptor.getClientValue("11:22:33:44:55:66"))
    }

    @Test fun updateWithoutSubscribersStillUpdatesReadableValue() {
        val plugin = peripheralPlugin(Mockito.mock(BluetoothGattServer::class.java))
        val characteristic = Mockito.mock(BluetoothGattCharacteristic::class.java)
        Mockito.`when`(characteristic.properties).thenReturn(BluetoothGattCharacteristic.PROPERTY_READ)
        characteristics()[report] = characteristic
        val value = byteArrayOf(42)
        val results = mutableListOf<Result<Unit>>()
        plugin.updateCharacteristic(report, null, value, null) { results.add(it) }
        Mockito.verify(characteristic).setValue(value)
        assertEquals(1, results.size)
        assertTrue(results.single().isSuccess)
    }

    @Test fun acceptedNotificationCompletesOnlyAfterOnNotificationSent() {
        val server = Mockito.mock(BluetoothGattServer::class.java)
        val plugin = peripheralPlugin(server).also { it.runPostedRunnablesImmediately() }
        plugin.subscribedNotifyCharacteristic()
        server.acceptNotifications()
        val results = mutableListOf<Result<Unit>>()

        plugin.updateCharacteristic(report, "report-1", byteArrayOf(1), deviceAddress) {
            results.add(it)
        }

        assertTrue(results.isEmpty(), "The callback must wait until the packet is sent")
        plugin.handleNotificationSent(plugin.connectedDevice(), BluetoothGatt.GATT_SUCCESS)
        assertEquals(1, results.size)
        assertTrue(results.single().isSuccess)
    }

    @Test fun failedNotificationSentFailsTheCallback() {
        val server = Mockito.mock(BluetoothGattServer::class.java)
        val plugin = peripheralPlugin(server).also { it.runPostedRunnablesImmediately() }
        plugin.subscribedNotifyCharacteristic()
        server.acceptNotifications()
        val results = mutableListOf<Result<Unit>>()
        plugin.updateCharacteristic(report, "report-1", byteArrayOf(1), deviceAddress) {
            results.add(it)
        }

        plugin.handleNotificationSent(plugin.connectedDevice(), BluetoothGatt.GATT_FAILURE)

        assertEquals(1, results.size)
        assertTrue(results.single().isFailure)
    }

    // #403: a queued update must not overwrite the value the stack is sending
    // for the packet already in flight.
    @Test fun queuedUpdateDoesNotOverwriteInFlightCharacteristicValue() {
        val server = Mockito.mock(BluetoothGattServer::class.java)
        val plugin = peripheralPlugin(server).also { it.runPostedRunnablesImmediately() }
        val characteristic = plugin.subscribedNotifyCharacteristic()
        server.acceptNotifications()
        val results = mutableListOf<Result<Unit>>()

        plugin.updateCharacteristic(report, "report-1", byteArrayOf(1), deviceAddress) {
            results.add(it)
        }
        assertEquals(listOf(listOf(1)), valuesSetOn(characteristic))

        plugin.updateCharacteristic(report, "report-1", byteArrayOf(2), deviceAddress) {
            results.add(it)
        }
        assertEquals(
            listOf(listOf(1)),
            valuesSetOn(characteristic),
        )
        assertTrue(results.isEmpty(), "The second packet waits for the first to be sent")

        plugin.handleNotificationSent(plugin.connectedDevice(), BluetoothGatt.GATT_SUCCESS)
        assertEquals(
            listOf(listOf(1), listOf(2)),
            valuesSetOn(characteristic),
        )
        assertEquals(1, results.size)
        assertTrue(results.single().isSuccess)

        plugin.handleNotificationSent(plugin.connectedDevice(), BluetoothGatt.GATT_SUCCESS)
        assertEquals(2, results.size)
        assertTrue(results[1].isSuccess)
    }

    @Test fun clearPendingNotificationsFailsQueuedUpdatesButKeepsTheOneInFlight() {
        val server = Mockito.mock(BluetoothGattServer::class.java)
        val plugin = peripheralPlugin(server).also { it.runPostedRunnablesImmediately() }
        plugin.subscribedNotifyCharacteristic()
        server.acceptNotifications()
        val results = mutableListOf<Result<Unit>>()
        plugin.updateCharacteristic(report, "report-1", byteArrayOf(1), deviceAddress) {
            results.add(it)
        }
        plugin.updateCharacteristic(report, "report-1", byteArrayOf(2), deviceAddress) {
            results.add(it)
        }

        plugin.clearPendingNotifications(deviceAddress)

        assertEquals(1, results.size, "Only the queued update is cancelled")
        assertTrue(results.single().isFailure)
        plugin.handleNotificationSent(plugin.connectedDevice(), BluetoothGatt.GATT_SUCCESS)
        assertEquals(2, results.size)
        assertTrue(results[1].isSuccess, "The in-flight packet is still settled by its callback")
    }

    // #406: a refused send leaves nothing for onNotificationSent to report, so
    // without its own retry the client's queue waits for an unrelated update.
    @Test fun refusedNotificationIsRetriedWithoutAnotherUpdate() {
        val server = Mockito.mock(BluetoothGattServer::class.java)
        val plugin = peripheralPlugin(server).also { it.runPostedRunnablesImmediately() }
        val retries = plugin.captureDelayedRunnables()
        val characteristic = plugin.subscribedNotifyCharacteristic()
        server.refuseNotifications()
        val results = mutableListOf<Result<Unit>>()

        plugin.updateCharacteristic(report, "report-1", byteArrayOf(1), deviceAddress) {
            results.add(it)
        }

        assertEquals(1, retries.size, "The refusal schedules exactly one retry")
        assertEquals(10L, retries.single().delayMillis, "The first retry uses the base delay")
        assertTrue(plugin.pendingRetries().containsKey(deviceAddress))
        assertEquals(mapOf(deviceAddress to 1), plugin.retryAttempts())
        assertEquals(1, server.notifyCalls())
        assertTrue(results.isEmpty(), "The Dart callback waits for the retry")

        // The stack has room now: the same payload goes out again.
        server.acceptNotifications()
        retries.removeAt(0).runnable.run()

        assertEquals(listOf(listOf(1), listOf(1)), valuesSetOn(characteristic))
        assertTrue(results.isEmpty(), "The callback still waits for onNotificationSent")

        plugin.handleNotificationSent(plugin.connectedDevice(), BluetoothGatt.GATT_SUCCESS)

        assertEquals(1, results.size)
        assertTrue(results.single().isSuccess)
        assertTrue(plugin.pendingRetries().isEmpty())
        assertTrue(plugin.retryAttempts().isEmpty(), "The next refusal starts from the base delay")
    }

    // #406: one client, one retry — several queued updates must not post one each.
    @Test fun queuedUpdatesForOneClientShareARejectedRetry() {
        val server = Mockito.mock(BluetoothGattServer::class.java)
        val plugin = peripheralPlugin(server).also { it.runPostedRunnablesImmediately() }
        val retries = plugin.captureDelayedRunnables()
        plugin.subscribedNotifyCharacteristic()
        server.refuseNotifications()
        val results = mutableListOf<Result<Unit>>()

        repeat(3) { index ->
            plugin.updateCharacteristic(report, "report-1", byteArrayOf(index.toByte()), deviceAddress) {
                results.add(it)
            }
        }

        assertEquals(1, retries.size, "The updates coalesce into a single retry")
        assertEquals(mapOf(deviceAddress to 1), plugin.retryAttempts())
        assertEquals(3, server.notifyCalls(), "Each update tried the send once")
        assertTrue(results.isEmpty())
    }

    // #406: the backoff doubles per consecutive refusal, then stays at the cap.
    @Test fun refusedRetriesBackOffAndCap() {
        val server = Mockito.mock(BluetoothGattServer::class.java)
        val plugin = peripheralPlugin(server).also { it.runPostedRunnablesImmediately() }
        val retries = plugin.captureDelayedRunnables()
        plugin.subscribedNotifyCharacteristic()
        server.refuseNotifications()
        val results = mutableListOf<Result<Unit>>()
        plugin.updateCharacteristic(report, "report-1", byteArrayOf(1), deviceAddress) {
            results.add(it)
        }

        val delays = mutableListOf<Long>()
        // Each run is refused again and schedules the next attempt.
        repeat(8) {
            val retry = retries.removeAt(0)
            delays.add(retry.delayMillis)
            retry.runnable.run()
        }

        assertEquals(listOf(10L, 20L, 40L, 80L, 160L, 320L, 500L, 500L), delays)
        assertEquals(1, retries.size, "Only the latest retry is live")
        assertEquals(
            7,
            plugin.retryAttempts()[deviceAddress],
            "The counter stops at the ceiling instead of overflowing",
        )
        assertTrue(results.isEmpty())
    }

    // #406: a client that unsubscribes while the payload waits must not receive
    // it, and the retry must not loop forever.
    @Test fun retryDropsThePayloadOfAClientThatUnsubscribed() {
        val server = Mockito.mock(BluetoothGattServer::class.java)
        val plugin = peripheralPlugin(server).also { it.runPostedRunnablesImmediately() }
        val retries = plugin.captureDelayedRunnables()
        plugin.subscribedNotifyCharacteristic()
        server.refuseNotifications()
        val results = mutableListOf<Result<Unit>>()
        plugin.updateCharacteristic(report, "report-1", byteArrayOf(1), deviceAddress) {
            results.add(it)
        }
        assertEquals(1, server.notifyCalls())

        // The central writes the CCCD off before the retry fires.
        subscribedCharDevicesMap.remove(deviceAddress)
        retries.removeAt(0).runnable.run()

        assertEquals(1, results.size)
        assertTrue(results.single().isFailure)
        assertEquals("Central unsubscribed", results.single().exceptionOrNull()?.message)
        assertEquals(1, server.notifyCalls(), "The stale payload is not sent again")
        assertTrue(plugin.pendingRetries().isEmpty())
        assertTrue(plugin.retryAttempts().isEmpty())

        // Resubscribing does not resurrect it either.
        subscribedCharDevicesMap[deviceAddress] = mutableSetOf("report-1")
        server.acceptNotifications()
        retries.forEach { it.runnable.run() }
        assertEquals(1, server.notifyCalls())
        assertEquals(1, results.size)
    }

    // #406: resetting the peripheral takes the retry with the queue it belongs to.
    @Test fun peripheralResetCancelsThePendingRetry() {
        val server = Mockito.mock(BluetoothGattServer::class.java)
        val plugin = peripheralPlugin(server).also { it.runPostedRunnablesImmediately() }
        val retries = plugin.captureDelayedRunnables()
        plugin.subscribedNotifyCharacteristic()
        server.refuseNotifications()
        val results = mutableListOf<Result<Unit>>()
        plugin.updateCharacteristic(report, "report-1", byteArrayOf(1), deviceAddress) {
            results.add(it)
        }
        val retry = retries.single()
        assertTrue(plugin.pendingRetries().containsKey(deviceAddress))

        plugin.onAdapterStateChanged(BluetoothAdapter.STATE_TURNING_OFF)

        assertEquals(1, results.size, "The queued payload is failed by the cleanup")
        assertTrue(results.single().isFailure)
        assertTrue(plugin.pendingRetries().isEmpty())
        assertTrue(plugin.retryAttempts().isEmpty())
        Mockito.verify(plugin.field<Handler>("handler")).removeCallbacks(retry.runnable)

        // A retry that still fires against the torn-down state is a no-op.
        retry.runnable.run()
        assertEquals(1, server.notifyCalls())
    }

    // #406: a per-client cancel takes the retry too, matching the id's case.
    @Test fun clearPendingNotificationsCancelsTheRetry() {
        val server = Mockito.mock(BluetoothGattServer::class.java)
        val plugin = peripheralPlugin(server).also { it.runPostedRunnablesImmediately() }
        val retries = plugin.captureDelayedRunnables()
        plugin.subscribedNotifyCharacteristic()
        server.refuseNotifications()
        val results = mutableListOf<Result<Unit>>()
        plugin.updateCharacteristic(report, "report-1", byteArrayOf(1), deviceAddress) {
            results.add(it)
        }
        val retry = retries.single()

        plugin.clearPendingNotifications(deviceAddress.lowercase())

        assertEquals(1, results.size)
        assertTrue(results.single().isFailure)
        assertTrue(plugin.pendingRetries().isEmpty())
        assertTrue(plugin.retryAttempts().isEmpty())
        Mockito.verify(plugin.field<Handler>("handler")).removeCallbacks(retry.runnable)
    }

    // #406: a disconnect takes the client's queue and its retry apart together.
    @Test fun disconnectCancelsThePendingRetry() {
        val server = Mockito.mock(BluetoothGattServer::class.java)
        val plugin = peripheralPlugin(server).also { it.runPostedRunnablesImmediately() }
        val retries = plugin.captureDelayedRunnables()
        plugin.subscribedNotifyCharacteristic()
        server.refuseNotifications()
        val results = mutableListOf<Result<Unit>>()
        plugin.updateCharacteristic(report, "report-1", byteArrayOf(1), deviceAddress) {
            results.add(it)
        }
        val retry = retries.single()

        plugin.cleanConnection(plugin.connectedDevice())

        assertEquals(1, results.size, "The queued payload is failed by the disconnect")
        assertTrue(results.single().isFailure)
        assertTrue(plugin.pendingRetries().isEmpty())
        assertTrue(plugin.retryAttempts().isEmpty())
        Mockito.verify(plugin.field<Handler>("handler")).removeCallbacks(retry.runnable)

        retry.runnable.run()
        assertEquals(1, server.notifyCalls(), "A retry against the torn-down queue sends nothing")
    }

    // #406: removing a service must take the retry only when nothing else of the
    // client is queued, so another service's refused payload is still retried.
    @Test fun removeServiceCancelsTheRetryOnlyWhenNothingElseIsQueued() {
        val server = Mockito.mock(BluetoothGattServer::class.java)
        val plugin = peripheralPlugin(server).also { it.runPostedRunnablesImmediately() }
        val retries = plugin.captureDelayedRunnables()
        plugin.subscribedNotifyCharacteristics()
        server.refuseNotifications()
        val results = mutableListOf<Result<Unit>>()
        plugin.updateCharacteristic(report, "report-1", byteArrayOf(1), deviceAddress) {
            results.add(it)
        }
        plugin.updateCharacteristic(otherReport, "report-2", byteArrayOf(2), deviceAddress) {
            results.add(it)
        }
        val retry = retries.single()

        plugin.removeService(hid)

        assertEquals(1, results.size, "Only the removed service's payload is failed")
        assertTrue(results.single().isFailure)
        assertEquals("Service removed", results.single().exceptionOrNull()?.message)
        assertTrue(
            plugin.pendingRetries().containsKey(deviceAddress),
            "The other service's payload still needs its retry",
        )
        Mockito.verify(plugin.field<Handler>("handler"), Mockito.never())
            .removeCallbacks(retry.runnable)

        plugin.removeService(otherService)

        assertEquals(2, results.size)
        assertTrue(results[1].isFailure)
        assertTrue(plugin.pendingRetries().isEmpty())
        assertTrue(plugin.retryAttempts().isEmpty())
        Mockito.verify(plugin.field<Handler>("handler")).removeCallbacks(retry.runnable)
    }

    // #406: dropping the characteristic the client unsubscribed from must not
    // stop the client's other characteristics from draining, and the backoff
    // keeps counting across the drop.
    @Test fun retryDropsTheUnsubscribedCharacteristicAndDrainsTheOther() {
        val server = Mockito.mock(BluetoothGattServer::class.java)
        val plugin = peripheralPlugin(server).also { it.runPostedRunnablesImmediately() }
        val retries = plugin.captureDelayedRunnables()
        plugin.subscribedNotifyCharacteristics()
        server.refuseNotifications()
        val results = mutableListOf<Result<Unit>>()
        plugin.updateCharacteristic(report, "report-1", byteArrayOf(1), deviceAddress) {
            results.add(it)
        }
        plugin.updateCharacteristic(otherReport, "report-2", byteArrayOf(2), deviceAddress) {
            results.add(it)
        }
        assertEquals(2, server.notifyCalls())
        // The client drops the first characteristic while its payload waits,
        // without the queue dropping it (the window this retry covers).
        subscribedCharDevicesMap[deviceAddress] = mutableSetOf("report-2")

        retries.removeAt(0).runnable.run()

        assertEquals(1, results.size)
        assertTrue(results.single().isFailure)
        assertEquals("Central unsubscribed", results.single().exceptionOrNull()?.message)
        assertEquals(3, server.notifyCalls(), "The other characteristic is attempted again")
        assertEquals(1, retries.size, "The other characteristic's refusal keeps retrying")
        assertEquals(20L, retries.single().delayMillis, "The backoff continues across the drop")

        server.acceptNotifications()
        retries.removeAt(0).runnable.run()
        assertEquals(4, server.notifyCalls())
        assertEquals(1, results.size, "The retried payload still waits for onNotificationSent")
        plugin.handleNotificationSent(plugin.connectedDevice(), BluetoothGatt.GATT_SUCCESS)

        assertEquals(2, results.size)
        assertTrue(results[1].isSuccess)
        assertTrue(plugin.pendingRetries().isEmpty())
        assertTrue(plugin.retryAttempts().isEmpty())
    }

    @Test fun resetFailsTheNotificationInFlight() {
        val server = Mockito.mock(BluetoothGattServer::class.java)
        val plugin = peripheralPlugin(server).also { it.runPostedRunnablesImmediately() }
        plugin.subscribedNotifyCharacteristic()
        server.acceptNotifications()
        val results = mutableListOf<Result<Unit>>()
        plugin.updateCharacteristic(report, "report-1", byteArrayOf(1), deviceAddress) {
            results.add(it)
        }

        plugin.onAdapterStateChanged(BluetoothAdapter.STATE_TURNING_OFF)

        assertEquals(1, results.size)
        assertTrue(results.single().isFailure)
        assertTrue(plugin.field<Map<String, Any>>("notificationsInFlight").isEmpty())
    }

    // #385: a service registered a second time must resolve to the new
    // characteristics, not the ones the server no longer holds.
    @Test fun clearServicesForgetsTheRegisteredCharacteristics() {
        val server = Mockito.mock(BluetoothGattServer::class.java)
        val plugin = peripheralPlugin(server)
        val service = mockService(hid)
        val characteristic = mockCharacteristic(report, service)
        characteristics()[report] = characteristic

        plugin.clearServices()

        assertNull(report.findGattCharacteristic())
        assertNull(hid.findService())
        val replacement = mockCharacteristic(report, service)
        characteristics().putIfAbsent(report, replacement)
        assertSame(replacement, report.findGattCharacteristic())
        Mockito.verify(server).clearServices()
    }

    // m5: the caches must not keep describing services the app believes gone,
    // even when the server call throws.
    @Test fun clearServicesForgetsTheCachesWhenTheServerCallThrows() {
        val server = Mockito.mock(BluetoothGattServer::class.java)
        val plugin = peripheralPlugin(server)
        val service = mockService(hid)
        val characteristic = mockCharacteristic(report, service)
        characteristics()[report] = characteristic
        Mockito.doThrow(IllegalStateException("server closed")).`when`(server).clearServices()

        assertFailsWith<IllegalStateException> { plugin.clearServices() }

        assertNull(report.findGattCharacteristic())
        assertNull(hid.findService())
    }

    // #385: removing one service must not drop another service's state.
    @Test fun removeServiceForgetsOnlyThatServicesState() {
        val server = Mockito.mock(BluetoothGattServer::class.java)
        val plugin = peripheralPlugin(server)
        val removedService = Mockito.mock(BluetoothGattService::class.java)
        val keptService = Mockito.mock(BluetoothGattService::class.java)
        val removedCharacteristic = mockCharacteristic(report, removedService)
        val keptCharacteristic = mockCharacteristic(otherReport, keptService)
        Mockito.`when`(removedService.uuid).thenReturn(UUID.fromString(hid))
        Mockito.`when`(removedService.characteristics).thenReturn(listOf(removedCharacteristic))
        Mockito.`when`(keptService.uuid).thenReturn(UUID.fromString(otherService))
        Mockito.`when`(keptService.characteristics).thenReturn(listOf(keptCharacteristic))
        characteristics()[report] = removedCharacteristic
        characteristics()["report-1"] = removedCharacteristic
        characteristicInstanceIds()[removedCharacteristic] = "report-1"
        characteristics()[otherReport] = keptCharacteristic
        characteristicInstanceIds()[keptCharacteristic] = "report-2"
        subscribedCharDevicesMap[deviceAddress] = mutableSetOf("report-1", "report-2")

        plugin.removeService(hid)

        assertNull(report.findGattCharacteristic())
        assertNull(report.findGattCharacteristic("report-1"))
        assertSame(keptCharacteristic, otherReport.findGattCharacteristic())
        assertEquals("report-2", keptCharacteristic.instanceId())
        assertEquals<Set<String>?>(setOf("report-2"), subscribedCharDevicesMap[deviceAddress])
        Mockito.verify(server).removeService(removedService)
    }

    // m5: same for the removal path.
    @Test fun removeServiceForgetsTheCachesWhenTheServerCallThrows() {
        val server = Mockito.mock(BluetoothGattServer::class.java)
        val plugin = peripheralPlugin(server)
        val removedService = Mockito.mock(BluetoothGattService::class.java)
        val characteristic = mockCharacteristic(report, removedService)
        Mockito.`when`(removedService.uuid).thenReturn(UUID.fromString(hid))
        Mockito.`when`(removedService.characteristics).thenReturn(listOf(characteristic))
        characteristics()[report] = characteristic
        Mockito.doThrow(IllegalStateException("server closed"))
            .`when`(server).removeService(removedService)

        assertFailsWith<IllegalStateException> { plugin.removeService(hid) }

        assertNull(report.findGattCharacteristic())
        assertNull(hid.findService())
    }

    // M2: two services may expose the same characteristic UUID. Removing one must
    // leave the other reachable, and must keep its CCCD values and subscriptions.
    @Test fun removingAServiceKeepsASharedCharacteristicUuidReachable() {
        val server = Mockito.mock(BluetoothGattServer::class.java)
        val plugin = peripheralPlugin(server)
        val removedService = Mockito.mock(BluetoothGattService::class.java)
        val keptService = Mockito.mock(BluetoothGattService::class.java)
        val removedCharacteristic = mockCharacteristic(report, removedService)
        val keptCharacteristic = mockCharacteristic(report, keptService)
        val removedDescriptor = mockDescriptor(removedCharacteristic)
        val keptDescriptor = mockDescriptor(keptCharacteristic)
        Mockito.`when`(removedService.uuid).thenReturn(UUID.fromString(hid))
        Mockito.`when`(removedService.characteristics).thenReturn(listOf(removedCharacteristic))
        Mockito.`when`(keptService.uuid).thenReturn(UUID.fromString(otherService))
        Mockito.`when`(keptService.characteristics).thenReturn(listOf(keptCharacteristic))
        // Both services expose `report`; the first registration owns the UUID alias.
        characteristics()[report] = removedCharacteristic
        characteristics()["hid-report"] = removedCharacteristic
        characteristicInstanceIds()[removedCharacteristic] = "hid-report"
        characteristics()["vendor-report"] = keptCharacteristic
        characteristicInstanceIds()[keptCharacteristic] = "vendor-report"
        subscribedCharDevicesMap[deviceAddress] = mutableSetOf("hid-report", "vendor-report")
        removedDescriptor.storeClientValue(deviceAddress, byteArrayOf(1, 0))
        keptDescriptor.storeClientValue(deviceAddress, byteArrayOf(1, 0))

        plugin.removeService(hid)

        assertSame(keptCharacteristic, report.findGattCharacteristic())
        assertSame(keptCharacteristic, report.findGattCharacteristic("vendor-report"))
        assertNull(removedCharacteristic.instanceId())
        assertNull(hid.findService())
        assertSame(keptService, otherService.findService())
        assertEquals<Set<String>?>(setOf("vendor-report"), subscribedCharDevicesMap[deviceAddress])
        assertContentEquals(byteArrayOf(1, 0), keptDescriptor.getClientValue(deviceAddress))
        assertContentEquals(byteArrayOf(0, 0), removedDescriptor.getClientValue(deviceAddress))
    }

    // M2: two services may expose the same characteristic UUID without instance
    // ids, so both characteristics share one identity. Removing one must not take
    // the surviving registration's subscription or CCCD value with it.
    @Test fun removingAServiceKeepsTheStateOfAUuidOnlySharedCharacteristic() {
        val server = Mockito.mock(BluetoothGattServer::class.java)
        val plugin = peripheralPlugin(server)
        val removedService = Mockito.mock(BluetoothGattService::class.java)
        val keptService = Mockito.mock(BluetoothGattService::class.java)
        val removedCharacteristic = mockCharacteristic(report, removedService)
        val keptCharacteristic = mockCharacteristic(report, keptService)
        val keptDescriptor = mockDescriptor(keptCharacteristic)
        Mockito.`when`(removedService.uuid).thenReturn(UUID.fromString(hid))
        Mockito.`when`(removedService.characteristics).thenReturn(listOf(removedCharacteristic))
        Mockito.`when`(keptService.uuid).thenReturn(UUID.fromString(otherService))
        Mockito.`when`(keptService.characteristics).thenReturn(listOf(keptCharacteristic))
        // Neither declares an instance id, so both are identified by the UUID.
        characteristics()[report] = removedCharacteristic
        characteristics()["other"] = keptCharacteristic
        subscribedCharDevicesMap[deviceAddress] = mutableSetOf(report)
        keptDescriptor.storeClientValue(deviceAddress, byteArrayOf(1, 0))

        plugin.removeService(hid)

        assertSame(keptCharacteristic, report.findGattCharacteristic())
        assertEquals<Set<String>?>(setOf(report), subscribedCharDevicesMap[deviceAddress])
        assertContentEquals(byteArrayOf(1, 0), keptDescriptor.getClientValue(deviceAddress))
    }

    // m2: a caller-supplied instance id may contain the old key delimiter. The
    // structured key means it can neither be read as, nor delete, another
    // characteristic's CCCD entry.
    @Test fun anInstanceIdContainingTheOldDelimiterIsNotMistakenForAnother() {
        val server = Mockito.mock(BluetoothGattServer::class.java)
        val plugin = peripheralPlugin(server)
        val removedService = Mockito.mock(BluetoothGattService::class.java)
        val keptService = Mockito.mock(BluetoothGattService::class.java)
        val removedCharacteristic = mockCharacteristic(report, removedService)
        val keptCharacteristic = mockCharacteristic(otherReport, keptService)
        val removedDescriptor = mockDescriptor(removedCharacteristic)
        val keptDescriptor = mockDescriptor(keptCharacteristic)
        Mockito.`when`(removedService.uuid).thenReturn(UUID.fromString(hid))
        Mockito.`when`(removedService.characteristics).thenReturn(listOf(removedCharacteristic))
        Mockito.`when`(keptService.uuid).thenReturn(UUID.fromString(otherService))
        Mockito.`when`(keptService.characteristics).thenReturn(listOf(keptCharacteristic))
        characteristics()["a"] = removedCharacteristic
        characteristicInstanceIds()[removedCharacteristic] = "a"
        characteristics()["a|b"] = keptCharacteristic
        characteristicInstanceIds()[keptCharacteristic] = "a|b"
        subscribedCharDevicesMap[deviceAddress] = mutableSetOf("a", "a|b")
        keptDescriptor.storeClientValue(deviceAddress, byteArrayOf(1, 0))
        removedDescriptor.storeClientValue(deviceAddress, byteArrayOf(2, 0))

        plugin.removeService(hid)

        assertEquals("a|b", keptCharacteristic.instanceId())
        assertContentEquals(byteArrayOf(1, 0), keptDescriptor.getClientValue(deviceAddress))
        assertContentEquals(byteArrayOf(0, 0), removedDescriptor.getClientValue(deviceAddress))
        assertEquals<Set<String>?>(setOf("a|b"), subscribedCharDevicesMap[deviceAddress])
    }

    // #384: a server left over from a previous adapter session rejects every
    // registration, so one retry on a freshly opened server is allowed.
    @Test fun addServiceRetriesOnceOnAFreshGattServer() {
        val staleServer = Mockito.mock(BluetoothGattServer::class.java)
        val freshServer = Mockito.mock(BluetoothGattServer::class.java)
        val plugin = peripheralPlugin(staleServer).also { it.serverFromAPreviousAdapterSession() }
        val manager = Mockito.mock(BluetoothManager::class.java)
        val adapter = Mockito.mock(BluetoothAdapter::class.java)
        Mockito.`when`(adapter.bluetoothLeAdvertiser)
            .thenReturn(Mockito.mock(BluetoothLeAdvertiser::class.java))
        Mockito.`when`(manager.adapter).thenReturn(adapter)
        Mockito.`when`(manager.openGattServer(Mockito.any(), Mockito.any())).thenReturn(freshServer)
        plugin.setField("bluetoothManager", manager)
        val staleService = Mockito.mock(BluetoothGattService::class.java)
        val freshService = Mockito.mock(BluetoothGattService::class.java)
        Mockito.`when`(staleServer.addService(staleService)).thenReturn(false)
        Mockito.`when`(freshServer.addService(freshService)).thenReturn(true)
        val attempts = ArrayDeque(listOf(staleService, freshService))

        plugin.addServiceWithRetry(buildService = { attempts.removeFirst() })

        assertTrue(attempts.isEmpty())
        assertSame(freshServer, plugin.field<BluetoothGattServer>("gattServer"))
        Mockito.verify(staleServer).close()
        Mockito.verify(manager, Mockito.times(1)).openGattServer(Mockito.any(), Mockito.any())
    }

    // M1: a rejection on the current session's server is not proof that the
    // server is dead. Android refuses a UUID it already holds, and dropping the
    // session for that unregisters every other service, disconnects every client
    // and stops advertising.
    @Test fun addServiceKeepsTheSessionWhenTheServerIsFromTheCurrentAdapterSession() {
        val server = Mockito.mock(BluetoothGattServer::class.java)
        val plugin = peripheralPlugin(server)
        plugin.connectedDevice()
        plugin.setField("advertisingState", PeripheralAdvertisingState.ADVERTISING)
        Mockito.`when`(server.addService(Mockito.any())).thenReturn(false)

        assertFailsWith<IllegalStateException> {
            plugin.addServiceWithRetry(
                buildService = { Mockito.mock(BluetoothGattService::class.java) },
            )
        }

        assertSame(server, plugin.field<BluetoothGattServer>("gattServer"))
        assertTrue(
            plugin.field<MutableMap<String, BluetoothDevice>>("bluetoothDevicesMap")
                .containsKey(deviceAddress),
        )
        assertEquals(PeripheralAdvertisingState.ADVERTISING, plugin.getAdvertisingState())
        Mockito.verify(server, Mockito.never()).close()
        // Nothing was dropped, so nothing may be reported as dropped.
        Mockito.verifyNoInteractions(plugin.callback())
    }

    // M1: when the session *is* dropped, the app must be able to resynchronise.
    @Test fun droppingTheSessionReportsEveryClientAndTheAdvertisingState() {
        val server = Mockito.mock(BluetoothGattServer::class.java)
        val plugin = peripheralPlugin(server)
        plugin.connectedDevice()
        plugin.setField("advertisingState", PeripheralAdvertisingState.ADVERTISING)

        plugin.onAdapterStateChanged(BluetoothAdapter.STATE_TURNING_OFF)

        assertEquals(
            listOf(listOf(deviceAddress, false)),
            plugin.callbackCalls("onConnectionStateChange").map { it.take(2) },
        )
        assertEquals(
            listOf(listOf(PeripheralAdvertisingState.IDLE, "Bluetooth turned off")),
            plugin.callbackCalls("onAdvertisingStateChange").map { it.take(2) },
        )
        assertEquals(PeripheralAdvertisingState.IDLE, plugin.getAdvertisingState())
        assertTrue(plugin.field<MutableMap<String, BluetoothDevice>>("bluetoothDevicesMap").isEmpty())
    }

    // M3: advertising that the drop stopped is not left reporting ADVERTISING.
    @Test fun bluetoothOffMovesAdvertisingToIdle() {
        val plugin = peripheralPlugin(Mockito.mock(BluetoothGattServer::class.java))
        plugin.setField("advertisingState", PeripheralAdvertisingState.STARTING)

        plugin.onAdapterStateChanged(BluetoothAdapter.STATE_OFF)

        assertEquals(PeripheralAdvertisingState.IDLE, plugin.getAdvertisingState())
    }

    @Test fun bluetoothOffDoesNotReportAdvertisingThatWasNotRunning() {
        val plugin = peripheralPlugin(Mockito.mock(BluetoothGattServer::class.java))

        plugin.onAdapterStateChanged(BluetoothAdapter.STATE_TURNING_OFF)

        assertEquals(PeripheralAdvertisingState.IDLE, plugin.getAdvertisingState())
        assertTrue(plugin.callbackCalls("onAdvertisingStateChange").isEmpty())
    }

    // #384: a genuine rejection is not an endless recovery attempt.
    @Test fun addServiceSurfacesTheOriginalRejectionAfterOneRetry() {
        val staleServer = Mockito.mock(BluetoothGattServer::class.java)
        val freshServer = Mockito.mock(BluetoothGattServer::class.java)
        val plugin = peripheralPlugin(staleServer).also { it.serverFromAPreviousAdapterSession() }
        val manager = Mockito.mock(BluetoothManager::class.java)
        val adapter = Mockito.mock(BluetoothAdapter::class.java)
        Mockito.`when`(adapter.bluetoothLeAdvertiser)
            .thenReturn(Mockito.mock(BluetoothLeAdvertiser::class.java))
        Mockito.`when`(manager.adapter).thenReturn(adapter)
        Mockito.`when`(manager.openGattServer(Mockito.any(), Mockito.any())).thenReturn(freshServer)
        plugin.setField("bluetoothManager", manager)
        val attempts = mutableListOf<BluetoothGattService>()
        val rejections = mutableListOf<IllegalStateException>()
        Mockito.`when`(staleServer.addService(Mockito.any())).thenReturn(false)
        Mockito.`when`(freshServer.addService(Mockito.any())).thenReturn(false)

        val error = assertFailsWith<IllegalStateException> {
            plugin.addServiceWithRetry(
                buildService = {
                    // toGattService() registers the characteristics it builds; the
                    // refused attempt must not leave them behind.
                    val gattService = Mockito.mock(BluetoothGattService::class.java)
                    val characteristic = mockCharacteristic(report, gattService)
                    Mockito.`when`(gattService.characteristics).thenReturn(listOf(characteristic))
                    characteristics()[report] = characteristic
                    attempts.add(gattService)
                    gattService
                },
                rejection = { message ->
                    // Distinct instances, so the reported one can be identified.
                    IllegalStateException(message).also(rejections::add)
                },
            )
        }

        assertEquals("Service registration rejected", error.message)
        assertEquals(2, attempts.size)
        assertEquals(2, rejections.size)
        assertSame(rejections.first(), error)
        Mockito.verify(manager, Mockito.times(1)).openGattServer(Mockito.any(), Mockito.any())
        // The refused characteristics must not stay resolvable either.
        assertTrue(characteristics().isEmpty())
    }

    // m1: when the retry cannot even open a server, the caller still gets the
    // rejection that started it, not the unrelated failure of the retry.
    @Test fun aFailedRetryStillReportsTheOriginalRejection() {
        val staleServer = Mockito.mock(BluetoothGattServer::class.java)
        val plugin = peripheralPlugin(staleServer).also { it.serverFromAPreviousAdapterSession() }
        val manager = Mockito.mock(BluetoothManager::class.java)
        // The first attempt runs on the seeded server; the retry finds no adapter.
        Mockito.`when`(manager.adapter)
            .thenReturn(Mockito.mock(BluetoothAdapter::class.java))
            .thenReturn(null)
        plugin.setField("bluetoothManager", manager)
        Mockito.`when`(staleServer.addService(Mockito.any())).thenReturn(false)
        val rejections = mutableListOf<IllegalStateException>()

        val error = assertFailsWith<IllegalStateException> {
            plugin.addServiceWithRetry(
                buildService = { Mockito.mock(BluetoothGattService::class.java) },
                rejection = { message -> IllegalStateException(message).also(rejections::add) },
            )
        }

        assertSame(rejections.first(), error)
        assertEquals(1, error.suppressed.size)
        assertIs<UnsupportedOperationException>(error.suppressed[0])
    }

    // #384: Bluetooth going off invalidates the server, the advertiser and the
    // state that belongs to that adapter session.
    @Test fun bluetoothOffDropsTheAdapterBoundState() {
        val server = Mockito.mock(BluetoothGattServer::class.java)
        val plugin = peripheralPlugin(server)
        val characteristic = mockCharacteristic(report, mockService(hid))
        characteristics()[report] = characteristic
        plugin.connectedDevice()
        plugin.field<MutableMap<String, Int>>("mtuByDeviceId")[deviceAddress] = 247

        plugin.onAdapterStateChanged(BluetoothAdapter.STATE_TURNING_OFF)

        assertNull(plugin.field<BluetoothGattServer?>("gattServer"))
        assertNull(plugin.field<BluetoothLeAdvertiser?>("bluetoothLeAdvertiser"))
        assertTrue(plugin.field<MutableMap<String, BluetoothDevice>>("bluetoothDevicesMap").isEmpty())
        assertTrue(plugin.field<MutableMap<String, Int>>("mtuByDeviceId").isEmpty())
        assertNull(report.findGattCharacteristic())
        Mockito.verify(server).close()
    }

    @Test fun bluetoothOnKeepsTheInitialisedServer() {
        val server = Mockito.mock(BluetoothGattServer::class.java)
        val plugin = peripheralPlugin(server)

        plugin.onAdapterStateChanged(BluetoothAdapter.STATE_ON)

        assertSame(server, plugin.field<BluetoothGattServer>("gattServer"))
        Mockito.verify(server, Mockito.never()).close()
    }

    // m4: the restore write fails while Bluetooth is off. The override must stay
    // recorded so the next STATE_ON tries again.
    @Test fun aFailedAdapterNameRestoreIsRetriedOnTheNextStateOn() {
        val plugin = peripheralPlugin(Mockito.mock(BluetoothGattServer::class.java))
        val manager = Mockito.mock(BluetoothManager::class.java)
        val adapter = Mockito.mock(BluetoothAdapter::class.java)
        Mockito.`when`(manager.adapter).thenReturn(adapter)
        plugin.setField("bluetoothManager", manager)
        plugin.setField("adapterNameOverridden", true)
        plugin.setField("originalAdapterName", "Original")
        Mockito.`when`(adapter.setName("Original")).thenReturn(false)

        plugin.onAdapterStateChanged(BluetoothAdapter.STATE_OFF)

        assertTrue(plugin.field("adapterNameOverridden"))
        assertEquals("Original", plugin.field("originalAdapterName"))

        Mockito.`when`(adapter.setName("Original")).thenReturn(true)

        plugin.onAdapterStateChanged(BluetoothAdapter.STATE_ON)

        assertFalse(plugin.field("adapterNameOverridden"))
        assertNull(plugin.field<String?>("originalAdapterName"))
    }

    // m3: the mock's `init` never runs, so this asserts the call (and that a
    // second dispose is a no-op), not a successful registration round trip.
    @Test fun disposeUnregistersTheAdapterReceiver() {
        val context = Mockito.mock(Context::class.java)
        val plugin = peripheralPlugin(Mockito.mock(BluetoothGattServer::class.java))
        plugin.setField("applicationContext", context)

        plugin.dispose()

        Mockito.verify(context).unregisterReceiver(Mockito.any())
    }

    @Test fun disposeIsIdempotent() {
        val context = Mockito.mock(Context::class.java)
        val plugin = peripheralPlugin(Mockito.mock(BluetoothGattServer::class.java))
        plugin.setField("applicationContext", context)

        plugin.dispose()
        plugin.dispose()

        // A second unregisterReceiver throws on a real context.
        Mockito.verify(context, Mockito.times(1)).unregisterReceiver(Mockito.any())
    }

    // m3: a detached engine may have no adapter. That must not abort the teardown
    // before the peripheral plugin, and its receiver, are released.
    @Test fun detachingWithoutAnAdapterStillReleasesThePeripheralPlugin() {
        val plugin = UniversalBlePlugin()
        val context = Mockito.mock(Context::class.java)
        val manager = Mockito.mock(BluetoothManager::class.java)
        Mockito.`when`(manager.adapter).thenReturn(null)
        val peripheral = Mockito.mock(UniversalBlePeripheralPlugin::class.java)
        plugin.setField("context", context)
        plugin.setField("bluetoothManager", manager)
        plugin.setField("peripheralPlugin", peripheral)
        plugin.setField("mainThreadHandler", Mockito.mock(Handler::class.java))
        val binding = Mockito.mock(FlutterPlugin.FlutterPluginBinding::class.java)
        Mockito.`when`(binding.binaryMessenger).thenReturn(Mockito.mock(BinaryMessenger::class.java))

        plugin.onDetachedFromEngine(binding)

        Mockito.verify(peripheral).dispose()
        Mockito.verify(context).unregisterReceiver(Mockito.any())
    }
}
