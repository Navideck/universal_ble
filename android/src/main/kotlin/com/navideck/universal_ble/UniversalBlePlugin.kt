package com.navideck.universal_ble

import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothDevice.BOND_BONDED
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothStatusCodes
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Context.RECEIVER_EXPORTED
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import androidx.core.content.edit


@SuppressLint("MissingPermission")
class UniversalBlePlugin : UniversalBlePlatformChannel, BluetoothGattCallback(), FlutterPlugin,
    ActivityAware, PluginRegistry.ActivityResultListener,
    PluginRegistry.RequestPermissionsResultListener {
    private val bluetoothEnableRequestCode = 2342313
    private val bluetoothDisableRequestCode = 2342414
    private val permissionRequestCode = 2342515
    private var permissionHandler: PermissionHandler? = null
    private var callbackChannel: UniversalBleCallbackChannel? = null
    private var mainThreadHandler: Handler? = null
    private lateinit var context: Context
    private var activity: Activity? = null
    private lateinit var bluetoothManager: BluetoothManager
    private lateinit var safeScanner: SafeScanner
    private val cachedServicesMap = mutableMapOf<String, List<String>>()
    private val universalBleFilterUtil = UniversalBleFilterUtil()

    // Flutter Futures
    private var bluetoothEnableRequestFuture: ((Result<Boolean>) -> Unit)? = null
    private var bluetoothDisableRequestFuture: ((Result<Boolean>) -> Unit)? = null
    private val discoverServicesFutureList = mutableListOf<DiscoverServicesFuture>()
    private val mtuResultFutureList = mutableListOf<MtuResultFuture>()
    private val readResultFutureList = mutableListOf<ReadResultFuture>()
    private val writeResultFutureList = mutableListOf<WriteResultFuture>()
    private val subscriptionResultFutureList = mutableListOf<SubscriptionResultFuture>()
    private val pairResultFutures = mutableMapOf<String, (Result<Boolean>) -> Unit>()
    private val rssiResultFutureList = mutableListOf<RssiResultFuture>()

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        UniversalBlePlatformChannel.setUp(flutterPluginBinding.binaryMessenger, this)
        callbackChannel = UniversalBleCallbackChannel(flutterPluginBinding.binaryMessenger)
        context = flutterPluginBinding.applicationContext
        mainThreadHandler = Handler(Looper.getMainLooper())
        bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        safeScanner = SafeScanner(bluetoothManager)

        val intentFilter = IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED)
        intentFilter.addAction(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(broadcastReceiver, intentFilter, RECEIVER_EXPORTED)
        } else {
            context.registerReceiver(broadcastReceiver, intentFilter)
        }
        cachedServicesMap.putAll(getCachedServicesMap())
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        bluetoothManager.adapter.bluetoothLeScanner?.stopScan(scanCallback)
        context.unregisterReceiver(broadcastReceiver)
        callbackChannel = null
        mainThreadHandler = null
    }

    override fun getBluetoothAvailabilityState(callback: (Result<Long>) -> Unit) {
        callback(
            Result.success(
                bluetoothManager.adapter?.state?.toAvailabilityState()
                    ?: AvailabilityState.Unknown.value
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

    override fun startScan(filter: UniversalScanFilter?) {
        if (!isBluetoothAvailable()) throw createFlutterError(
            UniversalBleErrorCode.BLUETOOTH_NOT_ENABLED,
            "Bluetooth not enabled"
        )

        val builder = ScanSettings.Builder()
        if (Build.VERSION.SDK_INT >= 26) {
            builder.setPhy(ScanSettings.PHY_LE_ALL_SUPPORTED)
            builder.setLegacy(false)
        }
        val settings = builder.build()

        val usesCustomFilters = filter?.usesCustomFilters() ?: false

        try {
            val filterServices = filter?.withServices?.toUUIDList() ?: emptyList()
            var scanFilters = emptyList<ScanFilter>()

            // Set custom scan filter only if required
            if (usesCustomFilters) {
                UniversalBleLogger.logError("Using Custom Filters")
                universalBleFilterUtil.scanFilter = filter
                universalBleFilterUtil.serviceFilterUUIDS = filterServices
            } else {
                universalBleFilterUtil.scanFilter = null
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

    override fun connect(deviceId: String) {
        // If already connected, send connected message,
        // if connecting, do nothing
        deviceId.findGatt()?.let {
            val currentState = bluetoothManager.getConnectionState(it.device, BluetoothProfile.GATT)
            if (currentState == BluetoothGatt.STATE_CONNECTED) {
                UniversalBleLogger.logError("$deviceId Already connected")
                mainThreadHandler?.post {
                    callbackChannel?.onConnectionChanged(deviceId, true, null) {}
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
                false,
                this,
                BluetoothDevice.TRANSPORT_LE
            )
        } else {
            remoteDevice.connectGatt(context, false, this)
        }
        gatt.saveCacheIfNeeded()
    }

    override fun disconnect(deviceId: String) {
        val gatt = deviceId.findGatt()
        if (gatt == null) {
            mainThreadHandler?.post {
                callbackChannel?.onConnectionChanged(deviceId, false, null) {}
            }
        } else {
            cleanConnection(gatt)
        }
    }

    override fun getConnectionState(deviceId: String): Long {
        try {
            val connectionState = bluetoothManager.getConnectionState(
                bluetoothManager.adapter.getRemoteDevice(deviceId),
                BluetoothProfile.GATT
            )
            return if (deviceId.isKnownGatt() || connectionState == BluetoothGatt.STATE_DISCONNECTED || connectionState == BluetoothGatt.STATE_DISCONNECTING) {
                connectionState.toBleConnectionState().value
            } else {
                // Might be connected with device, but not with app
                UniversalBleLogger.logError("Device might be connected but not known to this app")
                BleConnectionState.Disconnected.value
            }
        } catch (e: Exception) {
            return BleConnectionState.Disconnected.value
        }
    }

    override fun setLogLevel(logLevel: UniversalBleLogLevel) {
        UniversalBleLogger.setLogLevel(logLevel)
    }

    override fun readRssi(deviceId: String, callback: (Result<Long>) -> Unit) {
        try {
            val gatt = deviceId.toBluetoothGatt()
            if (gatt.readRemoteRssi()) {
                rssiResultFutureList.add(RssiResultFuture(deviceId, callback))
            } else {
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
        rssiResultFutureList.removeAll {
            if (it.deviceId == deviceId) {
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    it.result(Result.success(rssi.toLong()))
                } else {
                    it.result(
                        Result.failure(
                            createFlutterError(
                                UniversalBleErrorCode.FAILED,
                                "Failed to read RSSI"
                            )
                        )
                    )
                }
                true
            } else {
                false
            }
        }
    }

    override fun discoverServices(
        deviceId: String,
        withDescriptors: Boolean,
        callback: (Result<List<UniversalBleService>>) -> Unit,
    ) {
        try {
            val gatt = deviceId.toBluetoothGatt()
            if (gatt.discoverServices()) {
                discoverServicesFutureList.add(
                    DiscoverServicesFuture(
                        deviceId,
                        withDescriptors,
                        callback
                    )
                )
            } else {
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
        if (status != BluetoothGatt.GATT_SUCCESS) {
            discoverServicesFutureList.removeAll {
                if (it.deviceId == gatt.device.address) {
                    it.result(
                        Result.failure(
                            createFlutterError(
                                UniversalBleErrorCode.FAILED,
                                "Failed to discover services"
                            )
                        )
                    )
                    true
                } else {
                    false
                }
            }
            return
        }
        setCachedServices(gatt.device.address, gatt.services.map { it.uuid.toString() })
        discoverServicesFutureList.removeAll {
            if (it.deviceId == gatt.device.address) {
                it.result(Result.success(gatt.services.map { service ->
                    UniversalBleService(
                        uuid = service.uuid.toString(),
                        characteristics = service.characteristics.map { char ->
                            UniversalBleCharacteristic(
                                uuid = char.uuid.toString(),
                                properties = char.getPropertiesList(),
                                descriptors = if (it.withDescriptors) char.descriptors.map { descriptor ->
                                    UniversalBleDescriptor(descriptor.uuid.toString())
                                } else listOf()
                            )
                        }
                    )
                }))
                true
            } else {
                false
            }
        }
    }


    override fun setNotifiable(
        deviceId: String,
        service: String,
        characteristic: String,
        bleInputProperty: Long,
        callback: (Result<Unit>) -> Unit,
    ) {
        try {
            UniversalBleLogger.logDebug("SET_NOTIFY -> $deviceId $service $characteristic input=$bleInputProperty")
            val gatt = deviceId.toBluetoothGatt()
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

            val bleInputPropertyEnum: BleInputProperty =
                BleInputProperty.entries.first { it.value == bleInputProperty }

            val (value, enable) = when (bleInputPropertyEnum) {
                BleInputProperty.Notification -> BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE to true
                BleInputProperty.Indication -> BluetoothGattDescriptor.ENABLE_INDICATION_VALUE to true
                else -> BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE to false
            }

            if (descriptor != null) {
                // Some devices do not need CCCD to update
                @Suppress("DEPRECATION")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    val status = gatt.writeDescriptor(descriptor, value)
                    if (status != BluetoothStatusCodes.SUCCESS) {
                        callback(
                            Result.failure(
                                createFlutterError(
                                    status.parseBluetoothStatusCodeError()
                                        ?: UniversalBleErrorCode.FAILED,
                                    "Failed to update descriptor"
                                )
                            )
                        )
                        return
                    }
                } else {
                    descriptor.value = value
                    if (!gatt.writeDescriptor(descriptor)) {
                        callback(
                            Result.failure(
                                createFlutterError(
                                    UniversalBleErrorCode.FAILED,
                                    "Failed to update descriptor"
                                )
                            )
                        )
                        return
                    }
                }
            } else {
                UniversalBleLogger.logDebug("CCCD Descriptor not found")
            }

            if (gatt.setCharacteristicNotification(gattCharacteristic, enable)) {
                if (descriptor != null) {
                    subscriptionResultFutureList.add(
                        SubscriptionResultFuture(
                            gatt.device.address,
                            gattCharacteristic.uuid.toString(),
                            gattCharacteristic.service.uuid.toString(),
                            callback
                        )
                    )
                } else {
                    callback(Result.success(Unit))
                }
            } else {
                callback(
                    Result.failure(
                        createFlutterError(
                            UniversalBleErrorCode.FAILED,
                            "Failed to update subscription state"
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
                        UniversalBleErrorCode.FAILED,
                        "Failed to update subscription state",
                        e.toString()
                    )
                )
            )
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
            val gatt = deviceId.toBluetoothGatt()
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
            if (!gatt.readCharacteristic(gattCharacteristic)) {
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

            readResultFutureList.add(
                ReadResultFuture(
                    gatt.device.address,
                    gattCharacteristic.uuid.toString(),
                    gattCharacteristic.service.uuid.toString(),
                    callback
                )
            )
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
        readResultFutureList.removeAll {
            if (it.deviceId == gatt.device.address &&
                it.characteristicId == characteristic.uuid.toString() &&
                it.serviceId == characteristic.service.uuid.toString()
            ) {
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    it.result(Result.success(value))
                } else {
                    UniversalBleLogger.logError(
                        "READ_FAILED <- ${gatt.device.address} ${characteristic.uuid} status=$status"
                    )
                    it.result(
                        Result.failure(
                            createFlutterError(
                                gattStatusToUniversalBleErrorCode(status),
                                "Failed to read",
                                status.toString()
                            )
                        )
                    )
                }
                true
            } else {
                false
            }
        }
    }

    override fun writeValue(
        deviceId: String,
        service: String,
        characteristic: String,
        value: ByteArray,
        bleOutputProperty: Long,
        callback: (Result<Unit>) -> Unit,
    ) {
        try {
            UniversalBleLogger.logDebug("WRITE -> $deviceId $service $characteristic len=${value.size} property=$bleOutputProperty")
            val gatt = deviceId.toBluetoothGatt()
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
            if (bleOutputProperty == BleOutputProperty.WithResponse.value) {
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
            } else if (bleOutputProperty == BleOutputProperty.WithoutResponse.value) {
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


            val writeFuture = WriteResultFuture(
                gatt.device.address,
                gattCharacteristic.uuid.toString(),
                gattCharacteristic.service.uuid.toString(),
                callback
            )

            // Wait for the result
            writeResultFutureList.add(writeFuture)

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
                writeResultFutureList.remove(writeFuture)
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
            callback(Result.failure(e))
        }
    }

    override fun onCharacteristicWrite(
        gatt: BluetoothGatt?,
        characteristic: BluetoothGattCharacteristic,
        status: Int,
    ) {
        writeResultFutureList.removeAll {
            if (it.deviceId == gatt?.device?.address &&
                it.characteristicId == characteristic.uuid.toString() &&
                it.serviceId == characteristic.service.uuid.toString()
            ) {
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    it.result(Result.success(Unit))
                } else {
                    UniversalBleLogger.logError(
                        "WRITE_FAILED <- ${gatt?.device?.address} ${characteristic.uuid} status=$status"
                    )
                    it.result(
                        Result.failure(
                            createFlutterError(
                                gattStatusToUniversalBleErrorCode(status),
                                "Failed to write",
                                status.toString()
                            )
                        )
                    )
                }
                true
            } else {
                false
            }
        }
    }


    override fun requestMtu(deviceId: String, expectedMtu: Long, callback: (Result<Long>) -> Unit) {
        UniversalBleLogger.logDebug("REQUEST_MTU -> $deviceId expected=$expectedMtu")
        try {
            val gatt = deviceId.toBluetoothGatt()
            gatt.requestMtu(expectedMtu.toInt())
            mtuResultFutureList.add(MtuResultFuture(deviceId, callback))
        } catch (e: FlutterError) {
            callback(Result.failure(e))
        }
    }

    override fun onMtuChanged(gatt: BluetoothGatt?, mtu: Int, status: Int) {
        val deviceId = gatt?.device?.address ?: return
        mtuResultFutureList.removeAll {
            if (it.deviceId == deviceId) {
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    it.result(Result.success(mtu.toLong()))
                } else {
                    it.result(
                        Result.failure(
                            createFlutterError(
                                UniversalBleErrorCode.FAILED,
                                "Failed to change MTU"
                            )
                        )
                    )
                }
                true
            } else {
                false
            }
        }
    }

    override fun isPaired(deviceId: String, callback: (Result<Boolean>) -> Unit) {
        val remoteDevice: BluetoothDevice =
            bluetoothManager.adapter.getRemoteDevice(deviceId)
        callback(Result.success(remoteDevice.bondState == BOND_BONDED))
    }

    override fun pair(deviceId: String, callback: (Result<Boolean>) -> Unit) {
        try {
            val remoteDevice = bluetoothManager.adapter.getRemoteDevice(deviceId)
            val pendingFuture = pairResultFutures.remove(deviceId)

            // If already paired, return and complete pending futures
            if (remoteDevice.bondState == BOND_BONDED) {
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

    override fun unPair(deviceId: String) {
        val remoteDevice: BluetoothDevice =
            bluetoothManager.adapter.getRemoteDevice(deviceId)
        if (remoteDevice.bondState == BOND_BONDED) {
            remoteDevice.removeBond()
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
                    UniversalBleScanResult(
                        name = it.name,
                        deviceId = it.address,
                        isPaired = it.bondState == BOND_BONDED,
                        manufacturerDataList = null,
                        rssi = null,
                        timestamp = System.currentTimeMillis()
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
        device.address.findGatt()?.let { gatt ->
            gatt.services?.let { services ->
                updateCallback(services.map { service -> service.uuid.toString() })
                return
            }

            if (gatt.discoverServices()) {
                discoverServicesFutureList.add(
                    DiscoverServicesFuture(
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
                        if (!device.address.isKnownGatt()) {
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
                if (!device.address.isKnownGatt()) {
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

    private fun cleanConnection(gatt: BluetoothGatt) {
        gatt.removeCache()
        gatt.disconnect()
        val deviceDisconnectedError: FlutterError = createFlutterError(
            UniversalBleErrorCode.DEVICE_DISCONNECTED,
            "Device Disconnected",
        )
        readResultFutureList.removeAll {
            if (it.deviceId == gatt.device.address) {
                it.result(Result.failure(deviceDisconnectedError))
                true
            } else {
                false
            }
        }
        writeResultFutureList.removeAll {
            if (it.deviceId == gatt.device.address) {
                it.result(Result.failure(deviceDisconnectedError))
                true
            } else {
                false
            }
        }
        subscriptionResultFutureList.removeAll {
            if (it.deviceId == gatt.device.address) {
                it.result(Result.failure(deviceDisconnectedError))
                true
            } else {
                false
            }
        }
        mtuResultFutureList.removeAll {
            if (it.deviceId == gatt.device.address) {
                it.result(Result.failure(deviceDisconnectedError))
                true
            } else {
                false
            }
        }
        discoverServicesFutureList.removeAll {
            if (it.deviceId == gatt.device.address) {
                it.result(Result.failure(deviceDisconnectedError))
                true
            } else {
                false
            }
        }
        rssiResultFutureList.removeAll {
            if (it.deviceId == gatt.device.address) {
                it.result(Result.failure(deviceDisconnectedError))
                true
            } else {
                false
            }
        }
    }

    private fun onBondStateUpdate(deviceId: String, bonded: Boolean, error: String? = null) {
        val future = pairResultFutures.remove(deviceId)
        future?.let { it(Result.success(bonded)) }
        mainThreadHandler?.post {
            callbackChannel?.onPairStateChange(deviceId, bonded, error) {}
        }
    }

    private val broadcastReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == BluetoothAdapter.ACTION_STATE_CHANGED) {
                mainThreadHandler?.post {
                    callbackChannel?.onAvailabilityChanged(
                        bluetoothManager.adapter?.state?.toAvailabilityState()
                            ?: AvailabilityState.Unknown.value
                    ) {}
                }
            } else if (intent.action == BluetoothDevice.ACTION_BOND_STATE_CHANGED) {
                val device: BluetoothDevice? =
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        intent.getParcelableExtra(
                            BluetoothDevice.EXTRA_DEVICE,
                            BluetoothDevice::class.java
                        )
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                    }
                if (device == null) {
                    UniversalBleLogger.logError("No device found in ACTION_BOND_STATE_CHANGED intent")
                    return
                }
                // get pairing failed error
                when (intent.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, BluetoothDevice.ERROR)) {
                    BluetoothDevice.BOND_BONDING -> {
                        UniversalBleLogger.logVerbose("${device.address} BOND_BONDING")
                    }

                    BOND_BONDED -> {
                        onBondStateUpdate(device.address, true)
                    }

                    BluetoothDevice.ERROR -> {
                        onBondStateUpdate(device.address, false, "Failed to Pair")
                    }

                    BluetoothDevice.BOND_NONE -> {
                        UniversalBleLogger.logError("${device.address} BOND_NONE")
                        onBondStateUpdate(device.address, false)
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

            val name = result.device.name
            val manufacturerDataList = result.manufacturerDataList

            if (!universalBleFilterUtil.filterDevice(
                    name,
                    manufacturerDataList,
                    serviceUuids
                )
            ) return


            mainThreadHandler?.post {
                callbackChannel?.onScanResult(
                    UniversalBleScanResult(
                        name = result.device.name,
                        deviceId = result.device.address,
                        isPaired = result.device.bondState == BOND_BONDED,
                        manufacturerDataList = manufacturerDataList,
                        rssi = result.rssi.toLong(),
                        services = serviceUuids.map { it.toString() }.toList(),
                        timestamp = System.currentTimeMillis()
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
            mainThreadHandler?.post {
                callbackChannel?.onConnectionChanged(
                    gatt.device.address, true, status.parseHciErrorCode()
                ) {}
            }
        } else if (newState == BluetoothGatt.STATE_DISCONNECTED) {
            cleanConnection(gatt)
            mainThreadHandler?.post {
                callbackChannel?.onConnectionChanged(
                    gatt.device.address, false, status.parseHciErrorCode()
                ) {}
            }
            UniversalBleLogger.logDebug("Closing gatt for ${gatt.device.name}")
            gatt.close()
        }
    }

    override fun onCharacteristicChanged(
        gatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic,
        value: ByteArray,
    ) {
        UniversalBleLogger.logVerbose(
            "NOTIFY <- ${gatt.device.address} ${characteristic.uuid} len=${value.size}"
        )
        mainThreadHandler?.post {
            callbackChannel?.onValueChanged(
                deviceIdArg = gatt.device.address,
                characteristicIdArg = characteristic.uuid.toString(),
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
        super.onDescriptorWrite(gatt, descriptor, status)
        if (descriptor?.uuid.toString() == ccdCharacteristic.toString()) {
            val char: String? = descriptor?.characteristic?.uuid?.toString()
            val service: String? = descriptor?.characteristic?.service?.uuid?.toString()
            val deviceId: String? = gatt?.device?.address
            if (deviceId != null && char != null && service != null) {
                updateSubscriptionState(deviceId, char, service, status)
            }
        }
    }

    private fun updateSubscriptionState(
        deviceId: String,
        characteristic: String,
        service: String,
        status: Int,
    ) {
        subscriptionResultFutureList.removeAll {
            if (it.deviceId == deviceId &&
                it.characteristicId == characteristic &&
                it.serviceId == service
            ) {
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    it.result(
                        Result.failure(
                            createFlutterError(
                                gattStatusToUniversalBleErrorCode(status),
                                "Failed to update subscription state",
                                status.toString()
                            )
                        )
                    )
                } else {
                    it.result(Result.success(Unit))
                }
                true
            } else {
                false
            }
        }
    }

    private fun isBluetoothAvailable(): Boolean {
        return bluetoothManager.adapter.isEnabled
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
        onCharacteristicRead(gatt, characteristic, characteristic.value, status)
    }

    @Suppress("OVERRIDE_DEPRECATION", "DEPRECATION")
    override fun onCharacteristicChanged(
        gatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic,
    ) {
        onCharacteristicChanged(gatt, characteristic, characteristic.value)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
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
        permissionHandler = PermissionHandler(context, binding.activity, permissionRequestCode)
        binding.addActivityResultListener(this)
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activity = null
        permissionHandler = null
    }

    override fun onDetachedFromActivityForConfigChanges() {}
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        permissionHandler = PermissionHandler(context, binding.activity, permissionRequestCode)
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