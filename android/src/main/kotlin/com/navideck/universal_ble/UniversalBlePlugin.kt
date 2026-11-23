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
import android.bluetooth.BluetoothStatusCodes
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
import java.util.Collections
import java.util.UUID
import java.util.WeakHashMap
import java.util.concurrent.ConcurrentHashMap
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
    private val discoverServicesFutureList = mutableListOf<DiscoverServicesFuture>()
    private val mtuResultFutureList = mutableListOf<MtuResultFuture>()
    // Protected by mtuResultFutureList's lock. An observed MTU belongs to this
    // GATT client, never to a later connection using the same device address.
    private val negotiatedMtus = WeakHashMap<BluetoothGatt, Int>()
    private val readResultFutureList = mutableListOf<ReadResultFuture>()
    private val writeResultFutureList = mutableListOf<WriteResultFuture>()
    private val readDescriptorResultFutureList = mutableListOf<ReadDescriptorResultFuture>()
    private val writeDescriptorResultFutureList = mutableListOf<WriteDescriptorResultFuture>()
    private val subscriptionResultFutureList = mutableListOf<SubscriptionResultFuture>()
    private val pairResultFutures = mutableMapOf<String, (Result<Boolean>) -> Unit>()

    // Addresses seen go through BOND_BONDING. A return to BOND_NONE while an address is in here is a
    // failed/declined bond (an event), not a steady BOND_NONE, so onBondStateUpdate() marks it as a failure
    // instead of letting Dart's pairing-state dedup swallow it (#325).
    private val bondingAttempts = mutableSetOf<String>()
    private val rssiResultFutureList = mutableListOf<RssiResultFuture>()
    private val autoConnectDevices = mutableSetOf<String>()

    // GATT clients that reached STATE_CONNECTED, so a later STATE_DISCONNECTED can be told
    // apart from a failed connection attempt (Android reports both the same way).
    private val connectedGatts: MutableSet<BluetoothGatt> =
        Collections.newSetFromMap(ConcurrentHashMap<BluetoothGatt, Boolean>())

    // Per plugin instance (one per FlutterEngine): the GATT clients this engine
    // owns (see [GattRegistry]). A connect() here never reuses a client from
    // another engine, and detach releases only this engine's clients.
    private val gattRegistry = GattRegistry()

    // GATT clients that a link loss left open for autoConnect, until they
    // report a connection again. The next STATE_CONNECTED for one of them is a
    // new link, which inherits nothing from the previous one (#394).
    private val awaitingReconnectGatts: MutableSet<BluetoothGatt> =
        Collections.newSetFromMap(ConcurrentHashMap<BluetoothGatt, Boolean>())

    /**
     * When enabled, close every known GATT client on engine detach. The
     * plugin otherwise leaves GATT open, so a killed app keeps the
     * peripheral occupied until its supervision timeout.
     */
    private var closeGattOnDetach = false

    // Clients that disconnect() is tearing down; closed on STATE_DISCONNECTED or by the fallback timer.
    private val closingGatts: MutableSet<BluetoothGatt> =
        Collections.newSetFromMap(ConcurrentHashMap<BluetoothGatt, Boolean>())
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
        if (closeGattOnDetach) gattRegistry.snapshot().forEach(::cleanConnection)
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

        // Note: platformConfig carries platform-specific connection options
        // If already connected, send connected message,
        // if connecting, do nothing
        gattRegistry.find(deviceId)?.let {
            val currentState = bluetoothManager.getConnectionState(it.device, BluetoothProfile.GATT)
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
            // The client below replaces this one, so it will never be the client
            // that reports the reconnect.
            awaitingReconnectGatts.remove(it)
        }

        val shouldAutoConnect = autoConnect ?: false
        if (shouldAutoConnect) {
            autoConnectDevices.add(deviceId)
        } else {
            autoConnectDevices.remove(deviceId)
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
        gattRegistry.put(gatt)
    }

    override fun disconnect(deviceId: String) {
        autoConnectDevices.remove(deviceId)
        val gatt = gattRegistry.find(deviceId)
        if (gatt == null) {
            awaitingReconnectGatts.removeAll { it.device.address == deviceId }
            cleanUpConnection(deviceId)
            mainThreadHandler?.post {
                callbackChannel?.onConnectionChanged(deviceId, false, null, null, null) {}
            }
        } else {
            cleanConnection(gatt)
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
            val gatt = gattRegistry.get(deviceId)
            // Register before readRemoteRssi, as readValue does: its callback
            // arrives on a binder thread, so the entry must already be in the
            // list the disconnect cleanup sweeps — and only while the link is up
            // (#394).
            val future = RssiResultFuture(gatt, deviceId, callback)
            if (!rssiResultFutureList.addIfLinkedUp(gatt, future)) {
                callback(Result.failure(deviceDisconnectedError()))
                return
            }
            val started = try {
                gatt.readRemoteRssi()
            } catch (e: Exception) {
                // A callback or disconnect may already own the reply.
                synchronized(rssiResultFutureList) {
                    if (!rssiResultFutureList.remove(future)) return
                }
                throw e
            }
            if (!started) {
                synchronized(rssiResultFutureList) {
                    if (!rssiResultFutureList.remove(future)) return
                }
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
        val future: RssiResultFuture?
        synchronized(rssiResultFutureList) {
            future = rssiResultFutureList.firstOrNull { it.gatt === gatt }
            future?.let { rssiResultFutureList.remove(it) }
        }
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
            val gatt = gattRegistry.get(deviceId)
            // Register before discoverServices, as readValue does: the result
            // arrives on a binder thread, so the entry must already be in the
            // list the disconnect cleanup sweeps — and only while the link is up
            // (#394).
            val future = DiscoverServicesFuture(gatt, deviceId, withDescriptors, callback)
            if (!discoverServicesFutureList.addIfLinkedUp(gatt, future)) {
                callback(Result.failure(deviceDisconnectedError()))
                return
            }
            if (platformConfig?.android?.clearGattCache == true && !gatt.refreshGattCache()) {
                // A callback or disconnect may already own the reply.
                synchronized(discoverServicesFutureList) {
                    if (!discoverServicesFutureList.remove(future)) return
                }
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
            val started = try {
                gatt.discoverServices()
            } catch (e: Exception) {
                // A callback or disconnect may already own the reply.
                synchronized(discoverServicesFutureList) {
                    if (!discoverServicesFutureList.remove(future)) return
                }
                throw e
            }
            if (!started) {
                synchronized(discoverServicesFutureList) {
                    if (!discoverServicesFutureList.remove(future)) return
                }
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
        val pending: List<DiscoverServicesFuture>
        synchronized(discoverServicesFutureList) {
            pending = discoverServicesFutureList.filter { it.gatt === gatt }
            discoverServicesFutureList.removeAll(pending)
        }
        if (services != null && gattRegistry.find(deviceId) === gatt) {
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
        // Assigned once the CCCD request is registered; declared out here so the
        // error paths below can withdraw it too.
        var pendingFuture: SubscriptionResultFuture? = null
        try {
            UniversalBleLogger.logDebug("SET_NOTIFY -> $deviceId $service $characteristic input=$bleInputProperty")
            val gatt = gattRegistry.get(deviceId)
            val gattCharacteristic: BluetoothGattCharacteristic? =
                gatt.getCharacteristic(service, characteristic)

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

            val descriptor: BluetoothGattDescriptor? =
                gattCharacteristic.getDescriptor(ccdCharacteristic)

            val (value, enable) = when (bleInputProperty) {
                BleInputProperty.NOTIFICATION -> BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE to true
                BleInputProperty.INDICATION -> BluetoothGattDescriptor.ENABLE_INDICATION_VALUE to true
                else -> BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE to false
            }

            // Register before issuing the CCCD write, as readValue does: the
            // write's callback arrives on a binder thread and a future added
            // afterwards is never matched (updateSubscriptionState finds
            // nothing to complete), leaving the Dart call awaiting forever.
            // Every access to the list holds its lock.
            val pending: SubscriptionResultFuture? =
                if (descriptor == null) null else SubscriptionResultFuture(
                    gatt,
                    descriptor,
                    gatt.device.address,
                    callback,
                )
            if (pending != null) {
                // Only register while the link is up (see writeValue): a CCCD
                // write the stack accepts on a disconnected autoConnect client
                // can be dropped without a callback, and the stranded entry
                // would then consume the next subscription's completion (#394).
                if (!subscriptionResultFutureList.addIfLinkedUp(gatt, pending)) {
                    callback(Result.failure(deviceDisconnectedError()))
                    return
                }
                pendingFuture = pending
            } else if (!isLinkUp(gatt)) {
                // No CCCD to write, so there is no pending result to sweep, but
                // setCharacteristicNotification() still succeeds locally on a
                // linkless client and would report a subscription the stack
                // cannot deliver. Refuse it like any other request (#394).
                callback(Result.failure(deviceDisconnectedError()))
                return
            }

            /** Withdraws [pending] so a later callback cannot reply twice. */
            fun withdraw(): Boolean = removeSubscriptionFuture(pending)

            fun fail(error: FlutterError) {
                if (!withdraw()) return
                callback(Result.failure(error))
            }

            if (descriptor != null) {
                // Some devices do not need CCCD to update
                @Suppress("DEPRECATION")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    val status = try {
                        gatt.writeDescriptor(descriptor, value)
                    } catch (e: Exception) {
                        // A callback or disconnect may already own the reply.
                        if (!withdraw()) return
                        throw e
                    }
                    if (status != BluetoothStatusCodes.SUCCESS) {
                        fail(
                            createFlutterError(
                                status.parseBluetoothStatusCodeError()
                                    ?: UniversalBleErrorCode.FAILED,
                                "Failed to update descriptor"
                            )
                        )
                        return
                    }
                } else {
                    descriptor.value = value
                    val started = try {
                        gatt.writeDescriptor(descriptor)
                    } catch (e: Exception) {
                        // A callback or disconnect may already own the reply.
                        if (!withdraw()) return
                        throw e
                    }
                    if (!started) {
                        fail(
                            createFlutterError(
                                UniversalBleErrorCode.FAILED,
                                "Failed to update descriptor"
                            )
                        )
                        return
                    }
                }
            } else {
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
        } catch (e: FlutterError) {
            if (removeSubscriptionFuture(pendingFuture)) callback(Result.failure(e))
        } catch (e: Exception) {
            if (removeSubscriptionFuture(pendingFuture)) {
                callback(
                    Result.failure(
                        createFlutterError(
                            UniversalBleErrorCode.FAILED,
                            "Failed to update subscription state",
                            e.toString()
                        )
                    )
                )
            }
        }
    }

    /**
     * Removes [future] while it is still registered. False means a callback (or
     * a device cleanup) already owns the reply, which must not be sent twice.
     */
    private fun removeSubscriptionFuture(future: SubscriptionResultFuture?): Boolean {
        if (future == null) return true
        synchronized(subscriptionResultFutureList) {
            return subscriptionResultFutureList.remove(future)
        }
    }

    override fun readValue(
        deviceId: String,
        service: String,
        characteristic: String,
        callback: (Result<ByteArray>) -> Unit,
    ) {
        try {
            UniversalBleLogger.logDebug("READ -> $deviceId $service $characteristic")
            val gatt = gattRegistry.get(deviceId)
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
            val readFuture = ReadResultFuture(
                gatt,
                gatt.device.address,
                gattCharacteristic.uuid.toString(),
                gattCharacteristic.service.uuid.toString(),
                callback
            )
            if (!readResultFutureList.addIfLinkedUp(gatt, readFuture)) {
                callback(Result.failure(deviceDisconnectedError()))
                return
            }

            val started = try {
                gatt.readCharacteristic(gattCharacteristic)
            } catch (e: Exception) {
                // A callback or disconnect may already own the reply.
                synchronized(readResultFutureList) {
                    if (!readResultFutureList.remove(readFuture)) return
                }
                throw e
            }
            if (!started) {
                synchronized(readResultFutureList) {
                    if (!readResultFutureList.remove(readFuture)) return
                }
                callback(
                    Result.failure(
                        createFlutterError(
                            UniversalBleErrorCode.CHARACTERISTIC_NOT_FOUND,
                            "$characteristic not found",
                        )
                    )
                )
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
        val future: ReadResultFuture?
        synchronized(readResultFutureList) {
            future = readResultFutureList.firstOrNull {
                it.gatt === gatt &&
                    it.deviceId == deviceId &&
                    it.characteristicId == characteristicId &&
                    it.serviceId == serviceUuid
            }
            future?.let { readResultFutureList.remove(it) }
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
        var writeFuture: WriteResultFuture? = null
        try {
            UniversalBleLogger.logDebug("WRITE -> $deviceId $service $characteristic len=${value.size} property=$bleOutputProperty")
            val gatt = gattRegistry.get(deviceId)
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

            // Checked after the lookups so a caller still gets deviceNotFound,
            // characteristicNotFound and the write-support errors it got before.
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

            val future = WriteResultFuture(
                gatt,
                gatt.device.address,
                gattCharacteristic.uuid.toString(),
                gattCharacteristic.service.uuid.toString(),
                callback
            )

            // Wait for the result. The list is mutated both here (main thread)
            // and in onCharacteristicWrite / cleanUpConnection (Bluetooth
            // binder threads), so every access must hold the lock.
            //
            // Register only while the link is up, and under that same lock: an
            // autoConnect client stays open after a link loss, so the stack can
            // accept a write and then drop it without ever calling
            // onCharacteristicWrite. The orphaned entry would take the next
            // write's completion, and after the reconnect every write would lag
            // by one and time out (#394).
            if (!writeResultFutureList.addIfLinkedUp(gatt, future)) {
                callback(Result.failure(deviceDisconnectedError()))
                return
            }
            writeFuture = future

            val result = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                gatt.writeCharacteristic(gattCharacteristic, value, writeType)
            } else {
                @Suppress("DEPRECATION")
                gattCharacteristic.value = value
                gattCharacteristic.writeType = writeType
                @Suppress("DEPRECATION")
                val status = gatt.writeCharacteristic(gattCharacteristic)
                if (status) BluetoothGatt.GATT_SUCCESS else BluetoothGatt.GATT_FAILURE
            }

            if (result != BluetoothGatt.GATT_SUCCESS) {
                withdrawWriteFuture(future)
                callback(
                    Result.failure(
                        createFlutterError(
                            gattStatusToUniversalBleErrorCode(result),
                            "Failed to write",
                            result.toString()
                        )
                    )
                )
            }
        } catch (e: FlutterError) {
            writeFuture?.let(::withdrawWriteFuture)
            callback(Result.failure(e))
        } catch (e: Exception) {
            // A write the stack refuses by throwing (a characteristic whose
            // service is gone, for example) never reaches onCharacteristicWrite.
            // Fail this call and unregister its result: otherwise the next
            // completion is delivered to the orphaned future and every later
            // write lags by one.
            writeFuture?.let(::withdrawWriteFuture)
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

    private fun withdrawWriteFuture(future: WriteResultFuture) {
        synchronized(writeResultFutureList) {
            writeResultFutureList.remove(future)
        }
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
        val future: WriteResultFuture?
        synchronized(writeResultFutureList) {
            future = writeResultFutureList.firstOrNull {
                it.gatt === gatt &&
                    it.deviceId == gatt?.device?.address &&
                    it.characteristicId == characteristic.uuid.toString() &&
                    it.serviceId == characteristic.service?.uuid?.toString()
            }
            future?.let { writeResultFutureList.remove(it) }
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
            val gatt = gattRegistry.get(deviceId)
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
            val readFuture = ReadDescriptorResultFuture(
                gatt,
                gatt.device.address,
                gattDescriptor.uuid.toString(),
                gattCharacteristic.uuid.toString(),
                gattCharacteristic.service.uuid.toString(),
                callback
            )
            // Register before issuing the read, as readValue does: the response
            // can otherwise arrive before the future is pending, and the link
            // check shares the lock with the disconnect cleanup (#394).
            if (!readDescriptorResultFutureList.addIfLinkedUp(gatt, readFuture)) {
                callback(Result.failure(deviceDisconnectedError()))
                return
            }

            val started = try {
                gatt.readDescriptor(gattDescriptor)
            } catch (e: Exception) {
                // A callback or disconnect may already own the reply.
                synchronized(readDescriptorResultFutureList) {
                    if (!readDescriptorResultFutureList.remove(readFuture)) return
                }
                throw e
            }
            if (!started) {
                synchronized(readDescriptorResultFutureList) {
                    if (!readDescriptorResultFutureList.remove(readFuture)) return
                }
                callback(
                    Result.failure(
                        createFlutterError(
                            UniversalBleErrorCode.READ_FAILED,
                            "Failed to read descriptor"
                        )
                    )
                )
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
        val future: ReadDescriptorResultFuture?
        synchronized(readDescriptorResultFutureList) {
            future = readDescriptorResultFutureList.firstOrNull {
                it.gatt === gatt &&
                    it.deviceId == gatt.device.address &&
                    it.descriptorId == descriptor.uuid.toString() &&
                    it.characteristicId == descriptor.characteristic.uuid.toString() &&
                    it.serviceId == descriptor.characteristic.service.uuid.toString()
            }
            future?.let { readDescriptorResultFutureList.remove(it) }
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
        var writeFuture: WriteDescriptorResultFuture? = null
        try {
            UniversalBleLogger.logDebug("WRITE_DESCRIPTOR -> $deviceId $service $characteristic $descriptor len=${value.size}")
            val gatt = gattRegistry.get(deviceId)
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

            // Checked after the lookups so a caller still gets deviceNotFound and
            // the not-found errors it got before. writeDescriptor does not throw
            // for a long value, but a value over the attribute cap cannot work.
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

            val future = WriteDescriptorResultFuture(
                gatt,
                gatt.device.address,
                gattDescriptor.uuid.toString(),
                gattCharacteristic.uuid.toString(),
                gattCharacteristic.service.uuid.toString(),
                callback
            )

            // Same rule as writeValue: only register while the link is up, under
            // the lock the disconnect cleanup takes, so a request the stack
            // accepts and then drops cannot survive as a stale entry (#394).
            if (!writeDescriptorResultFutureList.addIfLinkedUp(gatt, future)) {
                callback(Result.failure(deviceDisconnectedError()))
                return
            }
            writeFuture = future

            val status = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                gatt.writeDescriptor(gattDescriptor, value)
            } else {
                @Suppress("DEPRECATION")
                gattDescriptor.value = value
                @Suppress("DEPRECATION")
                if (gatt.writeDescriptor(gattDescriptor)) BluetoothGatt.GATT_SUCCESS else BluetoothGatt.GATT_FAILURE
            }

            if (status != BluetoothGatt.GATT_SUCCESS) {
                withdrawWriteDescriptorFuture(future)
                callback(
                    Result.failure(
                        createFlutterError(
                            gattStatusToUniversalBleErrorCode(status),
                            "Failed to write descriptor",
                            status.toString()
                        )
                    )
                )
            }
        } catch (e: FlutterError) {
            writeFuture?.let(::withdrawWriteDescriptorFuture)
            callback(Result.failure(e))
        } catch (e: Exception) {
            // Withdraw the pending result before failing the call, so a refused
            // descriptor write cannot consume the next completion.
            writeFuture?.let(::withdrawWriteDescriptorFuture)
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

    private fun withdrawWriteDescriptorFuture(future: WriteDescriptorResultFuture) {
        synchronized(writeDescriptorResultFutureList) {
            writeDescriptorResultFutureList.remove(future)
        }
    }

    override fun requestMtu(deviceId: String, expectedMtu: Long, callback: (Result<Long>) -> Unit) {
        UniversalBleLogger.logDebug("REQUEST_MTU -> $deviceId expected=$expectedMtu")
        val gatt = try {
            gattRegistry.get(deviceId)
        } catch (e: FlutterError) {
            postMtuResult(callback, Result.failure(e))
            return
        }
        var reusedMtu: Int? = null
        var shouldRequest = false
        var linkUp = false
        synchronized(mtuResultFutureList) {
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
                    val alreadyPending = mtuResultFutureList.any { it.gatt === gatt }
                    // Register before requestMtu: its callback can arrive immediately.
                    mtuResultFutureList.add(MtuResultFuture(deviceId, gatt, callback))
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
        val pending: List<MtuResultFuture>
        synchronized(mtuResultFutureList) {
            result.getOrNull()?.let { negotiatedMtus[gatt] = it.toInt() }
            pending = mtuResultFutureList.filter { it.gatt === gatt }
            mtuResultFutureList.removeAll(pending)
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
            val gatt = gattRegistry.get(deviceId)
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
        gatt != null && gattRegistry.find(gatt.device.address) === gatt

    /**
     * Whether [gatt] has a link the platform can deliver operations on.
     *
     * `connectedGatts` is updated from `onConnectionStateChange` on a binder
     * thread, so an operation must read this inside the same lock that the
     * disconnect cleanup takes: either the check sees the link already gone and
     * refuses the call, or the pending result is registered in time for the
     * cleanup to sweep it. Reading it outside that lock leaves a window where
     * the check passes, cleanup sweeps, and the result is added afterwards —
     * stranded until a later callback completes it one behind (#394).
     */
    private fun isLinkUp(gatt: BluetoothGatt): Boolean = connectedGatts.contains(gatt)

    /**
     * Adds [future] to this pending list while holding its lock, but only if
     * [gatt] still has a live link. Returns whether it was added; a caller that
     * gets false must fail its call with `deviceDisconnected` instead of
     * submitting the operation.
     *
     * Adding under the list's own lock is what closes the race described in
     * [isLinkUp]: the disconnect cleanup sweeps the same list under the same
     * lock.
     */
    private fun <T> MutableList<T>.addIfLinkedUp(gatt: BluetoothGatt, future: T): Boolean =
        synchronized(this) {
            if (isLinkUp(gatt)) {
                add(future)
                true
            } else {
                false
            }
        }

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
        gattRegistry.find(device.address)?.let { gatt ->
            gatt.services?.let { services ->
                updateCallback(services.map { service -> service.uuid.toString() })
                return
            }

            if (gatt.discoverServices()) {
                // Completed by onServicesDiscovered on a binder thread.
                synchronized(discoverServicesFutureList) {
                    discoverServicesFutureList.add(
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
                }
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
            return futureGatt !== gattRegistry.find(deviceId)
        }

        failPendingOperations(::owns)
        // The observed MTU belonged to the link that is gone; the next
        // connection negotiates its own.
        synchronized(mtuResultFutureList) {
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
        val pendingReads: List<ReadResultFuture>
        synchronized(readResultFutureList) {
            pendingReads = readResultFutureList.filter {
                owns(it.gatt, it.deviceId)
            }
            readResultFutureList.removeAll(pendingReads)
        }
        for (future in pendingReads) {
            postToMainLooper {
                try {
                    future.result(Result.failure(error))
                } catch (e: Exception) {
                    UniversalBleLogger.logError("Read completion delivery failed: $e")
                }
            }
        }
        val pendingWrites: List<WriteResultFuture>
        synchronized(writeResultFutureList) {
            pendingWrites = writeResultFutureList.filter {
                owns(it.gatt, it.deviceId)
            }
            writeResultFutureList.removeAll(pendingWrites)
        }
        for (future in pendingWrites) {
            postToMainLooper {
                try {
                    future.result(Result.failure(error))
                } catch (e: Exception) {
                    UniversalBleLogger.logError("Write completion delivery failed: $e")
                }
            }
        }
        val pendingDescriptorReads: List<ReadDescriptorResultFuture>
        synchronized(readDescriptorResultFutureList) {
            pendingDescriptorReads = readDescriptorResultFutureList.filter {
                owns(it.gatt, it.deviceId)
            }
            readDescriptorResultFutureList.removeAll(pendingDescriptorReads)
        }
        for (future in pendingDescriptorReads) {
            postToMainLooper {
                try {
                    future.result(Result.failure(error))
                } catch (e: Exception) {
                    UniversalBleLogger.logError("Read descriptor completion delivery failed: $e")
                }
            }
        }
        val pendingDescriptorWrites: List<WriteDescriptorResultFuture>
        synchronized(writeDescriptorResultFutureList) {
            pendingDescriptorWrites = writeDescriptorResultFutureList.filter {
                owns(it.gatt, it.deviceId)
            }
            writeDescriptorResultFutureList.removeAll(pendingDescriptorWrites)
        }
        for (future in pendingDescriptorWrites) {
            postToMainLooper {
                try {
                    future.result(Result.failure(error))
                } catch (e: Exception) {
                    UniversalBleLogger.logError("Write descriptor completion delivery failed: $e")
                }
            }
        }
        val pendingSubscriptions: List<SubscriptionResultFuture>
        synchronized(subscriptionResultFutureList) {
            pendingSubscriptions = subscriptionResultFutureList.filter {
                owns(it.gatt, it.deviceId)
            }
            subscriptionResultFutureList.removeAll(pendingSubscriptions)
        }
        for (future in pendingSubscriptions) {
            postToMainLooper {
                try {
                    future.result(Result.failure(error))
                } catch (e: Exception) {
                    UniversalBleLogger.logError("Subscription completion delivery failed: $e")
                }
            }
        }
        val pendingMtus: List<MtuResultFuture>
        synchronized(mtuResultFutureList) {
            pendingMtus = mtuResultFutureList.filter {
                owns(it.gatt, it.deviceId)
            }
            mtuResultFutureList.removeAll(pendingMtus)
        }
        for (future in pendingMtus) {
            postMtuResult(future.result, Result.failure(error))
        }
        val pendingDiscoveries: List<DiscoverServicesFuture>
        synchronized(discoverServicesFutureList) {
            pendingDiscoveries = discoverServicesFutureList.filter {
                owns(it.gatt, it.deviceId)
            }
            discoverServicesFutureList.removeAll(pendingDiscoveries)
        }
        for (future in pendingDiscoveries) {
            postToMainLooper {
                try {
                    future.result(Result.failure(error))
                } catch (e: Exception) {
                    UniversalBleLogger.logError(
                        "Discover services completion delivery failed: $e"
                    )
                }
            }
        }
        val pendingRssis: List<RssiResultFuture>
        synchronized(rssiResultFutureList) {
            pendingRssis = rssiResultFutureList.filter {
                owns(it.gatt, it.deviceId)
            }
            rssiResultFutureList.removeAll(pendingRssis)
        }
        for (future in pendingRssis) {
            postToMainLooper {
                try {
                    future.result(Result.failure(error))
                } catch (e: Exception) {
                    UniversalBleLogger.logError("RSSI completion delivery failed: $e")
                }
            }
        }
    }

    private fun cleanConnection(gatt: BluetoothGatt) {
        val deviceId = gatt.device.address
        gattRegistry.remove(gatt)
        awaitingReconnectGatts.remove(gatt)
        cleanUpConnection(deviceId, gatt)
        closingGatts.add(gatt)
        gatt.disconnect()
        // close() runs from onConnectionStateChange once the link is down. A client that never
        // reached CONNECTED gets no callback at all, so release it anyway after a while (#277).
        mainThreadHandler?.postDelayed({
            if (closingGatts.remove(gatt)) {
                UniversalBleLogger.logDebug("No STATE_DISCONNECTED for $deviceId, closing gatt")
                // No callback ever reported the link down, so drop the state that
                // describes it; the closed client must not be taken for connected.
                connectedGatts.remove(gatt)
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
            if ((owner != null && owner !== gatt) || closingGatts.contains(gatt)) {
                UniversalBleLogger.logDebug(
                    "CONNECTED ignored from a superseded client <- ${gatt.device.address}"
                )
                return
            }
            // A client that kept the link loss open for autoConnect is now on a
            // new link, which inherits nothing from the previous one. An
            // operation the stack accepted just before that loss can be dropped
            // without ever calling back; its entry would then complete with the
            // new link's first callback and every later operation would lag by
            // one. Fail whatever is still attributed to this client — and only
            // to it (#394).
            //
            // Sweep before the link is marked up: the submission gate reads
            // connectedGatts, so a request that lands in a pending list after
            // this point belongs to the new link and must not be failed here.
            if (awaitingReconnectGatts.remove(gatt)) {
                failPendingOperations { futureGatt, _ -> futureGatt === gatt }
            }
            connectedGatts.add(gatt)
            mainThreadHandler?.post {
                callbackChannel?.onConnectionChanged(
                    gatt.device.address, true, status.parseHciErrorCode(), status.toConnectionErrorCode(), status.toGattErrorCode()
                ) {}
            }
        } else if (newState == BluetoothGatt.STATE_DISCONNECTED) {
            val deviceId = gatt.device.address
            val wasConnected = connectedGatts.remove(gatt)
            val shouldAutoConnect = autoConnectDevices.contains(deviceId)
            val closingByRequest = closingGatts.remove(gatt)
            // A client the registry no longer holds was replaced, whether by a
            // newer connect() or by disconnect(): its requests and its
            // connection state are not the current connection's to fail or
            // report. Same rule as the close fallback timer in cleanConnection().
            val superseded = gattRegistry.find(deviceId)?.let { it !== gatt } == true

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

            if (closingByRequest || !shouldAutoConnect) {
                // Only keep the client open when autoConnect should let Android reconnect it
                awaitingReconnectGatts.remove(gatt)
                gattRegistry.remove(gatt)
                gatt.disconnect()
                UniversalBleLogger.logDebug("Closing gatt for $deviceId")
                gatt.close()
            } else if (!superseded) {
                // When autoConnect is enabled, keep GATT open for Android to
                // reconnect; its next STATE_CONNECTED starts a new link.
                awaitingReconnectGatts.add(gatt)
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
            val future: WriteDescriptorResultFuture?
            synchronized(writeDescriptorResultFutureList) {
                future = writeDescriptorResultFutureList.firstOrNull {
                    it.gatt === gatt &&
                        it.deviceId == gatt?.device?.address &&
                        it.descriptorId == descriptor.uuid.toString() &&
                        it.characteristicId == descriptor.characteristic?.uuid?.toString() &&
                        it.serviceId == descriptor.characteristic?.service?.uuid?.toString()
                }
                future?.let { writeDescriptorResultFutureList.remove(it) }
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
        val future: SubscriptionResultFuture?
        synchronized(subscriptionResultFutureList) {
            // A replaced connection can report the same address and UUIDs.
            // Only the exact GATT and descriptor that submitted the request own it.
            future = subscriptionResultFutureList.firstOrNull {
                it.gatt === gatt && it.descriptor === descriptor
            } ?: subscriptionResultFutureList.firstOrNull {
                // A discoverServices() completing between the CCCD write and its
                // callback rebuilds the service tree, so the framework reports a
                // fresh descriptor object for the same attribute. Match on that
                // identity instead; without it the caller would await forever.
                // The GATT check keeps a replaced connection out.
                it.gatt === gatt && it.descriptor.sameAttributeAs(descriptor)
            }
            future?.let { subscriptionResultFutureList.remove(it) }
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
