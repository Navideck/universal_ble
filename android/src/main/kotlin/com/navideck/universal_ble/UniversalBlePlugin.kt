package com.navideck.universal_ble

import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry
import java.util.UUID
import java.util.WeakHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import androidx.core.content.edit

// Bluetooth Core caps an attribute value at 512 bytes. Android 15+ throws
// IllegalArgumentException from writeCharacteristic(characteristic, value,
// writeType) for a longer value; writeDescriptor does not length-check, so the
// guard there only turns a value that cannot work into a clear error. Reject
// them with a classified error instead of letting the exception escape with the
// pending result still registered, which made every later write complete one
// behind.
private const val MAX_ATTRIBUTE_VALUE_SIZE = 512

@SuppressLint("MissingPermission")
class UniversalBlePlugin : UniversalBlePlatformChannel, BluetoothGattCallback(), FlutterPlugin,
    UniversalBleAndroidChannel,
    ActivityAware, PluginRegistry.ActivityResultListener,
    PluginRegistry.RequestPermissionsResultListener {
    private val bluetoothEnableRequestCode = 2342313
    private val bluetoothDisableRequestCode = 2342414
    private val permissionRequestCode = 2342515
    private val advertisePermissionRequestCode = 2342616
    private var permissionHandler: PermissionHandler? = null
    private var callbackChannel: UniversalBleCallbackChannel? = null

    // Read on Bluetooth binder threads (from GATT callbacks) but assigned on the
    // main thread in onAttachedToEngine/onDetachedFromEngine; @Volatile makes
    // those writes visible so a binder thread never sees a stale null and drops
    // a completion.
    @Volatile
    private var mainThreadHandler: Handler? = null
    private lateinit var context: Context
    private var activity: Activity? = null
    private lateinit var bluetoothManager: BluetoothManager
    private lateinit var safeScanner: SafeScanner
    private val cachedServicesMap = mutableMapOf<String, List<String>>()
    private val universalBleFilterUtil = UniversalBleFilterUtil()
    private lateinit var peripheralPlugin: UniversalBlePeripheralPlugin

    // Flutter Futures
    private var bluetoothEnableRequestFuture: ((Result<Boolean>) -> Unit)? = null
    private var bluetoothDisableRequestFuture: ((Result<Boolean>) -> Unit)? = null
    private val discoveryOperations = pendingOperations<DiscoverServicesFuture>("Discover services")
    private val mtuOperations = pendingOperations<MtuResultFuture>("MTU")
    // Protected by mtuOperations' lock. An observed MTU belongs to this GATT
    // client, never to a later connection using the same device address.
    private val negotiatedMtus = WeakHashMap<BluetoothGatt, Int>()
    private val readOperations = pendingOperations<ReadResultFuture>("Read")
    private val writeOperations = pendingOperations<WriteResultFuture>("Write")
    private val descriptorReadOperations =
        pendingOperations<ReadDescriptorResultFuture>("Read descriptor")
    private val descriptorWriteOperations =
        pendingOperations<WriteDescriptorResultFuture>("Write descriptor")
    private val subscriptionOperations =
        pendingOperations<SubscriptionResultFuture>("Subscription")
    private val pairResultFutures = mutableMapOf<String, (Result<Boolean>) -> Unit>()

    // Addresses seen go through BOND_BONDING. A return to BOND_NONE while an address is in here is a
    // failed/declined bond (an event), not a steady BOND_NONE, so onBondStateUpdate() marks it as a failure
    // instead of letting Dart's pairing-state dedup swallow it (#325).
    private val bondingAttempts = mutableSetOf<String>()
    private val rssiOperations = pendingOperations<RssiResultFuture>("RSSI")

    // Per plugin instance (one per FlutterEngine): the GATT clients this engine
    // owns and the link state of each (see [GattRegistry]). A connect() here
    // never reuses a client from another engine, and detach releases only this
    // engine's clients.
    private val gattRegistry = GattRegistry()

    /**
     * When enabled, close every known GATT client on engine detach. The
     * plugin otherwise leaves GATT open, so a killed app keeps the
     * peripheral occupied until its supervision timeout.
     */
    private var closeGattOnDetach = false

    private val gattCloseTimeoutMs = 1500L

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        mainThreadHandler = Handler(Looper.getMainLooper())
        permissionHandler = PermissionHandler(
            context,
            permissionRequestCode,
            advertisePermissionRequestCode,
        )
        bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        safeScanner = SafeScanner(bluetoothManager)

        UniversalBlePlatformChannel.setUp(flutterPluginBinding.binaryMessenger, this)
        UniversalBleAndroidChannel.setUp(flutterPluginBinding.binaryMessenger, this)
        peripheralPlugin = UniversalBlePeripheralPlugin(
            flutterPluginBinding.applicationContext,
            bluetoothManager,
            flutterPluginBinding.binaryMessenger
        )
        UniversalBlePeripheralChannel.setUp(flutterPluginBinding.binaryMessenger, peripheralPlugin)
        callbackChannel = UniversalBleCallbackChannel(flutterPluginBinding.binaryMessenger)


        val intentFilter = IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED)
        intentFilter.addAction(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
        context.registerReceiverCompat(broadcastReceiver, intentFilter, exported = true)
        cachedServicesMap.putAll(getCachedServicesMap())
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // Release only the clients this engine created. The snapshot avoids mutating
        // the map while clients are released.
        if (closeGattOnDetach) gattRegistry.snapshot().forEach { cleanConnection(it.gatt) }
        // A detached engine may have no adapter; a null one must not abort the
        // teardown before the receiver and the peripheral plugin are released.
        bluetoothManager.adapter?.bluetoothLeScanner?.stopScan(scanCallback)
        context.unregisterReceiver(broadcastReceiver)
        peripheralPlugin.dispose()
        UniversalBlePeripheralChannel.setUp(binding.binaryMessenger, null)
        UniversalBleAndroidChannel.setUp(binding.binaryMessenger, null)
        callbackChannel = null
        mainThreadHandler = null
        permissionHandler = null
    }

    override fun getBluetoothAvailabilityState(callback: (Result<AvailabilityState>) -> Unit) {
        callback(
            Result.success(
                bluetoothManager.adapter?.state?.toAvailabilityState()
                    ?: AvailabilityState.UNKNOWN
            )
        )
    }

    override fun hasPermissions(withAndroidFineLocation: Boolean): Boolean {
        return permissionHandler?.hasPermissions(withAndroidFineLocation) ?: false
    }

    override fun requestPermissions(
        withAndroidFineLocation: Boolean,
        callback: (Result<Unit>) -> Unit,
    ) {
        if (permissionHandler == null) {
            callback(
                Result.failure(
                    createFlutterError(
                        UniversalBleErrorCode.FAILED,
                        "PermissionHandler is not initialized"
                    )
                )
            )
        }
        permissionHandler?.requestPermissions(withAndroidFineLocation, callback)
    }

    override fun enableBluetooth(callback: (Result<Boolean>) -> Unit) {
        if (bluetoothManager.adapter.isEnabled) {
            callback(Result.success(true))
            return
        }
        if (bluetoothEnableRequestFuture != null) {
            callback(
                Result.failure(
                    createFlutterError(
                        UniversalBleErrorCode.OPERATION_IN_PROGRESS,
                        "Bluetooth enable request in progress"
                    )
                )
            )
            return
        }
        val enableBtIntent = Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)
        activity?.startActivityForResult(enableBtIntent, bluetoothEnableRequestCode)
        bluetoothEnableRequestFuture = callback
    }

    override fun disableBluetooth(callback: (Result<Boolean>) -> Unit) {
        if (!bluetoothManager.adapter.isEnabled) {
            callback(Result.success(true))
            return
        }
        if (bluetoothDisableRequestFuture != null) {
            callback(
                Result.failure(
                    createFlutterError(
                        UniversalBleErrorCode.OPERATION_IN_PROGRESS,
                        "Bluetooth disable request in progress"
                    )
                )
            )
            return
        }
        val disableBtIntent = Intent("android.bluetooth.adapter.action.REQUEST_DISABLE")
        activity?.startActivityForResult(disableBtIntent, bluetoothDisableRequestCode)
        bluetoothDisableRequestFuture = callback
    }

    override fun startScan(filter: UniversalScanFilter?, config: UniversalScanConfig?) {
        if (!isBluetoothAvailable()) throw createFlutterError(
            UniversalBleErrorCode.BLUETOOTH_NOT_ENABLED,
            "Bluetooth not enabled"
        )

        val builder = ScanSettings.Builder()
        val legacy = config?.android?.legacy
        config?.android?.let { androidConfig ->
            androidConfig.scanMode?.parse()?.let { scanMode ->
                builder.setScanMode(scanMode)
            }
            androidConfig.reportDelayMillis?.let { reportDelay ->
                builder.setReportDelay(reportDelay)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                androidConfig.callbackType?.let { types ->
                    val combined = types.mapNotNull { it.parse() }.fold(0) { acc, v -> acc or v }
                    if (combined != 0) builder.setCallbackType(combined)
                }
                androidConfig.matchMode?.parse()?.let { builder.setMatchMode(it) }
                androidConfig.numOfMatches?.parse()?.let { builder.setNumOfMatches(it) }

                // Battery-friendly de-duplication: report only the first match per
                // device (mirrors iOS's CBCentralManagerScanOptionAllowDuplicatesKey
                // = false) unless the caller overrode callbackType. First-match
                // filtering is offloaded to the controller, so only request it when
                // the adapter supports it; otherwise startScan() fails with
                // SCAN_FAILED_FEATURE_UNSUPPORTED (and the failure is only logged).
                // The Dart layer de-duplicates regardless of this native lever.
                if (config?.skipDuplicates == true &&
                    androidConfig.callbackType == null &&
                    supportsFirstMatchScan()
                ) {
                    builder.setCallbackType(ScanSettings.CALLBACK_TYPE_FIRST_MATCH)
                }
            }
        }
        if (Build.VERSION.SDK_INT >= 26) {
            if (legacy == true) {
                builder.setLegacy(true)
            } else {
                builder.setPhy(ScanSettings.PHY_LE_ALL_SUPPORTED)
                builder.setLegacy(false)
            }
        }
        val settings = builder.build()

        val usesCustomFilters = filter?.usesCustomFilters() ?: false

        try {
            val filterServices = filter?.withServices?.toUUIDList() ?: emptyList()
            var scanFilters = emptyList<ScanFilter>()

            // Set custom scan filter only if required
            if (usesCustomFilters) {
                UniversalBleLogger.logError("Using Custom Filters")
                universalBleFilterUtil.configure(filter)
            } else {
                universalBleFilterUtil.configure(null)
                scanFilters = filter?.toScanFilters(filterServices) ?: emptyList()
            }

            safeScanner.startScan(
                scanFilters, settings, scanCallback
            )
        } catch (e: Exception) {
            throw createFlutterError(
                UniversalBleErrorCode.FAILED,
                "Failed to start Scan",
                details = e.toString()
            )
        }
    }

    override fun stopScan() {
        if (!isBluetoothAvailable()) throw createFlutterError(
            UniversalBleErrorCode.BLUETOOTH_NOT_ENABLED,
            "Bluetooth not enabled"
        )
        // check if already scanning
        safeScanner.stopScan(scanCallback)
    }

    override fun isScanning(): Boolean {
        return safeScanner.isScanning()
    }

    override fun requestDevice(
        options: AppleAccessorySetupOptions,
        callback: (Result<UniversalDevicePickerResult>) -> Unit,
    ) {
        callback(
            Result.failure(
                createFlutterError(
                    UniversalBleErrorCode.NOT_SUPPORTED,
                    "AccessorySetupKit is only supported on iOS 18+",
                )
            )
        )
    }

    override fun connect(
        deviceId: String,
        autoConnect: Boolean?,
        platformConfig: ConnectionPlatformConfig?,
    ) {
        platformConfig?.android?.closeGattOnDetach?.let { closeGattOnDetach = it }

        val shouldAutoConnect = autoConnect ?: false

        // Note: platformConfig carries platform-specific connection options
        // If already connected, send connected message,
        // if connecting, do nothing
        val replaced = gattRegistry.find(deviceId)
        replaced?.let { existing ->
            val currentState =
                bluetoothManager.getConnectionState(existing.gatt.device, BluetoothProfile.GATT)
            if (currentState == BluetoothGatt.STATE_CONNECTED) {
                UniversalBleLogger.logError("$deviceId Already connected")
                mainThreadHandler?.post {
                    callbackChannel?.onConnectionChanged(deviceId, true, null, null, null) {}
                }
                return
            } else if (currentState == BluetoothGatt.STATE_CONNECTING) {
                throw createFlutterError(
                    UniversalBleErrorCode.CONNECTION_IN_PROGRESS,
                    "Connection already in progress"
                )
            }
        }

        val remoteDevice = bluetoothManager.adapter.getRemoteDevice(deviceId)
        val gatt = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            remoteDevice.connectGatt(
                context,
                shouldAutoConnect,
                this,
                BluetoothDevice.TRANSPORT_LE
            )
        } else {
            remoteDevice.connectGatt(context, shouldAutoConnect, this)
        }
        gattRegistry.put(gatt, shouldAutoConnect)
        // The client this one replaces cannot report the new link, and its own
        // link is down (a connected or connecting one returned above), so tear
        // it down here. Leaving it open would keep a tracked client — and an
        // autoConnect attempt Android never stops — that nothing would ever
        // close.
        if (replaced != null && replaced.gatt !== gatt) cleanConnection(replaced.gatt)
    }

    override fun disconnect(deviceId: String) {
        val client = gattRegistry.find(deviceId)
        if (client == null) {
            cleanUpConnection(deviceId)
            mainThreadHandler?.post {
                callbackChannel?.onConnectionChanged(deviceId, false, null, null, null) {}
            }
        } else {
            // cleanConnection() also cancels the client's autoConnect, so an
            // explicit disconnect is not followed by an automatic reconnect.
            cleanConnection(client.gatt)
        }
    }

    override fun getConnectionState(deviceId: String): BleConnectionState {
        try {
            val connectionState = bluetoothManager.getConnectionState(
                bluetoothManager.adapter.getRemoteDevice(deviceId),
                BluetoothProfile.GATT
            )
            return if (gattRegistry.isKnown(deviceId) || connectionState == BluetoothGatt.STATE_DISCONNECTED || connectionState == BluetoothGatt.STATE_DISCONNECTING) {
                connectionState.toBleConnectionState()
            } else {
                // Might be connected with device, but not with app
                UniversalBleLogger.logError("Device might be connected but not known to this app")
                BleConnectionState.DISCONNECTED
            }
        } catch (_: Exception) {
            return BleConnectionState.DISCONNECTED
        }
    }

    override fun setLogLevel(logLevel: BleLogLevel) {
        UniversalBleLogger.setLogLevel(logLevel)
    }

    override fun hasBluetoothAdvertisePermission(): Boolean {
        return permissionHandler?.hasBluetoothAdvertisePermission() ?: false
    }

    override fun requestBluetoothAdvertisePermission(callback: (Result<Boolean>) -> Unit) {
        val handler = permissionHandler
        if (handler == null) {
            callback(
                Result.failure(
                    createFlutterError(
                        UniversalBleErrorCode.FAILED,
                        "PermissionHandler is not initialized",
                    ),
                ),
            )
            return
        }
        handler.requestBluetoothAdvertisePermission(callback)
    }

    override fun readRssi(deviceId: String, callback: (Result<Long>) -> Unit) {
        try {
            val gatt = gattRegistry.get(deviceId).gatt
            // Register before readRemoteRssi, as readValue does: its callback
            // arrives on a binder thread, so the entry must already be in the
            // collection the disconnect cleanup sweeps — and only while the link
            // is up (#394).
            val future = RssiResultFuture(gatt, deviceId, callback)
            if (!rssiOperations.addIfLinkedUp(gatt, future, ::isLinkUp)) {
                callback(Result.failure(deviceDisconnectedError()))
                return
            }
            val started = try {
                gatt.readRemoteRssi()
            } catch (e: Exception) {
                // A callback or disconnect may already own the reply.
                if (!rssiOperations.remove(future)) return
                throw e
            }
            if (!started) {
                if (!rssiOperations.remove(future)) return
                callback(
                    Result.failure(
                        createFlutterError(
                            UniversalBleErrorCode.FAILED,
                            "Failed to read RSSI"
                        )
                    )
                )
            }
        } catch (e: FlutterError) {
            callback(Result.failure(e))
        }
    }

    override fun onReadRemoteRssi(gatt: BluetoothGatt?, rssi: Int, status: Int) {
        val deviceId = gatt?.device?.address ?: return
        // Runs on a binder thread: match and remove under the lock, then
        // complete on the main thread (platform-channel replies must be sent
        // there). Every readRemoteRssi() has its own response, so this callback
        // belongs to the oldest pending request only — completing every match
        // would report one reading to a request still in flight.
        val future = rssiOperations.takeOldest { it.gatt === gatt }
        if (future == null) {
            return
        }
        postToMainLooper {
            try {
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    future.result(Result.success(rssi.toLong()))
                } else {
                    future.result(
                        Result.failure(
                            createFlutterError(
                                UniversalBleErrorCode.FAILED,
                                "Failed to read RSSI"
                            )
                        )
                    )
                }
            } catch (e: Exception) {
                UniversalBleLogger.logError("RSSI completion delivery failed: $e")
            }
        }
    }

    override fun discoverServices(
        deviceId: String,
        withDescriptors: Boolean,
        platformConfig: DiscoverServicesPlatformConfig?,
        callback: (Result<List<UniversalBleService>>) -> Unit,
    ) {
        try {
            val gatt = gattRegistry.get(deviceId).gatt
            // Register before discoverServices, as readValue does: the result
            // arrives on a binder thread, so the entry must already be in the
            // collection the disconnect cleanup sweeps — and only while the link
            // is up (#394).
            val future = DiscoverServicesFuture(gatt, deviceId, withDescriptors, callback)
            if (!discoveryOperations.addIfLinkedUp(gatt, future, ::isLinkUp)) {
                callback(Result.failure(deviceDisconnectedError()))
                return
            }
            if (platformConfig?.android?.clearGattCache == true && !gatt.refreshGattCache()) {
                // A callback or disconnect may already own the reply.
                if (!discoveryOperations.remove(future)) return
                callback(
                    Result.failure(
                        createFlutterError(
                            UniversalBleErrorCode.FAILED,
                            "Failed to clear GATT cache"
                        )
                    )
                )
                return
            }
            if (!gatt.discoverServices()) {
                if (!discoveryOperations.remove(future)) return
                callback(
                    Result.failure(
                        createFlutterError(
                            UniversalBleErrorCode.FAILED,
                            "Failed to discover services"
                        )
                    )
                )
            }
        } catch (e: FlutterError) {
            callback(Result.failure(e))
        }
    }

    override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
        val deviceId = gatt.device.address
        // Runs on a binder thread. Read the services before taking the pending
        // futures: this throws once the link is gone, and a future removed
        // without a result would never complete.
        val services: List<BluetoothGattService>? =
            if (status == BluetoothGatt.GATT_SUCCESS) gatt.services else null
        val pending = discoveryOperations.drainMatching { it.gatt === gatt }
        if (services != null && gattRegistry.find(deviceId)?.gatt === gatt) {
            try {
                setCachedServices(deviceId, services.map { it.uuid.toString() })
            } catch (e: Exception) {
                // The cache is best-effort: the callers below still need their
                // result, and a detached plugin has no context to write to.
                UniversalBleLogger.logError("DISCOVER_CACHE_FAILED <- $deviceId $e")
            }
        }
        // A discovery result belongs to this GATT instance, not a single caller, so
        // every pending caller gets it. Complete on the main thread (platform
        // channel replies must be sent there), one callback at a time, so a
        // throwing handler cannot swallow the rest.
        for (future in pending) {
            postToMainLooper {
                val result: Result<List<UniversalBleService>> = if (services == null) {
                    Result.failure(
                        createFlutterError(
                            UniversalBleErrorCode.FAILED,
                            "Failed to discover services"
                        )
                    )
                } else {
                    try {
                        Result.success(services.map { service ->
                            UniversalBleService(
                                uuid = service.uuid.toString(),
                                characteristics = service.characteristics.map { char ->
                                    UniversalBleCharacteristic(
                                        uuid = char.uuid.toString(),
                                        properties = char.getPropertiesList(),
                                        descriptors = if (future.withDescriptors) char.descriptors.map { descriptor ->
                                            UniversalBleDescriptor(descriptor.uuid.toString())
                                        } else listOf()
                                    )
                                }
                            )
                        })
                    } catch (e: Exception) {
                        UniversalBleLogger.logError(
                            "DISCOVER_FAILED <- $deviceId $e"
                        )
                        Result.failure(
                            createFlutterError(
                                UniversalBleErrorCode.FAILED,
                                "Failed to discover services",
                                e.toString()
                            )
                        )
                    }
                }
                try {
                    future.result(result)
                } catch (e: Exception) {
                    UniversalBleLogger.logError(
                        "Discover services completion delivery failed: $e"
                    )
                }
            }
        }
    }


    override fun setNotifiable(
        deviceId: String,
        service: String,
        characteristic: String,
        bleInputProperty: BleInputProperty,
        callback: (Result<Unit>) -> Unit,
    ) {
        // Assigned once the CCCD request is registered. Every failure below
        // withdraws it before replying, so the Dart call gets exactly one
        // answer: from here, from the CCCD callback, or from a disconnect.
        var pending: SubscriptionResultFuture? = null
        try {
            UniversalBleLogger.logDebug("SET_NOTIFY -> $deviceId $service $characteristic input=$bleInputProperty")
            val gatt = gattRegistry.get(deviceId).gatt
            // A disconnected device reports that, whatever the cache holds.
            if (!isLinkUp(gatt)) {
                callback(Result.failure(deviceDisconnectedError()))
                return
            }
            val gattCharacteristic = gatt.getCharacteristic(service, characteristic)
            if (gattCharacteristic == null) {
                callback(
                    Result.failure(
                        createFlutterError(
                            UniversalBleErrorCode.CHARACTERISTIC_NOT_FOUND,
                            "characteristic not found"
                        )
                    )
                )
                return
            }
            val descriptor = gattCharacteristic.getDescriptor(ccdCharacteristic)
            val (value, enable) = when (bleInputProperty) {
                BleInputProperty.NOTIFICATION -> BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE to true
                BleInputProperty.INDICATION -> BluetoothGattDescriptor.ENABLE_INDICATION_VALUE to true
                else -> BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE to false
            }

            /** Withdraws the pending request, then answers the Dart call once. */
            fun fail(error: FlutterError) {
                val future = pending
                if (!removeSubscriptionFuture(future)) return
                if (future == null) callback(Result.failure(error)) else future.fail(error)
            }

            if (descriptor != null) {
                pending = SubscriptionResultFuture(
                    gatt,
                    descriptor,
                    gatt.device.address,
                    callback,
                )
                // Register before issuing the CCCD write, as readValue does: the
                // write's callback arrives on a binder thread and a future added
                // afterwards is never matched, leaving the Dart call awaiting
                // forever. The link check shares the lock, so a disconnected
                // autoConnect client cannot leave an entry the stack drops
                // without a callback (#394).
                if (!subscriptionOperations.addIfLinkedUp(gatt, pending, ::isLinkUp)) {
                    callback(Result.failure(deviceDisconnectedError()))
                    return
                }
                val status = writeCccdDescriptor(gatt, descriptor, value)
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    fail(
                        createFlutterError(
                            cccDescriptorErrorCode(status),
                            "Failed to update descriptor"
                        )
                    )
                    return
                }
            } else if (!isLinkUp(gatt)) {
                // No CCCD to write, so there is no pending result to sweep, but
                // setCharacteristicNotification() still succeeds locally on a
                // linkless client and would report a subscription the stack
                // cannot deliver. Refuse it like any other request (#394).
                callback(Result.failure(deviceDisconnectedError()))
                return
            } else {
                // Some devices do not need CCCD to update.
                UniversalBleLogger.logDebug("CCCD Descriptor not found")
            }

            if (gatt.setCharacteristicNotification(gattCharacteristic, enable)) {
                // With a CCCD the pending future is completed by
                // updateSubscriptionState on a binder thread; without one this
                // call is the whole request.
                if (pending == null) callback(Result.success(Unit))
            } else {
                fail(
                    createFlutterError(
                        UniversalBleErrorCode.FAILED,
                        "Failed to update subscription state"
                    )
                )
            }
        } catch (e: Exception) {
            val error = if (e is FlutterError) {
                e
            } else {
                createFlutterError(
                    UniversalBleErrorCode.FAILED,
                    "Failed to update subscription state",
                    e.toString()
                )
            }
            // A CCCD callback or a disconnect sweep may already have answered;
            // withdrawing first keeps this path from replying twice.
            if (pending == null || subscriptionOperations.remove(pending)) {
                callback(Result.failure(error))
            }
        }
    }

    /**
     * Writes [value] to the CCCD, or to the descriptor that enables indications
     * or notifications, and returns the status the stack reported. The API 33+
     * overload reports one; the deprecated one only a boolean, mapped here.
     * A throwing call propagates to the caller's single error path.
     *
     * [value] is nullable because the values come from static arrays in the
     * platform jar, which JVM tests see as null. The deprecated overload only
     * stores the array, and the API 33+ overload — unreachable there, because
     * the test JVM reports SDK_INT 0 — needs the non-null value a device has.
     */
    @Suppress("DEPRECATION")
    private fun writeCccdDescriptor(
        gatt: BluetoothGatt,
        descriptor: BluetoothGattDescriptor,
        value: ByteArray?,
    ): Int = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        gatt.writeDescriptor(descriptor, checkNotNull(value))
    } else {
        descriptor.value = value
        if (gatt.writeDescriptor(descriptor)) {
            BluetoothGatt.GATT_SUCCESS
        } else {
            BluetoothGatt.GATT_FAILURE
        }
    }

    /**
     * The error a refused CCCD write reports. The pre-33 overload only says
     * whether the request started, so it keeps the generic code; API 33+
     * carries a status that names the reason.
     */
    private fun cccDescriptorErrorCode(status: Int): UniversalBleErrorCode =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            status.parseBluetoothStatusCodeError() ?: UniversalBleErrorCode.FAILED
        } else {
            UniversalBleErrorCode.FAILED
        }

    /**
     * Removes [future] while it is still registered. False means a callback (or
     * a device cleanup) already owns the reply, which must not be sent twice.
     */
    private fun removeSubscriptionFuture(future: SubscriptionResultFuture?): Boolean {
        if (future == null) return true
        return subscriptionOperations.remove(future)
    }

    override fun readValue(
        deviceId: String,
        service: String,
        characteristic: String,
        callback: (Result<ByteArray>) -> Unit,
    ) {
        try {
            UniversalBleLogger.logDebug("READ -> $deviceId $service $characteristic")
            val gatt = gattRegistry.get(deviceId).gatt
            // A disconnected device reports that, whatever the cache holds.
            if (!isLinkUp(gatt)) {
                callback(Result.failure(deviceDisconnectedError()))
                return
            }
            val gattCharacteristic = gatt.getCharacteristic(service, characteristic)
            if (gattCharacteristic == null) {
                callback(
                    Result.failure(
                        createFlutterError(
                            UniversalBleErrorCode.CHARACTERISTIC_NOT_FOUND,
                            "Unknown characteristic"
                        )
                    )
                )
                return
            }
            // Register before issuing the read, as writeValue does: the response
            // arrives on a binder thread and a future added afterwards is never
            // matched (the callback finds nothing to complete), leaving the Dart
            // call awaiting forever. Every access to the list holds its lock.
            // The link check shares the lock, so a disconnected client cannot
            // leave a read that the stack drops without a callback (#394).
            submitGattRequest(
                gatt,
                readOperations,
                ReadResultFuture(
                    gatt,
                    gatt.device.address,
                    gattCharacteristic.uuid.toString(),
                    gattCharacteristic.service.uuid.toString(),
                    callback
                ),
                issue = {
                    if (gatt.readCharacteristic(gattCharacteristic)) {
                        BluetoothGatt.GATT_SUCCESS
                    } else {
                        BluetoothGatt.GATT_FAILURE
                    }
                },
                statusError = {
                    createFlutterError(
                        UniversalBleErrorCode.CHARACTERISTIC_NOT_FOUND,
                        "$characteristic not found",
                    )
                },
            )?.let { failure ->
                callback(Result.failure(failure))
                return
            }
        } catch (e: FlutterError) {
            callback(Result.failure(e))
        } catch (e: Exception) {
            callback(
                Result.failure(
                    createFlutterError(
                        UniversalBleErrorCode.READ_FAILED,
                        "Failed to read value",
                        e.toString()
                    )
                )
            )
        }
    }

    override fun onCharacteristicRead(
        gatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic,
        value: ByteArray,
        status: Int,
    ) {
        // Runs on a binder thread: match and remove under the lock, then
        // complete on the main thread (platform-channel replies must be sent
        // there). Every readCharacteristic() has its own response, so this
        // callback belongs to the oldest pending read of that characteristic —
        // completing every match would acknowledge reads still in flight.
        // The service must match exactly, as onCharacteristicWrite requires: a
        // device+characteristic-only fallback can complete a read issued for
        // another service that exposes the same characteristic UUID (HID
        // report characteristics).
        val deviceId = gatt.device.address
        val characteristicId = characteristic.uuid.toString()
        val serviceUuid = characteristic.service?.uuid?.toString()
        val future = readOperations.takeOldest {
            it.gatt === gatt &&
                it.deviceId == deviceId &&
                it.characteristicId == characteristicId &&
                it.serviceId == serviceUuid
        }
        if (status != BluetoothGatt.GATT_SUCCESS) {
            UniversalBleLogger.logError(
                "READ_FAILED <- $deviceId $characteristicId status=$status"
            )
        }
        if (future == null) {
            return
        }
        postToMainLooper {
            try {
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    future.result(Result.success(value))
                } else {
                    future.result(
                        Result.failure(
                            createFlutterError(
                                gattStatusToUniversalBleErrorCode(status),
                                "Failed to read",
                                status.toString()
                            )
                        )
                    )
                }
            } catch (e: Exception) {
                UniversalBleLogger.logError("Read completion delivery failed: $e")
            }
        }
    }

    override fun writeValue(
        deviceId: String,
        service: String,
        characteristic: String,
        value: ByteArray,
        bleOutputProperty: BleOutputProperty,
        callback: (Result<Unit>) -> Unit,
    ) {
        try {
            UniversalBleLogger.logDebug("WRITE -> $deviceId $service $characteristic len=${value.size} property=$bleOutputProperty")
            val gatt = gattRegistry.get(deviceId).gatt
            // A disconnected device reports that, whatever the cache holds.
            if (!isLinkUp(gatt)) {
                callback(Result.failure(deviceDisconnectedError()))
                return
            }
            val gattCharacteristic = gatt.getCharacteristic(service, characteristic)
            if (gattCharacteristic == null) {
                callback(
                    Result.failure(
                        createFlutterError(
                            UniversalBleErrorCode.CHARACTERISTIC_NOT_FOUND,
                            "$characteristic not found",
                        )
                    )
                )
                return
            }

            var writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
            if (bleOutputProperty == BleOutputProperty.WITH_RESPONSE) {
                if (gattCharacteristic.properties and BluetoothGattCharacteristic.PROPERTY_WRITE == 0) {
                    callback(
                        Result.failure(
                            createFlutterError(
                                UniversalBleErrorCode.CHARACTERISTIC_DOES_NOT_SUPPORT_WRITE,
                                "Characteristic does not support write withResponse"
                            )
                        )
                    )
                    return
                }
                writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
            } else if (bleOutputProperty == BleOutputProperty.WITHOUT_RESPONSE) {
                if (gattCharacteristic.properties and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE == 0) {
                    callback(
                        Result.failure(
                            createFlutterError(
                                UniversalBleErrorCode.CHARACTERISTIC_DOES_NOT_SUPPORT_WRITE_WITHOUT_RESPONSE,
                                "Characteristic does not support write withoutResponse"
                            )
                        )
                    )
                    return
                }
                writeType = BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
            }

            // Checked after the link check and the lookups so a wrong device,
            // attribute or operation outranks a payload that is too long.
            if (value.size > MAX_ATTRIBUTE_VALUE_SIZE) {
                callback(
                    Result.failure(
                        createFlutterError(
                            UniversalBleErrorCode.INVALID_ATTRIBUTE_LENGTH,
                            "Value is ${value.size} bytes, longer than the $MAX_ATTRIBUTE_VALUE_SIZE-byte attribute limit",
                        )
                    )
                )
                return
            }

            submitGattRequest(
                gatt,
                writeOperations,
                WriteResultFuture(
                    gatt,
                    gatt.device.address,
                    gattCharacteristic.uuid.toString(),
                    gattCharacteristic.service.uuid.toString(),
                    callback
                ),
                issue = {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        gatt.writeCharacteristic(gattCharacteristic, value, writeType)
                    } else {
                        @Suppress("DEPRECATION")
                        gattCharacteristic.value = value
                        gattCharacteristic.writeType = writeType
                        @Suppress("DEPRECATION")
                        if (gatt.writeCharacteristic(gattCharacteristic)) {
                            BluetoothGatt.GATT_SUCCESS
                        } else {
                            BluetoothGatt.GATT_FAILURE
                        }
                    }
                },
                statusError = { status ->
                    createFlutterError(
                        gattStatusToUniversalBleErrorCode(status),
                        "Failed to write",
                        status.toString()
                    )
                },
            )?.let { failure ->
                callback(Result.failure(failure))
            }
        } catch (e: FlutterError) {
            callback(Result.failure(e))
        } catch (e: Exception) {
            // A write the stack refuses by throwing (a characteristic whose
            // service is gone, for example) never reaches onCharacteristicWrite.
            // The submission already unregistered its result, so the next
            // completion cannot be delivered to the orphaned future.
            callback(
                Result.failure(
                    createFlutterError(
                        UniversalBleErrorCode.WRITE_FAILED,
                        "Failed to write: ${e.message}",
                        e.toString()
                    )
                )
            )
        }
    }

    private fun <T : PendingOperation> pendingOperations(label: String) =
        PendingOperations<T>({ action: () -> Unit -> postToMainLooper(action) }, label)

    /**
     * Registers [pending] for a GATT request and submits it with [issue].
     *
     * Returns null when the request is pending, i.e. the platform is expected
     * to report it through a callback, or the failure to deliver when it was
     * refused. A request is registered only while its client's link is up, and
     * under the pending collection's lock, so a disconnect cannot sweep the
     * list in between and strand it (#394). A stack call that refuses the
     * request, by returning a non-success [BluetoothGatt] status or by
     * throwing, has its registration withdrawn here: otherwise the next
     * completion would be delivered to the orphaned entry and every later
     * operation would lag by one (#387).
     *
     * Callers keep their own error mapping: [statusError] turns a refusal into
     * the code that operation has always reported.
     */
    private fun <T : PendingOperation> submitGattRequest(
        gatt: BluetoothGatt,
        operations: PendingOperations<T>,
        pending: T,
        issue: () -> Int,
        statusError: (Int) -> FlutterError,
    ): FlutterError? {
        if (!operations.addIfLinkedUp(gatt, pending, ::isLinkUp)) {
            return deviceDisconnectedError()
        }
        val status = try {
            issue()
        } catch (e: Exception) {
            // A callback (or a disconnect sweep) may already own the reply.
            if (!operations.remove(pending)) return null
            throw e
        }
        if (status == BluetoothGatt.GATT_SUCCESS) return null
        // A sweep or callback may have claimed the reply while the stack call
        // was running; in that case it already answered for this request.
        if (!operations.remove(pending)) return null
        return statusError(status)
    }

    // Deliver on the main looper. Platform-channel replies must be sent there,
    // and because matching futures are removed from their list before delivery,
    // a completion must never be dropped just because the cached handler was
    // cleared (a GATT callback racing onDetachedFromEngine) — that would leak
    // the pending Dart await. Fall back to a fresh main-looper handler so the
    // completion is always attempted.
    private fun postToMainLooper(action: () -> Unit) {
        (mainThreadHandler ?: Handler(Looper.getMainLooper())).post(action)
    }

    override fun onCharacteristicWrite(
        gatt: BluetoothGatt?,
        characteristic: BluetoothGattCharacteristic,
        status: Int,
    ) {
        // Runs on a binder thread: remove the matching future under the lock,
        // then complete it on the main thread (platform-channel replies must
        // be sent there), individually contained so a bad callback can neither
        // corrupt the list nor block later completions. Android serializes
        // GATT operations per device, so this callback always belongs to the
        // OLDEST pending write on this characteristic — completing every match
        // would acknowledge later writes that are still in flight (or not yet
        // accepted natively) with this operation's status.
        val future = writeOperations.takeOldest {
            it.gatt === gatt &&
                it.deviceId == gatt?.device?.address &&
                it.characteristicId == characteristic.uuid.toString() &&
                it.serviceId == characteristic.service?.uuid?.toString()
        }
        if (status != BluetoothGatt.GATT_SUCCESS) {
            UniversalBleLogger.logError(
                "WRITE_FAILED <- ${gatt?.device?.address} ${characteristic.uuid} status=$status"
            )
        }
        if (future != null) {
            postToMainLooper {
                try {
                    if (status == BluetoothGatt.GATT_SUCCESS) {
                        future.result(Result.success(Unit))
                    } else {
                        future.result(
                            Result.failure(
                                createFlutterError(
                                    gattStatusToUniversalBleErrorCode(status),
                                    "Failed to write",
                                    status.toString()
                                )
                            )
                        )
                    }
                } catch (e: Exception) {
                    UniversalBleLogger.logError("Write completion delivery failed: $e")
                }
            }
        }
    }

    override fun readDescriptorValue(
        deviceId: String,
        service: String,
        characteristic: String,
        descriptor: String,
        callback: (Result<ByteArray>) -> Unit,
    ) {
        try {
            UniversalBleLogger.logDebug("READ_DESCRIPTOR -> $deviceId $service $characteristic $descriptor")
            val gatt = gattRegistry.get(deviceId).gatt
            // A disconnected device reports that, whatever the cache holds.
            if (!isLinkUp(gatt)) {
                callback(Result.failure(deviceDisconnectedError()))
                return
            }
            val gattCharacteristic = gatt.getCharacteristic(service, characteristic)
            if (gattCharacteristic == null) {
                callback(
                    Result.failure(
                        createFlutterError(
                            UniversalBleErrorCode.CHARACTERISTIC_NOT_FOUND,
                            "Characteristic not found"
                        )
                    )
                )
                return
            }
            val gattDescriptor = gattCharacteristic.getDescriptor(UUID.fromString(descriptor))
            if (gattDescriptor == null) {
                callback(
                    Result.failure(
                        createFlutterError(
                            UniversalBleErrorCode.CHARACTERISTIC_NOT_FOUND,
                            "Descriptor not found"
                        )
                    )
                )
                return
            }
            // Register before issuing the read, as readValue does: the response
            // can otherwise arrive before the future is pending (#394).
            submitGattRequest(
                gatt,
                descriptorReadOperations,
                ReadDescriptorResultFuture(
                    gatt,
                    gatt.device.address,
                    gattDescriptor.uuid.toString(),
                    gattCharacteristic.uuid.toString(),
                    gattCharacteristic.service.uuid.toString(),
                    callback
                ),
                issue = {
                    if (gatt.readDescriptor(gattDescriptor)) {
                        BluetoothGatt.GATT_SUCCESS
                    } else {
                        BluetoothGatt.GATT_FAILURE
                    }
                },
                statusError = {
                    createFlutterError(
                        UniversalBleErrorCode.READ_FAILED,
                        "Failed to read descriptor"
                    )
                },
            )?.let { failure ->
                callback(Result.failure(failure))
                return
            }
        } catch (e: FlutterError) {
            callback(Result.failure(e))
        } catch (e: Exception) {
            callback(
                Result.failure(
                    createFlutterError(
                        UniversalBleErrorCode.READ_FAILED,
                        "Failed to read descriptor value",
                        e.toString()
                    )
                )
            )
        }
    }

    override fun onDescriptorRead(
        gatt: BluetoothGatt,
        descriptor: BluetoothGattDescriptor,
        status: Int,
        value: ByteArray,
    ) {
        val future = descriptorReadOperations.takeOldest {
            it.gatt === gatt &&
                it.deviceId == gatt.device.address &&
                it.descriptorId == descriptor.uuid.toString() &&
                it.characteristicId == descriptor.characteristic.uuid.toString() &&
                it.serviceId == descriptor.characteristic.service.uuid.toString()
        }
        if (future != null) {
            postToMainLooper {
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    future.result(Result.success(value))
                } else {
                    future.result(
                        Result.failure(
                            createFlutterError(
                                gattStatusToUniversalBleErrorCode(status),
                                "Failed to read descriptor",
                                status.toString()
                            )
                        )
                    )
                }
            }
        }
    }

    @Suppress("DEPRECATION")
    override fun onDescriptorRead(
        gatt: BluetoothGatt,
        descriptor: BluetoothGattDescriptor,
        status: Int,
    ) {
        onDescriptorRead(gatt, descriptor, status, descriptor.value ?: byteArrayOf())
    }

    override fun writeDescriptorValue(
        deviceId: String,
        service: String,
        characteristic: String,
        descriptor: String,
        value: ByteArray,
        callback: (Result<Unit>) -> Unit,
    ) {
        try {
            UniversalBleLogger.logDebug("WRITE_DESCRIPTOR -> $deviceId $service $characteristic $descriptor len=${value.size}")
            val gatt = gattRegistry.get(deviceId).gatt
            // A disconnected device reports that, whatever the cache holds.
            if (!isLinkUp(gatt)) {
                callback(Result.failure(deviceDisconnectedError()))
                return
            }
            val gattCharacteristic = gatt.getCharacteristic(service, characteristic)
            if (gattCharacteristic == null) {
                callback(
                    Result.failure(
                        createFlutterError(
                            UniversalBleErrorCode.CHARACTERISTIC_NOT_FOUND,
                            "Characteristic not found"
                        )
                    )
                )
                return
            }
            val gattDescriptor = gattCharacteristic.getDescriptor(UUID.fromString(descriptor))
            if (gattDescriptor == null) {
                callback(
                    Result.failure(
                        createFlutterError(
                            UniversalBleErrorCode.CHARACTERISTIC_NOT_FOUND,
                            "Descriptor not found"
                        )
                    )
                )
                return
            }

            // Checked after the link check and the lookups so a wrong device or
            // attribute outranks a payload that is too long. writeDescriptor does
            // not throw for a long value, but a value over the attribute cap
            // cannot work.
            if (value.size > MAX_ATTRIBUTE_VALUE_SIZE) {
                callback(
                    Result.failure(
                        createFlutterError(
                            UniversalBleErrorCode.INVALID_ATTRIBUTE_LENGTH,
                            "Value is ${value.size} bytes, longer than the $MAX_ATTRIBUTE_VALUE_SIZE-byte attribute limit",
                        )
                    )
                )
                return
            }

            submitGattRequest(
                gatt,
                descriptorWriteOperations,
                WriteDescriptorResultFuture(
                    gatt,
                    gatt.device.address,
                    gattDescriptor.uuid.toString(),
                    gattCharacteristic.uuid.toString(),
                    gattCharacteristic.service.uuid.toString(),
                    callback
                ),
                issue = {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        gatt.writeDescriptor(gattDescriptor, value)
                    } else {
                        @Suppress("DEPRECATION")
                        gattDescriptor.value = value
                        @Suppress("DEPRECATION")
                        if (gatt.writeDescriptor(gattDescriptor)) {
                            BluetoothGatt.GATT_SUCCESS
                        } else {
                            BluetoothGatt.GATT_FAILURE
                        }
                    }
                },
                statusError = { status ->
                    createFlutterError(
                        gattStatusToUniversalBleErrorCode(status),
                        "Failed to write descriptor",
                        status.toString()
                    )
                },
            )?.let { failure ->
                callback(Result.failure(failure))
            }
        } catch (e: FlutterError) {
            callback(Result.failure(e))
        } catch (e: Exception) {
            // The submission unregistered the pending result before rethrowing,
            // so a refused descriptor write cannot consume the next completion.
            callback(
                Result.failure(
                    createFlutterError(
                        UniversalBleErrorCode.FAILED,
                        "Failed to write descriptor value",
                        e.toString()
                    )
                )
            )
        }
    }

    override fun requestMtu(deviceId: String, expectedMtu: Long, callback: (Result<Long>) -> Unit) {
        UniversalBleLogger.logDebug("REQUEST_MTU -> $deviceId expected=$expectedMtu")
        val gatt = try {
            gattRegistry.get(deviceId).gatt
        } catch (e: FlutterError) {
            postMtuResult(callback, Result.failure(e))
            return
        }
        var reusedMtu: Int? = null
        var shouldRequest = false
        var linkUp = false
        mtuOperations.withLock {
            // Only serve or register while the link is up, under the lock the
            // disconnect cleanup takes (see writeValue): the stack accepts a
            // request on a linkless autoConnect client and then drops it
            // without a callback, and the stranded entry would be completed by
            // the reconnected link's first MTU change (#394).
            linkUp = isLinkUp(gatt)
            if (linkUp) {
                val cached = negotiatedMtus[gatt]
                // Android 14+ ignores subsequent negotiations. Earlier versions
                // can still request an increase when the observed MTU is smaller.
                if (cached != null && canReuseNegotiatedMtu(cached, expectedMtu.toInt(), Build.VERSION.SDK_INT)) {
                    reusedMtu = cached
                } else {
                    val alreadyPending = mtuOperations.any { it.gatt === gatt }
                    // Register before requestMtu: its callback can arrive immediately.
                    mtuOperations.add(MtuResultFuture(deviceId, gatt, callback))
                    shouldRequest = !alreadyPending
                }
            }
        }
        if (!linkUp) {
            postMtuResult(callback, Result.failure(deviceDisconnectedError()))
            return
        }
        reusedMtu?.let {
            // Deliver outside the lock, like every other completion path.
            postMtuResult(callback, Result.success(it.toLong()))
            return
        }
        if (!shouldRequest) return
        try {
            if (!gatt.requestMtu(expectedMtu.toInt())) {
                completeMtu(gatt, Result.failure(createFlutterError(
                    UniversalBleErrorCode.FAILED,
                    "MTU request was not accepted",
                )))
            }
        } catch (e: Exception) {
            completeMtu(gatt, Result.failure(
                if (e is FlutterError) e else createFlutterError(
                    UniversalBleErrorCode.FAILED,
                    "Failed to request MTU",
                    e.toString(),
                )
            ))
        }
    }

    private fun postMtuResult(callback: (Result<Long>) -> Unit, result: Result<Long>) {
        postToMainLooper {
            try {
                callback(result)
            } catch (e: Exception) {
                UniversalBleLogger.logError("MTU completion delivery failed: $e")
            }
        }
    }

    private fun completeMtu(gatt: BluetoothGatt, result: Result<Long>) {
        val pending = mtuOperations.withLock {
            result.getOrNull()?.let { negotiatedMtus[gatt] = it.toInt() }
            mtuOperations.drainMatching { it.gatt === gatt }
        }
        // GATT callbacks run on Binder threads. Match the main-looper delivery
        // used by other BLE completions, after removing requests under the lock.
        for (future in pending) postMtuResult(future.result, result)
    }

    override fun requestConnectionPriority(
        deviceId: String,
        priority: BleConnectionPriority,
        callback: (Result<Unit>) -> Unit,
    ) {
        try {
            val gatt = gattRegistry.get(deviceId).gatt
            val androidPriority = when (priority) {
                BleConnectionPriority.BALANCED -> BluetoothGatt.CONNECTION_PRIORITY_BALANCED
                BleConnectionPriority.HIGH_PERFORMANCE -> BluetoothGatt.CONNECTION_PRIORITY_HIGH
                BleConnectionPriority.LOW_POWER -> BluetoothGatt.CONNECTION_PRIORITY_LOW_POWER
            }
            val success = gatt.requestConnectionPriority(androidPriority)
            if (success) {
                callback(Result.success(Unit))
            } else {
                callback(
                    Result.failure(
                        createFlutterError(
                            UniversalBleErrorCode.FAILED,
                            "requestConnectionPriority returned false",
                        ),
                    ),
                )
            }
        } catch (e: FlutterError) {
            callback(Result.failure(e))
        } catch (e: Exception) {
            callback(
                Result.failure(
                    createFlutterError(
                        UniversalBleErrorCode.FAILED,
                        "requestConnectionPriority failed",
                        e.toString()
                    )
                )
            )
        }
    }

    // BluetoothGattCallback.onConnectionUpdated is @hide (not in public android.jar).
    // Same method name is required so the framework invokes it at runtime; no `override`.
    @Suppress("unused")
    fun onConnectionUpdated(
        gatt: BluetoothGatt?,
        interval: Int,
        latency: Int,
        timeout: Int,
        status: Int,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val deviceId = gatt?.device?.address ?: return
        if (!isCurrentClient(gatt)) return
        UniversalBleLogger.logDebug(
            "onConnectionUpdated -> $deviceId interval=$interval latency=$latency timeout=$timeout status=$status"
        )
        mainThreadHandler?.post {
            callbackChannel?.onConnectionParametersUpdated(
                BleConnectionParametersChange(
                    deviceId = deviceId,
                    interval = interval.toLong(),
                    latency = latency.toLong(),
                    supervisionTimeout = timeout.toLong(),
                    status = status.toLong(),
                )
            ) {}
        }
    }

    /**
     * Whether [gatt] is still the client registered for its device address, i.e.
     * the connection whose state and values the app should see. A client that a
     * newer `connect()` replaced is not, and neither is one `disconnect()` has
     * already removed from the registry.
     *
     * An `autoConnect` client deliberately stays registered while Android keeps
     * it open, so it keeps reporting once the link recovers.
     */
    private fun isCurrentClient(gatt: BluetoothGatt?): Boolean =
        gatt != null && gattRegistry.find(gatt.device.address)?.gatt === gatt

    /**
     * Whether [gatt] has a link the platform can deliver operations on.
     *
     * Client state is updated from `onConnectionStateChange` on a binder
     * thread, so an operation must read this inside the lock its pending
     * collection takes (see [PendingOperations.addIfLinkedUp]): either the
     * check sees the link already gone and refuses the call, or the pending
     * result is registered in time for the cleanup sweep to fail it. Reading it
     * outside that lock leaves a window where the check passes, cleanup sweeps,
     * and the result is added afterwards — stranded until a later callback
     * completes it one behind (#394).
     *
     * Requests check it before the characteristic lookup: an autoConnect client
     * keeps its cached services across a link loss, so a lookup-first order
     * would report a missing characteristic for a device that is known and
     * simply disconnected. The submission gate still re-checks under its lock.
     */
    private fun isLinkUp(gatt: BluetoothGatt): Boolean =
        gattRegistry.find(gatt)?.isLinkUp == true

    private fun deviceDisconnectedError(): FlutterError = createFlutterError(
        UniversalBleErrorCode.DEVICE_DISCONNECTED,
        "Device Disconnected",
    )

    override fun onMtuChanged(gatt: BluetoothGatt?, mtu: Int, status: Int) {
        val deviceId = gatt?.device?.address ?: return
        // Only the registered client may report or cache an MTU; a stale client
        // that was already removed must not populate state for a new connection.
        if (!isCurrentClient(gatt)) return
        UniversalBleLogger.logDebug("MTU_CHANGED <- $deviceId mtu=$mtu status=$status")
        completeMtu(gatt, if (status == BluetoothGatt.GATT_SUCCESS) {
            Result.success(mtu.toLong())
        } else {
            Result.failure(createFlutterError(
                UniversalBleErrorCode.FAILED,
                "Failed to change MTU",
                status.toString(),
            ))
        })
    }

    override fun isPaired(deviceId: String, callback: (Result<Boolean>) -> Unit) {
        val remoteDevice: BluetoothDevice =
            bluetoothManager.adapter.getRemoteDevice(deviceId)
        callback(Result.success(remoteDevice.isBonded()))
    }

    override fun pair(deviceId: String, callback: (Result<Boolean>) -> Unit) {
        try {
            val remoteDevice = bluetoothManager.adapter.getRemoteDevice(deviceId)
            val pendingFuture = pairResultFutures.remove(deviceId)

            // If already paired, return and complete pending futures
            if (remoteDevice.isBonded()) {
                pendingFuture?.let { it(Result.success(true)) }
                callback(Result.success(true))
                return
            }

            // throw error if we already have a pending future
            if (pendingFuture != null) {
                callback(
                    Result.failure(
                        createFlutterError(
                            UniversalBleErrorCode.OPERATION_IN_PROGRESS,
                            "Pairing already in progress"
                        )
                    )
                )
                return
            }

            // Make a Pair request and complete future from Pair Update intent
            if (remoteDevice.createBond()) {
                pairResultFutures[deviceId] = callback
            } else {
                callback(
                    Result.failure(
                        createFlutterError(
                            UniversalBleErrorCode.PAIRING_FAILED,
                            "Failed to pair"
                        )
                    )
                )
            }
        } catch (e: Exception) {
            callback(
                Result.failure(
                    createFlutterError(UniversalBleErrorCode.FAILED, e.toString())
                )
            )
        }

    }

    override fun unPair(deviceId: String, callback: (Result<Unit>) -> Unit) {
        try {
            val remoteDevice: BluetoothDevice =
                bluetoothManager.adapter.getRemoteDevice(deviceId)
            if (remoteDevice.isBonded()) remoteDevice.removeBond()
            callback(Result.success(Unit))
        } catch (e: Exception) {
            callback(Result.failure(e))
        }
    }

    override fun getSystemDevices(
        withServices: List<String>,
        callback: (Result<List<UniversalBleScanResult>>) -> Unit,
    ) {
        var devices: List<BluetoothDevice> =
            bluetoothManager.getConnectedDevices(BluetoothProfile.GATT)
        if (withServices.isNotEmpty()) {
            devices = filterDevicesByServices(devices, withServices)
        }
        callback(
            Result.success(
                devices.map {
                    val timestampMicroseconds = System.currentTimeMillis() * 1000
                    UniversalBleScanResult(
                        name = it.name,
                        deviceId = it.address,
                        isPaired = it.isBonded(),
                        manufacturerDataList = null,
                        serviceData = null,
                        rssi = null,
                        timestamp = timestampMicroseconds / 1000,
                        timestampMicroseconds = timestampMicroseconds
                    )
                }
            )
        )
    }

    private fun filterDevicesByServices(
        devices: List<BluetoothDevice>,
        withServices: List<String>,
    ): List<BluetoothDevice> {
        // If all devices have cached services
        if (devices.all { cachedServicesMap[it.address] != null }) {
            return devices.filter { device ->
                cachedServicesMap[device.address]?.any { uuid -> withServices.contains(uuid) } == true
            }
        }

        // Else discover services off already connected devices
        val latch = CountDownLatch(devices.size)
        val resultMap = mutableMapOf<String, Boolean>()

        devices.forEach { device ->
            discoverServicesOffAlreadyConnectedDevice(device) { uuids ->
                resultMap[device.address] =
                    uuids?.any { uuid -> withServices.contains(uuid) } == true
                latch.countDown()
            }
        }

        try {
            val timeout = (devices.size * 2).toLong()
            latch.await(timeout, TimeUnit.SECONDS)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        }

        return devices.filter { resultMap[it.address] == true }
    }

    private fun discoverServicesOffAlreadyConnectedDevice(
        device: BluetoothDevice,
        callback: (List<String>?) -> Unit,
    ) {
        // Check if already cached
        cachedServicesMap[device.address]?.let {
            callback(it)
            return
        }

        // To avoid duplicate callback
        var isUpdated = false
        fun updateCallback(uuids: List<String>?) {
            if (isUpdated) return
            callback(uuids)
            isUpdated = true
        }

        // If its a known gatt, just discover services
        gattRegistry.find(device.address)?.let { client ->
            val gatt = client.gatt
            gatt.services?.let { services ->
                updateCallback(services.map { service -> service.uuid.toString() })
                return
            }

            if (gatt.discoverServices()) {
                // Completed by onServicesDiscovered on a binder thread.
                discoveryOperations.add(
                    DiscoverServicesFuture(
                        gatt,
                        device.address,
                        false
                    ) { uuids: Result<List<UniversalBleService>> ->
                        if (uuids.isSuccess) {
                            updateCallback(uuids.getOrNull()?.map { it.uuid })
                        } else {
                            updateCallback(null)
                        }
                    }
                )
                return
            }
        }

        // Else connect to Gatt, discover services, then disconnect
        val callbackHandler = object : BluetoothGattCallback() {
            override fun onConnectionStateChange(gatt: BluetoothGatt?, status: Int, newState: Int) {
                if (status == BluetoothGatt.GATT_SUCCESS && newState == BluetoothGatt.STATE_CONNECTED) {
                    if (gatt?.discoverServices() != true) {
                        updateCallback(null)
                        if (!gattRegistry.isKnown(device.address)) {
                            gatt?.disconnect()
                        }
                    }
                } else {
                    updateCallback(null)
                }
            }

            override fun onServicesDiscovered(gatt: BluetoothGatt?, status: Int) {
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    val uuids = gatt?.services?.map { it.uuid.toString() }
                    if (uuids != null) {
                        setCachedServices(device.address, uuids)
                    }
                    updateCallback(uuids)
                }
                if (!gattRegistry.isKnown(device.address)) {
                    gatt?.disconnect()
                }
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            device.connectGatt(context, false, callbackHandler, BluetoothDevice.TRANSPORT_LE)
        } else {
            device.connectGatt(context, false, callbackHandler)
        }
    }

    /**
     * Fails pending operations for [deviceId]. When [gatt] is provided (a
     * disconnect of a specific client), that client's requests and MTU state
     * are cleared, along with those of any client that is no longer registered
     * for the address. A replacement GATT at the same address is unaffected.
     *
     * Superseded clients are swept because their own `STATE_DISCONNECTED` may
     * never arrive (#277), and this is then the last chance to fail the Dart
     * calls they still owe a reply.
     */
    private fun cleanUpConnection(deviceId: String, gatt: BluetoothGatt? = null) {
        /** Whether a pending operation belongs to the connection being cleaned up. */
        fun owns(futureGatt: BluetoothGatt, futureDeviceId: String): Boolean {
            if (futureDeviceId != deviceId) return false
            // Device-wide cleanup fails every operation for the address.
            if (gatt == null) return true
            if (futureGatt === gatt) return true
            // Read the registry at match time rather than once up front: a
            // connect() can publish a replacement while these lists are being
            // swept, and that client's requests must survive. Reading it under
            // each list's lock is safe because a future only enters a list
            // after its own gatt was published to the registry, so an entry
            // whose gatt is not visible here cannot be in the list being
            // filtered.
            return futureGatt !== gattRegistry.find(deviceId)?.gatt
        }

        failPendingOperations(::owns)
        // The observed MTU belonged to the link that is gone; the next
        // connection negotiates its own.
        mtuOperations.withLock {
            if (gatt != null) {
                negotiatedMtus.remove(gatt)
            } else {
                negotiatedMtus.keys.removeAll { it.device.address == deviceId }
            }
        }
    }

    /**
     * Fails every pending operation that [owns] selects with
     * `deviceDisconnected`, each on the main thread.
     *
     * Each list is swept under its own lock, which the request paths share
     * with their link check: a request submitted concurrently either lands in
     * time to be swept or is refused because its link is gone (#394).
     */
    private fun failPendingOperations(
        owns: (futureGatt: BluetoothGatt, futureDeviceId: String) -> Boolean,
    ) {
        val error: FlutterError = deviceDisconnectedError()
        val matches = { future: PendingOperation -> owns(future.gatt, future.deviceId) }
        readOperations.failMatching(error, matches)
        writeOperations.failMatching(error, matches)
        descriptorReadOperations.failMatching(error, matches)
        descriptorWriteOperations.failMatching(error, matches)
        subscriptionOperations.failMatching(error, matches)
        mtuOperations.failMatching(error, matches)
        discoveryOperations.failMatching(error, matches)
        rssiOperations.failMatching(error, matches)
    }

    private fun cleanConnection(gatt: BluetoothGatt) {
        val deviceId = gatt.device.address
        // A client the registry no longer tracks was closed already (a late
        // STATE_DISCONNECTED, after the fallback timer or another path ran). It
        // still gets a client so the teardown below stays idempotent, but that
        // client is never published: doing so would evict a newer connection
        // from the active slot and make a live link look superseded.
        val client = gattRegistry.find(gatt) ?: GattClient(gatt)
        client.autoConnect = false
        gattRegistry.beginClose(client)
        cleanUpConnection(deviceId, gatt)
        gatt.disconnect()
        // close() runs from onConnectionStateChange once the link is down. A client that never
        // reached CONNECTED gets no callback at all, so release it anyway after a while (#277).
        mainThreadHandler?.postDelayed({
            if (client.state == GattClient.State.CLOSING && gattRegistry.finishClose(client)) {
                UniversalBleLogger.logDebug("No STATE_DISCONNECTED for $deviceId, closing gatt")
                gatt.close()
                // A newer connect() owns this address now; its state is not ours to report.
                if (!gattRegistry.isKnown(deviceId)) {
                    callbackChannel?.onConnectionChanged(deviceId, false, null, null, null) {}
                }
            }
        }, gattCloseTimeoutMs)
    }

    private fun onBondStateUpdate(deviceId: String, bonded: Boolean, isFailure: Boolean = false) {
        val future = pairResultFutures.remove(deviceId)
        future?.let { it(Result.success(bonded)) }
        mainThreadHandler?.post {
            callbackChannel?.onPairStateChange(deviceId, bonded, isFailure) {}
        }
    }

    private val broadcastReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == BluetoothAdapter.ACTION_STATE_CHANGED) {
                mainThreadHandler?.post {
                    callbackChannel?.onAvailabilityChanged(
                        bluetoothManager.adapter?.state?.toAvailabilityState()
                            ?: AvailabilityState.UNKNOWN
                    ) {}
                }
            } else if (intent.action == BluetoothDevice.ACTION_BOND_STATE_CHANGED) {
                val bondStateChange = intent.getBondStateChange()
                if (bondStateChange == null) {
                    UniversalBleLogger.logError("No device found in ACTION_BOND_STATE_CHANGED intent")
                    return
                }
                // get pairing failed error
                when (bondStateChange.state) {
                    BluetoothDevice.BOND_BONDING -> {
                        bondingAttempts.add(bondStateChange.device.address)
                        UniversalBleLogger.logVerbose("${bondStateChange.device.address} BOND_BONDING")
                    }

                    BluetoothDevice.BOND_BONDED -> {
                        bondingAttempts.remove(bondStateChange.device.address)
                        onBondStateUpdate(bondStateChange.device.address, true)
                    }

                    BluetoothDevice.ERROR -> {
                        bondingAttempts.remove(bondStateChange.device.address)
                        onBondStateUpdate(bondStateChange.device.address, false, isFailure = true)
                    }

                    BluetoothDevice.BOND_NONE -> {
                        UniversalBleLogger.logError("${bondStateChange.device.address} BOND_NONE")
                        // A BOND_NONE that ends a bonding attempt we saw start is a failed/declined bond,
                        // not a steady BOND_NONE; report it as a failure so it isn't deduped away.
                        val failed = bondingAttempts.remove(bondStateChange.device.address)
                        onBondStateUpdate(bondStateChange.device.address, false, isFailure = failed)
                    }
                }
            }
        }
    }


    private val scanCallback = object : ScanCallback() {
        override fun onScanFailed(errorCode: Int) {
            UniversalBleLogger.logError("OnScanFailed: ${errorCode.parseScanErrorMessage()}")
        }

        override fun onScanResult(callbackType: Int, result: ScanResult) {

            // UniversalBleLogger.logVerbose("onScanResult: $result")
            var serviceUuids: Array<UUID> = arrayOf()
            result.device.uuids?.forEach {
                serviceUuids += it.uuid
            }
            result.scanRecord?.serviceUuids?.forEach {
                if (!serviceUuids.contains(it.uuid)) {
                    serviceUuids += it.uuid
                }
            }

            val name = result.resolvedDeviceName
            val manufacturerDataList = result.manufacturerDataList
            val serviceData = result.serviceData
            // ScanResult.timestampNanos is captured by Android at packet
            // reception. Convert that monotonic value to epoch microseconds
            // before posting to Flutter so main-thread delay is excluded.
            val timestampMicroseconds = System.currentTimeMillis() * 1000 -
                (SystemClock.elapsedRealtimeNanos() - result.timestampNanos) / 1000

            if (!universalBleFilterUtil.filterDevice(
                    name,
                    manufacturerDataList,
                    serviceUuids,
                    result.serviceDataUuids
                )
            ) return


            mainThreadHandler?.post {
                callbackChannel?.onScanResult(
                    UniversalBleScanResult(
                        name = name,
                        deviceId = result.device.address,
                        isPaired = result.device.isBonded(),
                        manufacturerDataList = manufacturerDataList,
                        serviceData = serviceData,
                        rssi = result.rssi.toLong(),
                        services = serviceUuids.map { it.toString() }.toList(),
                        timestamp = timestampMicroseconds / 1000,
                        timestampMicroseconds = timestampMicroseconds,
                        connectable = result.connectableOrNull()
                    )
                ) {}
            }
        }

        override fun onBatchScanResults(results: MutableList<ScanResult>?) {
            UniversalBleLogger.logVerbose("onBatchScanResults: $results")
        }
    }


    override fun onConnectionStateChange(
        gatt: BluetoothGatt,
        status: Int,
        newState: Int,
    ) {
        UniversalBleLogger.logDebug(
            "onConnectionStateChange-> Status: $status ${status.parseHciErrorCode()}, NewState: $newState"
        )

        if (newState == BluetoothGatt.STATE_CONNECTED) {
            // A client replaced by a newer connect() must not report a
            // connection for the address it no longer owns, and neither may one
            // disconnect() is tearing down.
            //
            // A client that is not registered at all is *not* superseded:
            // connectGatt() is given no Handler, so the stack can deliver this
            // callback on a binder thread before connect() reaches
            // gattRegistry.put(gatt). Dropping that event would leave Dart's
            // connect() waiting for a link that is in fact up, and its timeout
            // then tears the link down.
            val owner = gattRegistry.find(gatt.device.address)
            val tracked = gattRegistry.find(gatt)
            if ((owner != null && owner.gatt !== gatt) ||
                tracked?.state == GattClient.State.CLOSING
            ) {
                UniversalBleLogger.logDebug(
                    "CONNECTED ignored from a superseded client <- ${gatt.device.address}"
                )
                return
            }
            val client = if (owner?.gatt === gatt) owner else gattRegistry.put(gatt)
            // A client that kept the link loss open for autoConnect is now on a
            // new link, which inherits nothing from the previous one. An
            // operation the stack accepted just before that loss can be dropped
            // without ever calling back; its entry would then complete with the
            // new link's first callback and every later operation would lag by
            // one. Fail whatever is still attributed to this client — and only
            // to it (#394).
            //
            // Sweep before the link is marked up: the submission gate reads
            // the client state, so a request that lands in a pending collection
            // after this point belongs to the new link and must not be failed
            // here.
            val reconnected = client.state == GattClient.State.AWAITING_RECONNECT
            if (reconnected) {
                failPendingOperations { futureGatt, _ -> futureGatt === gatt }
            }
            client.setState(GattClient.State.CONNECTED)
            mainThreadHandler?.post {
                callbackChannel?.onConnectionChanged(
                    gatt.device.address, true, status.parseHciErrorCode(), status.toConnectionErrorCode(), status.toGattErrorCode()
                ) {}
            }
        } else if (newState == BluetoothGatt.STATE_DISCONNECTED) {
            val deviceId = gatt.device.address
            val client = gattRegistry.find(gatt)
            // Android reports a failed connection attempt the same way, so only
            // a client whose link came up owes a disconnect report. Read before
            // the state below changes: disconnect() has already moved it to
            // CLOSING by the time this callback arrives.
            val wasConnected = client?.takeLinkWasUp() == true
            val closingByRequest = client?.state == GattClient.State.CLOSING
            // Only a client that still reads autoConnect keeps its link open for
            // Android to reconnect it.
            val keepOpen = !closingByRequest && client?.autoConnect == true
            // A client the registry no longer holds as active was replaced,
            // whether by a newer connect() or by disconnect(): its requests and
            // its connection state are not the current connection's to fail or
            // report. Same rule as the close fallback timer in cleanConnection().
            val active = gattRegistry.find(deviceId)
            val superseded = active != null && active.gatt !== gatt

            // Take the link down before the sweep, as the old connected-set based
            // code did: a request submitted while the sweep runs must be refused
            // with `deviceDisconnected`, not registered in a list that was
            // already swept and then dropped by the stack without a callback
            // (#394). The client stays in the active slot until the sweep is
            // done, so `owns` can still tell its requests apart from a
            // replacement published meanwhile.
            client?.setState(
                if (keepOpen) GattClient.State.AWAITING_RECONNECT else GattClient.State.CLOSING
            )

            if (!superseded) {
                // Always clean up internal state (futures, etc.)
                cleanUpConnection(deviceId, gatt)

                // Send connection changed callback
                mainThreadHandler?.post {
                    callbackChannel?.onConnectionChanged(
                        deviceId,
                        false,
                        status.parseHciErrorCode(),
                        status.toConnectionErrorCode(wasConnected),
                        status.toGattErrorCode(),
                    ) {}
                }
            }

            // Only keep the client open when autoConnect should let Android
            // reconnect it; its next STATE_CONNECTED starts a new link.
            if (!keepOpen && (client == null || gattRegistry.finishClose(client))) {
                gatt.disconnect()
                UniversalBleLogger.logDebug("Closing gatt for $deviceId")
                gatt.close()
            }
        }
    }

    override fun onCharacteristicChanged(
        gatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic,
        value: ByteArray,
    ) {
        // A replaced client can keep notifying during its teardown; its values
        // belong to the connection it used to be, not to the one registered now.
        if (!isCurrentClient(gatt)) {
            UniversalBleLogger.logVerbose(
                "NOTIFY ignored from a superseded client <- ${gatt.device.address} ${characteristic.uuid}"
            )
            return
        }
        UniversalBleLogger.logVerbose(
            "NOTIFY <- ${gatt.device.address} ${characteristic.uuid} len=${value.size}"
        )
        mainThreadHandler?.post {
            callbackChannel?.onValueChanged(
                deviceIdArg = gatt.device.address,
                characteristicIdArg = characteristic.uuid.toString(),
                // The same characteristic UUID may exist in several services;
                // the owning service tells the two instances apart.
                serviceIdArg = characteristic.service?.uuid?.toString(),
                valueArg = value,
                timestampArg = System.currentTimeMillis()
            ) {}
        }
    }

    override fun onDescriptorWrite(
        gatt: BluetoothGatt?,
        descriptor: BluetoothGattDescriptor?,
        status: Int,
    ) {
        // No super call: BluetoothGattCallback's default implementations are
        // empty, and calling one from a unit test needs
        // testOptions.unitTests.returnDefaultValues, which would also make
        // every other unstubbed android.jar call in the suite fail silently.
        if (descriptor != null) {
            val future = descriptorWriteOperations.takeOldest {
                it.gatt === gatt &&
                    it.deviceId == gatt?.device?.address &&
                    it.descriptorId == descriptor.uuid.toString() &&
                    it.characteristicId == descriptor.characteristic?.uuid?.toString() &&
                    it.serviceId == descriptor.characteristic?.service?.uuid?.toString()
            }
            if (future != null) {
                postToMainLooper {
                    if (status == BluetoothGatt.GATT_SUCCESS) {
                        future.result(Result.success(Unit))
                    } else {
                        future.result(
                            Result.failure(
                                createFlutterError(
                                    gattStatusToUniversalBleErrorCode(status),
                                    "Failed to write descriptor",
                                    status.toString()
                                )
                            )
                        )
                    }
                }
            }
        }

        if (gatt != null && descriptor != null && descriptor.uuid == ccdCharacteristic) {
            updateSubscriptionState(gatt, descriptor, status)
        }
    }

    private fun updateSubscriptionState(
        gatt: BluetoothGatt,
        descriptor: BluetoothGattDescriptor,
        status: Int,
    ) {
        // Runs on a binder thread (the CCCD write callback): match and remove
        // under the lock, then complete on the main thread, where
        // platform-channel replies must be sent.
        // A replaced connection can report the same address and UUIDs. Only the
        // exact GATT and descriptor that submitted the request own it.
        val future = subscriptionOperations.takeOldest {
            it.gatt === gatt && it.descriptor === descriptor
        } ?: subscriptionOperations.takeOldest {
            // A discoverServices() completing between the CCCD write and its
            // callback rebuilds the service tree, so the framework reports a
            // fresh descriptor object for the same attribute. Match on that
            // identity instead; without it the caller would await forever.
            // The GATT check keeps a replaced connection out.
            it.gatt === gatt && it.descriptor.sameAttributeAs(descriptor)
        }
        if (future == null) {
            return
        }
        postToMainLooper {
            try {
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    future.result(Result.success(Unit))
                } else {
                    future.result(
                        Result.failure(
                            createFlutterError(
                                gattStatusToUniversalBleErrorCode(status),
                                "Failed to update subscription state",
                                status.toString()
                            )
                        )
                    )
                }
            } catch (e: Exception) {
                UniversalBleLogger.logError(
                    "Subscription completion delivery failed: $e"
                )
            }
        }
    }

    private fun isBluetoothAvailable(): Boolean {
        return bluetoothManager.isBluetoothEnabled()
    }

    /// Whether the controller can perform offloaded first-match (on-found)
    /// filtering. Android rejects `CALLBACK_TYPE_FIRST_MATCH` with
    /// `SCAN_FAILED_FEATURE_UNSUPPORTED` unless offloaded filtering is supported
    /// (`BluetoothLeScanner.isSettingsConfigAllowedForScan`). The framework also
    /// checks available hardware tracking filters there, but that check uses a
    /// hidden API, so the Dart layer stays the cross-platform guarantee.
    private fun supportsFirstMatchScan(): Boolean {
        val adapter = bluetoothManager.adapter ?: return false
        return adapter.isOffloadedFilteringSupported
    }

    private fun setCachedServices(deviceId: String, services: List<String>) {
        val cachedServicesSharedPref = context.getSharedPreferences(
            "com.navideck.universal_ble.services",
            Context.MODE_PRIVATE
        )
        cachedServicesSharedPref.edit { putStringSet(deviceId, services.toSet()) }
        cachedServicesMap[deviceId] = services
    }

    private fun getCachedServicesMap(): Map<String, List<String>> {
        val cachedServicesSharedPref = context.getSharedPreferences(
            "com.navideck.universal_ble.services",
            Context.MODE_PRIVATE
        )
        return cachedServicesSharedPref.all.mapValues { (_, value) ->
            (value as? Set<*>)?.map { it.toString() } ?: emptyList()
        }
    }

    /// Depreciated Members, ( Requires to support older android devices )
    @Suppress("OVERRIDE_DEPRECATION", "DEPRECATION")
    override fun onCharacteristicRead(
        gatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic,
        status: Int,
    ) {
        // characteristic.value is null on this legacy callback when the stack
        // failed to unpack the response; passing it through aborted the read.
        onCharacteristicRead(
            gatt,
            characteristic,
            characteristic.value ?: byteArrayOf(),
            status
        )
    }

    @Suppress("OVERRIDE_DEPRECATION", "DEPRECATION")
    override fun onCharacteristicChanged(
        gatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic,
    ) {
        onCharacteristicChanged(
            gatt,
            characteristic,
            characteristic.value ?: byteArrayOf()
        )
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (peripheralPlugin.handleActivityResult(requestCode, resultCode, data)) {
            return true
        }
        if (requestCode == bluetoothEnableRequestCode) {
            val future = bluetoothEnableRequestFuture ?: return false
            future(Result.success(resultCode == Activity.RESULT_OK))
            bluetoothEnableRequestFuture = null
            return true
        } else if (requestCode == bluetoothDisableRequestCode) {
            val future = bluetoothDisableRequestFuture ?: return false
            future(Result.success(resultCode == Activity.RESULT_OK))
            bluetoothDisableRequestFuture = null
            return true
        }
        return false
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        peripheralPlugin.attachActivity(binding.activity)
        binding.addActivityResultListener(this)
        binding.addRequestPermissionsResultListener(this)
        permissionHandler?.attachActivity(binding.activity)
    }

    override fun onDetachedFromActivity() {
        activity = null
        peripheralPlugin.attachActivity(null)
        permissionHandler?.attachActivity(null)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        // Activity will be reattached, keep the reference
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        peripheralPlugin.attachActivity(binding.activity)
        permissionHandler?.attachActivity(binding.activity)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        return permissionHandler?.handlePermissionResult(requestCode, permissions, grantResults)
            ?: false
    }
}

/**
 * Whether [other] addresses the same attribute as this descriptor. The
 * framework resolves the descriptor it reports through the GATT client's
 * current service list, so a `discoverServices()` completing between a CCCD
 * write and its callback hands back new objects for the same attribute.
 */
private fun BluetoothGattDescriptor.sameAttributeAs(
    other: BluetoothGattDescriptor,
): Boolean {
    // A descriptor the framework did not resolve through a characteristic
    // cannot be identified: matching two of them would treat any CCCD as this
    // one.
    val characteristic = characteristic ?: return false
    val otherCharacteristic = other.characteristic ?: return false
    return uuid == other.uuid &&
        characteristic.uuid == otherCharacteristic.uuid &&
        characteristic.service?.uuid == otherCharacteristic.service?.uuid
}
