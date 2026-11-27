package com.navideck.universal_ble

import android.annotation.SuppressLint
import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothStatusCodes
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Handler
import android.os.ParcelUuid
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

private const val TAG = "UniversalBlePeripheral"
private const val REQUEST_CODE_ENABLE_BLUETOOTH = 2342717

/** Bytes of [value] starting at [offset], as ATT expects for a read at that offset. */
private fun offsetSuffix(value: ByteArray, offset: Int): ByteArray = when {
    offset <= 0 -> value
    offset >= value.size -> byteArrayOf()
    else -> value.copyOfRange(offset, value.size)
}

@SuppressLint("MissingPermission")
class UniversalBlePeripheralPlugin(
    private val applicationContext: Context,
    private val bluetoothManager: BluetoothManager,
    messenger: BinaryMessenger,
) : UniversalBlePeripheralChannel {
    private var activity: Activity? = null
    private val callback = UniversalBlePeripheralCallback(messenger)
    private val handler = Handler(applicationContext.mainLooper)
    private var bluetoothLeAdvertiser: BluetoothLeAdvertiser? = null
    private var gattServer: BluetoothGattServer? = null
    private val bluetoothDevicesMap: MutableMap<String, BluetoothDevice> = HashMap()
    private val mtuByDeviceId: MutableMap<String, Int> = HashMap()
    private val emptyBytes = byteArrayOf()
    private var advertisingState: PeripheralAdvertisingState = PeripheralAdvertisingState.IDLE
    private var originalAdapterName: String? = null
    private var adapterNameOverridden = false
    private var isEnableBluetoothPromptPending = false
    private var disposed = false

    /**
     * Identifier of the current adapter session, bumped by every observed
     * [BluetoothAdapter.ACTION_STATE_CHANGED]. [gattServerSession] records the
     * session [gattServer] was opened in, so a server older than the current
     * session is known to have died with the adapter even though it is still
     * non-null here.
     */
    private var adapterSession: Long = 0

    /** The adapter session [gattServer] was opened in, or -1 when there is none. */
    private var gattServerSession: Long = -1
    @Volatile
    private var autoConnect: Boolean = true

    private data class PendingNotification(
        val device: BluetoothDevice,
        val characteristic: BluetoothGattCharacteristic,
        val value: ByteArray,
        val indicate: Boolean,
        /** Called exactly once, on [handler], with null when the stack accepted/sent it. */
        val onSettled: (Throwable?) -> Unit,
    )

    /**
     * Notifications waiting for the native transmit queue. Android accepts one
     * notification per client at a time ([BluetoothGattServer.notifyCharacteristicChanged]
     * returns false while the previous one is in flight), so they are drained
     * FIFO from [BluetoothGattServerCallback.onNotificationSent]. Ordering matters:
     * a HID release must never overtake the press it releases.
     *
     * This monitor also guards the transmit itself. Below API 33 the payload
     * travels in the shared [BluetoothGattCharacteristic.value], so the check,
     * the dequeue, that assignment and the notify call must not interleave with
     * another drain or with an update (#403).
     */
    private val pendingNotifications: ArrayDeque<PendingNotification> = ArrayDeque()

    /**
     * The notification each client currently owns, keyed by client address. It
     * is the one [BluetoothGattServerCallback.onNotificationSent] settles; the
     * key is also the client's "busy" marker, so a later packet cannot overtake
     * it before that callback.
     */
    private val notificationsInFlight: MutableMap<String, PendingNotification> = HashMap()

    /**
     * Settles [notifications] with [error] on the main thread. A GATT callback
     * runs on a binder thread, so completing the Pigeon result there would reply
     * to Dart from the wrong thread.
     */
    private fun settleNotifications(notifications: List<PendingNotification>, error: Throwable?) {
        if (notifications.isEmpty()) return
        handler.post {
            notifications.forEach { it.onSettled(error) }
        }
    }

    /**
     * Removes the notifications matching [predicate] from both the pending queue
     * and the in-flight map, and returns them so their callers can be failed.
     * Whatever is returned will not be reported by [onNotificationSent] again.
     */
    private fun dropNotifications(
        includeInFlight: Boolean = true,
        predicate: (PendingNotification) -> Boolean,
    ): List<PendingNotification> = synchronized(pendingNotifications) {
        val removed = pendingNotifications.filter(predicate).toMutableList()
        pendingNotifications.removeAll(predicate)
        if (includeInFlight) {
            val droppedInFlight = notificationsInFlight.filterValues(predicate)
            notificationsInFlight.values.removeAll(predicate)
            removed.addAll(droppedInFlight.values)
        }
        removed
    }

    /**
     * A [BluetoothGattServer] and a [BluetoothLeAdvertiser] do not survive an
     * adapter restart: the stack drops them, but they stay non-null here, so
     * every later registration is rejected (#384). Drop the adapter-bound state
     * when Bluetooth goes off, and the next peripheral call re-opens it.
     */
    private val adapterStateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action != BluetoothAdapter.ACTION_STATE_CHANGED) return
            val state = intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR)
            // Run where the plugin already serialises its work.
            handler.post { onAdapterStateChanged(state) }
        }
    }

    init {
        applicationContext.registerReceiverCompat(
            adapterStateReceiver,
            IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED),
            exported = true,
        )
    }

    fun attachActivity(activity: Activity?) {
        this.activity = activity
    }

    fun dispose() {
        // Detaching twice must not throw: onDetachedFromEngine is not guaranteed
        // to be the last caller, and a failed teardown must not leave the
        // receiver registered.
        if (disposed) return
        disposed = true
        kotlin.runCatching {
            applicationContext.unregisterReceiver(adapterStateReceiver)
        }.onFailure {
            UniversalBleLogger.logWarning("Failed to unregister the adapter receiver: ${it.message}")
        }
        // Drop callbacks posted for the previous state first, then let the
        // reset post the settlements for the notifications it discards. Doing it
        // the other way round would sweep those settlements away and leave their
        // Dart futures pending.
        handler.removeCallbacksAndMessages(null)
        resetPeripheralState()
        isEnableBluetoothPromptPending = false
    }

    /**
     * Drops the peripheral state that only exists for the current adapter
     * session: the GATT server and advertiser themselves, connected clients,
     * negotiated MTUs, queued and in-flight notifications, and the peripheral
     * caches. The next peripheral call re-opens them lazily.
     *
     * What it takes away is reported to Dart, because nothing else will: every
     * dropped client is disconnected, and an advertiser that is gone while the
     * state still says ADVERTISING is moved to [PeripheralAdvertisingState.IDLE].
     * Runs on the main thread, like its callers (the adapter receiver, `dispose`
     * and the platform-channel handlers).
     */
    private fun resetPeripheralState(advertisingMessage: String? = null) {
        kotlin.runCatching { bluetoothLeAdvertiser?.stopAdvertising(advertiseCallback) }
        restoreAdapterNameIfNeeded()
        // Queued notifications belong to the server that is being dropped, so
        // discard them before the caches that resolve their characteristics.
        clearPendingNotifications(null)
        val droppedInFlight = synchronized(pendingNotifications) {
            // The old server will never report these as sent, and a leftover
            // marker would block that client's queue forever.
            val current = notificationsInFlight.values.toList()
            notificationsInFlight.clear()
            current
        }
        settleNotifications(droppedInFlight, IllegalStateException("Peripheral reset"))
        kotlin.runCatching { gattServer?.close() }
        gattServer = null
        gattServerSession = -1
        bluetoothLeAdvertiser = null
        val droppedClients = synchronized(bluetoothDevicesMap) {
            val devices = bluetoothDevicesMap.values.toList()
            bluetoothDevicesMap.clear()
            devices
        }
        synchronized(mtuByDeviceId) { mtuByDeviceId.clear() }
        clearPeripheralCaches()
        droppedClients.forEach { device ->
            callback.onConnectionStateChange(device.address, false) {}
        }
        val wasAdvertising = advertisingState == PeripheralAdvertisingState.STARTING ||
            advertisingState == PeripheralAdvertisingState.ADVERTISING ||
            advertisingState == PeripheralAdvertisingState.STOPPING
        if (wasAdvertising) {
            advertisingState = PeripheralAdvertisingState.IDLE
            callback.onAdvertisingStateChange(PeripheralAdvertisingState.IDLE, advertisingMessage) {}
        }
    }

    /**
     * Drops the adapter-bound state when Bluetooth goes off, and starts a new
     * adapter session on every transition. See [adapterStateReceiver].
     */
    internal fun onAdapterStateChanged(state: Int) {
        // Any transition ends the session the current server was opened in: the
        // stack kills it on an adapter restart, and one opened while Bluetooth
        // was off is dead once it comes back on.
        adapterSession++
        when (state) {
            BluetoothAdapter.STATE_ON -> restoreAdapterNameIfNeeded()
            BluetoothAdapter.STATE_TURNING_OFF,
            BluetoothAdapter.STATE_OFF,
            -> resetPeripheralState("Bluetooth turned off")
        }
    }

    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == REQUEST_CODE_ENABLE_BLUETOOTH) {
            isEnableBluetoothPromptPending = false
            return true
        }
        return false
    }

    private fun promptEnableBluetooth(activity: Activity) {
        if (isEnableBluetoothPromptPending) return
        isEnableBluetoothPromptPending = true
        try {
            activity.startActivityForResult(
                Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE),
                REQUEST_CODE_ENABLE_BLUETOOTH,
            )
        } catch (e: Exception) {
            isEnableBluetoothPromptPending = false
            Log.e(TAG, "Failed to start Bluetooth enable activity", e)
        }
    }

    /** Opens the LE advertiser and GATT server on first use (not in the constructor). */
    private fun ensurePeripheralInitialized() {
        val adapter = bluetoothManager.adapter
            ?: throw UnsupportedOperationException("Bluetooth is not available.")
        if (bluetoothLeAdvertiser != null && gattServer != null) return
        bluetoothLeAdvertiser = adapter.bluetoothLeAdvertiser
            ?: throw UnsupportedOperationException(
                "Bluetooth LE Advertising not supported on this device.",
            )
        gattServer = bluetoothManager.openGattServer(applicationContext, gattServerCallback)
            ?: throw UnsupportedOperationException("gattServer is null, check Bluetooth is ON.")
        gattServerSession = adapterSession
    }

    private fun requireGattServer(): BluetoothGattServer {
        ensurePeripheralInitialized()
        return checkNotNull(gattServer) { "GATT server not available." }
    }

    override fun getAdvertisingState(): PeripheralAdvertisingState = advertisingState

    private fun hasRequiredPermissions(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        val hasAdvertise = ContextCompat.checkSelfPermission(
            applicationContext,
            Manifest.permission.BLUETOOTH_ADVERTISE,
        ) == PackageManager.PERMISSION_GRANTED
        val hasConnect = ContextCompat.checkSelfPermission(
            applicationContext,
            Manifest.permission.BLUETOOTH_CONNECT,
        ) == PackageManager.PERMISSION_GRANTED
        return hasAdvertise && hasConnect
    }

    override fun getReadinessState(): PeripheralReadinessState {
        val adapter = bluetoothManager.adapter ?: return PeripheralReadinessState.UNSUPPORTED
        if (!hasRequiredPermissions()) return PeripheralReadinessState.UNAUTHORIZED
        return try {
            if (!adapter.isEnabled) {
                PeripheralReadinessState.BLUETOOTH_OFF
            } else if (adapter.bluetoothLeAdvertiser == null) {
                PeripheralReadinessState.UNSUPPORTED
            } else {
                PeripheralReadinessState.READY
            }
        } catch (e: SecurityException) {
            PeripheralReadinessState.UNAUTHORIZED
        }
    }

    override fun addService(service: PeripheralService) {
        // The service is rebuilt per attempt: the characteristics of a refused
        // registration are not on the server and must not be reused.
        addServiceWithRetry(buildService = { service.toGattService() })
    }

    /**
     * Registers the service built by [buildService]. When a server left over
     * from a *previous* adapter session rejects the registration — the stack
     * dropped it without failing loudly (#384) — drop the cached server,
     * advertiser and per-server state, then retry once with a freshly built
     * service.
     *
     * A rejection on a server from the current session is not evidence that the
     * server is dead: Android refuses to register a service UUID it already
     * holds (hot restart, a duplicated `addService`), and re-opening the server
     * for that would unregister every other service, disconnect every client
     * and silently stop advertising. The retry therefore only runs when
     * [gattServerSession] is older than [adapterSession]. It happens once: a
     * genuine rejection still fails, with the error of the original attempt.
     *
     * [rejection] builds the error for a refused registration; tests inject it
     * to tell the original rejection from the retry's.
     */
    internal fun addServiceWithRetry(
        buildService: () -> BluetoothGattService,
        rejection: (String) -> IllegalStateException = ::IllegalStateException,
    ) {
        val rejected = registerService(buildService(), rejection) ?: return
        if (!isServerFromAPreviousAdapterSession()) {
            UniversalBleLogger.logError(
                "GATT server rejected a service; it belongs to the current adapter session, " +
                    "so it is kept as is",
            )
            throw rejected
        }
        UniversalBleLogger.logWarning(
            "A GATT server from a previous adapter session rejected a service, " +
                "re-opening it and retrying once",
        )
        resetPeripheralState("Bluetooth was restarted")
        // The retry can fail on its own, e.g. when the adapter disappears between
        // the two attempts and no server can be opened. The caller then still
        // gets the rejection that started the retry.
        val retried = kotlin.runCatching { registerService(buildService(), rejection) }
        retried.exceptionOrNull()?.let { retryFailure ->
            UniversalBleLogger.logWarning(
                "Retrying on a fresh GATT server failed: ${retryFailure.message}",
            )
            rejected.addSuppressed(retryFailure)
            throw rejected
        }
        if (retried.getOrNull() == null) return
        UniversalBleLogger.logError("GATT server rejected a service after re-opening it")
        throw rejected
    }

    /** Whether [gattServer] was opened before an adapter restart we observed. */
    private fun isServerFromAPreviousAdapterSession(): Boolean =
        gattServerSession in 0 until adapterSession

    /**
     * Adds [gattService] to the server, returning the rejection error built by
     * [rejection] or null on success. A rejected service's characteristics are
     * dropped from the caches so that a later registration of the same UUID
     * cannot resolve them.
     */
    private fun registerService(
        gattService: BluetoothGattService,
        rejection: (String) -> IllegalStateException,
    ): IllegalStateException? {
        if (requireGattServer().addService(gattService)) return null
        clearPeripheralCaches(gattService)
        return rejection("Service registration rejected")
    }

    override fun removeService(serviceId: String) {
        serviceId.findService()?.let { service ->
            val removed = dropNotifications { it.characteristic.service === service }
            settleNotifications(removed, IllegalStateException("Service removed"))
            // The service and its characteristics are no longer registered, so
            // nothing may keep resolving them: a later registration of the same
            // UUID would notify through these orphaned objects (#385). Done even
            // when the server call throws, so the caches never describe a
            // service the app believes to be gone.
            try {
                requireGattServer().removeService(service)
            } finally {
                clearPeripheralCaches(service)
            }
        }
    }

    override fun clearServices() {
        // Queued notifications are dropped before the caches that resolve their
        // characteristics, so none can be re-queued for services that are gone.
        clearPendingNotifications(null)
        val droppedInFlight = synchronized(pendingNotifications) {
            val current = notificationsInFlight.values.toList()
            notificationsInFlight.clear()
            current
        }
        settleNotifications(droppedInFlight, IllegalStateException("Services cleared"))
        try {
            requireGattServer().clearServices()
        } finally {
            clearPeripheralCaches()
        }
    }

    override fun getServices(): List<String> =
        runCatching {
            requireGattServer().services.map { it.uuid.toString() }
        }.getOrDefault(emptyList())

    override fun startAdvertising(
        services: List<String>,
        localName: String?,
        timeout: Long?,
        manufacturerData: UniversalManufacturerData?,
        platformConfig: PeripheralPlatformConfig?,
    ) {
        if (!hasRequiredPermissions()) {
            advertisingState = PeripheralAdvertisingState.ERROR
            callback.onAdvertisingStateChange(
                PeripheralAdvertisingState.ERROR,
                "Bluetooth permission not granted",
            ) {}
            throw SecurityException("Bluetooth permission not granted")
        }
        val isEnabled = try {
            bluetoothManager.isBluetoothEnabled()
        } catch (e: SecurityException) {
            advertisingState = PeripheralAdvertisingState.ERROR
            callback.onAdvertisingStateChange(
                PeripheralAdvertisingState.ERROR,
                "Bluetooth permission not granted",
            ) {}
            throw e
        }
        if (!isEnabled) {
            advertisingState = PeripheralAdvertisingState.ERROR
            callback.onAdvertisingStateChange(
                PeripheralAdvertisingState.ERROR,
                "Bluetooth is not enabled",
            ) {}
            activity?.let { promptEnableBluetooth(it) }
            throw Exception("Bluetooth is not enabled")
        }
        isEnableBluetoothPromptPending = false
        ensurePeripheralInitialized()
        advertisingState = PeripheralAdvertisingState.STARTING
        callback.onAdvertisingStateChange(PeripheralAdvertisingState.STARTING, null) {}

        handler.post {
            val adapter = bluetoothManager.adapter
            if (localName != null && adapter != null && adapter.name != localName) {
                if (!adapterNameOverridden) {
                    originalAdapterName = adapter.name
                }
                adapter.name = localName
                adapterNameOverridden = true
            }
            val advertiseSettings = AdvertiseSettings.Builder()
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
                .setConnectable(true)
                .setTimeout(timeout?.toInt() ?: 0)
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                .build()

            val addServicesInScanResponse =
                platformConfig?.android?.addServicesInScanResponse == true
            val addManufacturerDataInScanResponse =
                platformConfig?.android?.addManufacturerDataInScanResponse == true

            val advertiseDataBuilder = AdvertiseData.Builder()
                .setIncludeTxPowerLevel(false)
                .setIncludeDeviceName(localName != null)
            val scanResponseBuilder = AdvertiseData.Builder()
                .setIncludeTxPowerLevel(false)
                .setIncludeDeviceName(false)

            val msdBuilder =
                if (addManufacturerDataInScanResponse) scanResponseBuilder else advertiseDataBuilder
            manufacturerData?.let {
                msdBuilder.addManufacturerData(
                    it.companyIdentifier.toInt(),
                    it.data,
                )
            }

            val servicesBuilder =
                if (addServicesInScanResponse) scanResponseBuilder else advertiseDataBuilder
            services.forEach { servicesBuilder.addServiceUuid(ParcelUuid.fromString(it)) }

            bluetoothLeAdvertiser?.startAdvertising(
                advertiseSettings,
                advertiseDataBuilder.build(),
                scanResponseBuilder.build(),
                advertiseCallback,
            )
        }
    }

    override fun stopAdvertising() {
        if (advertisingState == PeripheralAdvertisingState.IDLE && bluetoothLeAdvertiser == null) {
            return
        }
        advertisingState = PeripheralAdvertisingState.STOPPING
        callback.onAdvertisingStateChange(PeripheralAdvertisingState.STOPPING, null) {}
        handler.post {
            kotlin.runCatching { bluetoothLeAdvertiser?.stopAdvertising(advertiseCallback) }
            restoreAdapterNameIfNeeded()
            advertisingState = PeripheralAdvertisingState.IDLE
            callback.onAdvertisingStateChange(PeripheralAdvertisingState.IDLE, null) {}
        }
    }

    override fun updateCharacteristic(
        characteristicId: String,
        characteristicInstanceId: String?,
        value: ByteArray,
        deviceId: String?,
        callback: (Result<Unit>) -> Unit,
    ) {
        // A failure or an empty subscriber set completes immediately; when there
        // is something to notify, the callback fires once every target client's
        // notification has settled.
        val characteristic: BluetoothGattCharacteristic
        val targetDevices: List<BluetoothDevice>
        try {
            requireGattServer()
            characteristic =
                characteristicId.findGattCharacteristic(characteristicInstanceId)
                    ?: throw Exception("Characteristic not found")
            targetDevices = synchronized(bluetoothDevicesMap) {
                if (deviceId != null) {
                    val dev = bluetoothDevicesMap[deviceId]
                        ?: bluetoothDevicesMap[deviceId.uppercase()]
                        ?: bluetoothDevicesMap[deviceId.lowercase()]
                        ?: throw Exception("Device not found")
                    listOf(dev)
                } else {
                    bluetoothDevicesMap.values.toList()
                }
            }
        } catch (e: Throwable) {
            callback(Result.failure(e))
            return
        }
        val indicate =
            (characteristic.properties and BluetoothGattCharacteristic.PROPERTY_INDICATE) != 0
        // Resolved before taking pendingNotifications: isSubscribed takes
        // subscribedCharDevicesMap, and the descriptor/cleanup paths take those two
        // monitors in the opposite order, so nesting them here would deadlock.
        val subscribedDevices = targetDevices.filter { isSubscribed(it.address, characteristic) }
        if (subscribedDevices.isEmpty()) {
            // Nobody to notify: the value is only the static one a read returns.
            // Written under this monitor so it cannot land between another
            // drain's value assignment and its notify call.
            synchronized(pendingNotifications) {
                @Suppress("DEPRECATION")
                characteristic.value = value.copyOf()
            }
            callback(Result.success(Unit))
            return
        }
        val remaining = AtomicInteger(subscribedDevices.size)
        val firstError = AtomicReference<Throwable?>(null)
        val settleOne: (Throwable?) -> Unit = { error ->
            if (error != null) firstError.compareAndSet(null, error)
            if (remaining.decrementAndGet() == 0) {
                val err = firstError.get()
                if (err != null) callback(Result.failure(err)) else callback(Result.success(Unit))
            }
        }
        // Assigning characteristic.value here would race the packet already in
        // flight (#403): the value is applied per packet in drainNotifications.
        synchronized(pendingNotifications) {
            subscribedDevices.forEach { device ->
                pendingNotifications.addLast(
                    PendingNotification(device, characteristic, value.copyOf(), indicate, settleOne)
                )
            }
            subscribedDevices.forEach { drainNotifications(it.address) }
        }
    }

    private fun isSubscribed(deviceAddress: String, characteristic: BluetoothGattCharacteristic): Boolean {
        val subscriptionId = characteristic.instanceId() ?: characteristic.uuid.toString()
        return synchronized(subscribedCharDevicesMap) {
            subscribedCharDevicesMap[deviceAddress]?.any { it.equals(subscriptionId, ignoreCase = true) } == true
        }
    }

    private fun drainNotifications(deviceAddress: String) {
        // Everything the packet owns is done under one monitor (#403): a second
        // update submitted while this one is in flight must neither dequeue it
        // nor overwrite the value the stack is about to send.
        synchronized(pendingNotifications) {
            if (notificationsInFlight.containsKey(deviceAddress)) return
            val index = pendingNotifications.indexOfFirst { it.device.address == deviceAddress }
            if (index < 0) return
            val next = pendingNotifications.removeAt(index)
            val server = gattServer ?: run {
                pendingNotifications.addFirst(next)
                return
            }
            notificationsInFlight[deviceAddress] = next
            // The in-flight check, the dequeue, the value assignment and the send
            // all happen under this monitor. Below API 33 the value is carried by
            // the shared characteristic, so another thread writing it in between
            // would transmit the wrong chunk (#403).
            val sent = kotlin.runCatching {
                @Suppress("DEPRECATION")
                next.characteristic.value = next.value
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    server.notifyCharacteristicChanged(
                        next.device,
                        next.characteristic,
                        next.indicate,
                        next.value,
                    ) == BluetoothStatusCodes.SUCCESS
                } else {
                    @Suppress("DEPRECATION")
                    server.notifyCharacteristicChanged(next.device, next.characteristic, next.indicate)
                }
            }.getOrDefault(false)
            if (!sent) {
                // Native queue still busy. Put the payload back at the front and
                // wait for onNotificationSent to retry; never drop a release.
                notificationsInFlight.remove(deviceAddress)
                pendingNotifications.addFirst(next)
            }
        }
    }

    /**
     * Settles the packet [BluetoothGattServerCallback.onNotificationSent] reports
     * and starts the next queued one. Runs on a binder thread, so the settlement
     * itself is posted to [handler]. Internal so the unit tests can drive it.
     */
    internal fun handleNotificationSent(device: BluetoothDevice, status: Int) {
        val address = device.address
        val completed = synchronized(pendingNotifications) {
            notificationsInFlight.remove(address)
        }
        // Queue the settlement before the next packet can be handed to the
        // stack, so two updates for the same client complete in submission
        // order. Posting never invokes the reply here.
        if (completed != null) {
            val error = if (status == BluetoothGatt.GATT_SUCCESS) null
            else IllegalStateException("Notification failed with status $status")
            settleNotifications(listOf(completed), error)
        }
        drainNotifications(address)
    }

    override fun clearPendingNotifications(deviceId: String?) {
        // In-flight packets are already owned by Android. Keep their busy
        // markers until onNotificationSent, so a neutral cannot overtake them.
        val removed = if (deviceId == null) {
            dropNotifications(includeInFlight = false) { true }
        } else {
            dropNotifications(includeInFlight = false) {
                it.device.address.equals(deviceId, ignoreCase = true)
            }
        }
        settleNotifications(removed, IllegalStateException("Notification cancelled"))
    }

    override fun getSubscribedClients(
        characteristicId: String,
        characteristicInstanceId: String?,
    ): List<String> {
        val targetInstanceId = characteristicInstanceId
            ?: characteristicId.findGattCharacteristic()?.instanceId()
        synchronized(subscribedCharDevicesMap) {
            return subscribedCharDevicesMap.entries
                .filter { (_, chars) ->
                    chars.any { subscribed ->
                        if (targetInstanceId != null) {
                            subscribed.equals(targetInstanceId, ignoreCase = true)
                        } else {
                            subscribed.equals(characteristicId, ignoreCase = true)
                        }
                    }
                }
                .map { it.key }
        }
    }

    override fun getMaximumNotifyLength(deviceId: String): Long? {
        val mtu = synchronized(mtuByDeviceId) { mtuByDeviceId[deviceId] } ?: return null
        return (mtu - 3).coerceAtLeast(0).toLong()
    }

    override fun setAutoConnect(autoConnect: Boolean) {
        this.autoConnect = autoConnect
    }

    private fun onConnectionUpdate(device: BluetoothDevice, status: Int, newState: Int) {
        Log.e(TAG, "onConnectionStateChange: $status -> $newState")
        handler.post {
            callback.onConnectionStateChange(
                device.address,
                newState == BluetoothProfile.STATE_CONNECTED,
            ) {}
        }
        if (newState == BluetoothProfile.STATE_DISCONNECTED) cleanConnection(device)
    }

    private fun cleanConnection(device: BluetoothDevice) {
        val deviceAddress = device.address
        val subscribedCharUUID = synchronized(subscribedCharDevicesMap) {
            val current = subscribedCharDevicesMap[deviceAddress]?.toList() ?: emptyList()
            subscribedCharDevicesMap.remove(deviceAddress)
            current
        }
        subscribedCharUUID.forEach { subscribedId ->
            val characteristic = subscribedId.findGattCharacteristic()
            handler.post {
                callback.onCharacteristicSubscriptionChange(
                    deviceAddress,
                    characteristic?.uuid?.toString() ?: subscribedId,
                    characteristic?.instanceId(),
                    false,
                    device.name,
                ) {}
            }
        }
        val removed = dropNotifications { it.device.address == deviceAddress }
        settleNotifications(removed, IllegalStateException("Device disconnected"))
    }

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartFailure(errorCode: Int) {
            super.onStartFailure(errorCode)
            handler.post {
                restoreAdapterNameIfNeeded()
                val errorMessage = when (errorCode) {
                    ADVERTISE_FAILED_ALREADY_STARTED -> "Already started"
                    ADVERTISE_FAILED_DATA_TOO_LARGE -> "Data too large"
                    ADVERTISE_FAILED_FEATURE_UNSUPPORTED -> "Feature unsupported"
                    ADVERTISE_FAILED_INTERNAL_ERROR -> "Internal error"
                    ADVERTISE_FAILED_TOO_MANY_ADVERTISERS -> "Too many advertisers"
                    else -> "Failed to start advertising: $errorCode"
                }
                advertisingState = PeripheralAdvertisingState.ERROR
                callback.onAdvertisingStateChange(PeripheralAdvertisingState.ERROR, errorMessage) {}
            }
        }

        override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
            super.onStartSuccess(settingsInEffect)
            advertisingState = PeripheralAdvertisingState.ADVERTISING
            handler.post {
                callback.onAdvertisingStateChange(PeripheralAdvertisingState.ADVERTISING, null) {}
            }
        }
    }

    private val gattServerCallback = object : BluetoothGattServerCallback() {
        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            super.onConnectionStateChange(device, status, newState)
            when (newState) {
                BluetoothProfile.STATE_CONNECTED -> {
                    synchronized(bluetoothDevicesMap) {
                        bluetoothDevicesMap[device.address] = device
                    }
                    handler.post { gattServer?.connect(device, autoConnect) }
                    onConnectionUpdate(device, status, newState)
                }

                BluetoothProfile.STATE_DISCONNECTED -> {
                    synchronized(bluetoothDevicesMap) {
                        bluetoothDevicesMap.remove(device.address)
                    }
                    onConnectionUpdate(device, status, newState)
                }
            }
        }

        override fun onMtuChanged(device: BluetoothDevice?, mtu: Int) {
            super.onMtuChanged(device, mtu)
            device?.address?.let { address ->
                synchronized(mtuByDeviceId) { mtuByDeviceId[address] = mtu }
                handler.post { callback.onMtuChange(address, mtu.toLong()) {} }
            }
        }

        override fun onNotificationSent(device: BluetoothDevice, status: Int) {
            super.onNotificationSent(device, status)
            handleNotificationSent(device, status)
        }

        override fun onCharacteristicReadRequest(
            device: BluetoothDevice,
            requestId: Int,
            offset: Int,
            characteristic: BluetoothGattCharacteristic,
        ) {
            super.onCharacteristicReadRequest(device, requestId, offset, characteristic)
            if (gattServer == null) return
            handler.post {
                callback.onReadRequest(
                    deviceIdArg = device.address,
                    characteristicIdArg = characteristic.uuid.toString(),
                    characteristicInstanceIdArg = characteristic.instanceId(),
                    offsetArg = offset.toLong(),
                    valueArg = characteristic.value,
                ) { result ->
                    val readResult = result.getOrNull()
                    if (readResult == null) {
                        val configured = characteristic.value
                        if (configured == null) {
                            gattServer?.sendResponse(
                                device, requestId, BluetoothGatt.GATT_FAILURE, 0, emptyBytes,
                            )
                        } else {
                            gattServer?.sendResponse(
                                device,
                                requestId,
                                BluetoothGatt.GATT_SUCCESS,
                                offset,
                                offsetSuffix(configured, offset),
                            )
                        }
                    } else {
                        gattServer?.sendResponse(
                            device,
                            requestId,
                            readResult.status?.toInt() ?: BluetoothGatt.GATT_SUCCESS,
                            readResult.offset?.toInt() ?: 0,
                            readResult.value,
                        )
                    }
                }
            }
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray,
        ) {
            super.onCharacteristicWriteRequest(
                device, requestId, characteristic, preparedWrite, responseNeeded, offset, value,
            )
            handler.post {
                callback.onWriteRequest(
                    deviceIdArg = device.address,
                    characteristicIdArg = characteristic.uuid.toString(),
                    characteristicInstanceIdArg = characteristic.instanceId(),
                    offsetArg = offset.toLong(),
                    valueArg = value,
                ) { writeResponse ->
                    val writeResult = writeResponse.getOrNull()
                    if (responseNeeded) {
                        gattServer?.sendResponse(
                            device,
                            requestId,
                            writeResult?.status?.toInt() ?: BluetoothGatt.GATT_SUCCESS,
                            writeResult?.offset?.toInt() ?: 0,
                            writeResult?.value ?: emptyBytes,
                        )
                    }
                }
            }
        }

        override fun onServiceAdded(status: Int, service: BluetoothGattService) {
            super.onServiceAdded(status, service)
            val error = if (status != BluetoothGatt.GATT_SUCCESS) "Adding Service failed" else null
            handler.post { callback.onServiceAdded(service.uuid.toString(), error) {} }
        }

        override fun onDescriptorReadRequest(
            device: BluetoothDevice,
            requestId: Int,
            offset: Int,
            descriptor: BluetoothGattDescriptor,
        ) {
            super.onDescriptorReadRequest(device, requestId, offset, descriptor)
            handler.post {
                callback.onDescriptorReadRequest(
                    deviceIdArg = device.address,
                    characteristicIdArg = descriptor.characteristic.uuid.toString(),
                    characteristicInstanceIdArg = descriptor.characteristic.instanceId(),
                    descriptorIdArg = descriptor.uuid.toString(),
                    offsetArg = offset.toLong(),
                    valueArg = descriptor.getClientValue(device.address),
                ) { result ->
                    val readResult = result.getOrNull()
                    if (readResult == null) {
                        val configured = descriptor.getClientValue(device.address)
                        if (configured == null) {
                            gattServer?.sendResponse(
                                device,
                                requestId,
                                BluetoothGatt.GATT_FAILURE,
                                offset,
                                emptyBytes,
                            )
                        } else {
                            gattServer?.sendResponse(
                                device,
                                requestId,
                                BluetoothGatt.GATT_SUCCESS,
                                offset,
                                offsetSuffix(configured, offset),
                            )
                        }
                    } else {
                        gattServer?.sendResponse(
                            device,
                            requestId,
                            readResult.status?.toInt() ?: BluetoothGatt.GATT_SUCCESS,
                            readResult.offset?.toInt() ?: offset,
                            readResult.value,
                        )
                    }
                }
            }
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray?,
        ) {
            super.onDescriptorWriteRequest(
                device, requestId, descriptor, preparedWrite, responseNeeded, offset, value,
            )
            descriptor.value = value
            descriptor.storeClientValue(device?.address, value)
            if (descriptor.uuid.toString().lowercase() == peripheralDescriptorCCUUID.lowercase()) {
                val isSubscribed =
                    BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE.contentEquals(value) ||
                            BluetoothGattDescriptor.ENABLE_INDICATION_VALUE.contentEquals(value)
                val characteristic = descriptor.characteristic
                val subscriptionId =
                    characteristic.instanceId() ?: characteristic.uuid.toString()
                device?.address?.let { address ->
                    handler.post {
                        callback.onCharacteristicSubscriptionChange(
                            address,
                            characteristic.uuid.toString(),
                            characteristic.instanceId(),
                            isSubscribed,
                            device.name,
                        ) {}
                    }
                    synchronized(subscribedCharDevicesMap) {
                        val charSet = subscribedCharDevicesMap.getOrPut(address) { mutableSetOf() }
                        if (isSubscribed) {
                            charSet.add(subscriptionId)
                        } else {
                            charSet.remove(subscriptionId)
                        }
                    }
                    if (!isSubscribed) {
                        val removed = dropNotifications {
                            it.device.address == address && it.characteristic === characteristic
                        }
                        settleNotifications(removed, IllegalStateException("Central unsubscribed"))
                    }
                }
            }
            if (responseNeeded) {
                handler.post {
                    callback.onDescriptorWriteRequest(
                        deviceIdArg = device?.address ?: "",
                        characteristicIdArg = descriptor.characteristic.uuid.toString(),
                        characteristicInstanceIdArg = descriptor.characteristic.instanceId(),
                        descriptorIdArg = descriptor.uuid.toString(),
                        offsetArg = offset.toLong(),
                        valueArg = value,
                    ) { writeResponse ->
                        val writeResult = writeResponse.getOrNull()
                        gattServer?.sendResponse(
                            device,
                            requestId,
                            writeResult?.status?.toInt() ?: BluetoothGatt.GATT_SUCCESS,
                            writeResult?.offset?.toInt() ?: offset,
                            writeResult?.value ?: value ?: emptyBytes,
                        )
                    }
                }
            }
        }
    }

    /**
     * Restores the adapter name a [startAdvertising] call overrode. The override
     * is only forgotten once the write succeeded: it now also runs while
     * Bluetooth is turning off, where the write legitimately fails, and the next
     * [BluetoothAdapter.STATE_ON] retries it. Leaving the flags set would make
     * the next local name look like it was already saved.
     */
    private fun restoreAdapterNameIfNeeded() {
        if (!adapterNameOverridden) return
        val adapter = bluetoothManager.adapter ?: return
        val name = originalAdapterName
        if (name == null) {
            // There was no original name to write back.
            adapterNameOverridden = false
            return
        }
        val restored = kotlin.runCatching { adapter.setName(name) }.getOrDefault(false)
        if (!restored) {
            UniversalBleLogger.logWarning(
                "Failed to restore the adapter name to \"$name\", retrying on the next STATE_ON",
            )
            return
        }
        adapterNameOverridden = false
        originalAdapterName = null
    }
}
