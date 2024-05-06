package com.navideck.universal_ble

import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.*
import android.bluetooth.BluetoothDevice.BOND_BONDED
import android.bluetooth.BluetoothDevice.BOND_NONE
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
import android.os.ParcelUuid
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.*
import java.util.*
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit


private const val TAG = "UniversalBlePlugin"

@SuppressLint("MissingPermission")
class UniversalBlePlugin : UniversalBlePlatformChannel, BluetoothGattCallback(), FlutterPlugin,
    ActivityAware, PluginRegistry.ActivityResultListener {
    private val bluetoothEnableRequestCode = 2342313
    private var callbackChannel: UniversalBleCallbackChannel? = null
    private var mainThreadHandler: Handler? = null
    private lateinit var context: Context
    private var activity: Activity? = null
    private lateinit var bluetoothManager: BluetoothManager
    private val mtuResultFutureList = mutableListOf<MtuResultFuture>()
    private val bleCharacteristicFutureList = mutableListOf<BleCharacteristicFuture>()
    private val discoverServicesFutureList = mutableListOf<DiscoverServicesFuture>()
    private val writeResultFutureList = mutableListOf<WriteResultFuture>()
    private val cachedServicesMap = mutableMapOf<String, List<String>>()
    private val devicesStateMap = mutableMapOf<String, Int>()
    private var bluetoothEnableRequestFuture: ((Result<Boolean>) -> Unit)? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        UniversalBlePlatformChannel.setUp(flutterPluginBinding.binaryMessenger, this)
        callbackChannel = UniversalBleCallbackChannel(flutterPluginBinding.binaryMessenger)
        context = flutterPluginBinding.applicationContext
        mainThreadHandler = Handler(Looper.getMainLooper())
        bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager

        val intentFilter = IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED)
        intentFilter.addAction(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
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

    override fun enableBluetooth(callback: (Result<Boolean>) -> Unit) {
        if (bluetoothManager.adapter.isEnabled) {
            callback(Result.success(true))
            return
        }
        if (bluetoothEnableRequestFuture != null) {
            callback(
                Result.failure(
                    FlutterError("Failed", "Bluetooth enable request in progress", null)
                )
            )
            return
        }
        val enableBtIntent = Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)
        activity?.startActivityForResult(enableBtIntent, bluetoothEnableRequestCode)
        bluetoothEnableRequestFuture = callback
    }

    override fun startScan(filter: UniversalScanFilter?) {
        if (!isBluetoothAvailable()) throw FlutterError(
            "BluetoothNotEnabled",
            "Bluetooth not enabled",
        )

        val builder = ScanSettings.Builder()
        if (Build.VERSION.SDK_INT >= 26) {
            builder.setPhy(ScanSettings.PHY_LE_ALL_SUPPORTED)
            builder.setLegacy(false)
        }
        val settings = builder.build()

        bluetoothManager.adapter.bluetoothLeScanner?.startScan(
            filter?.toScanFilters() ?: emptyList<ScanFilter>(),
            settings,
            scanCallback
        )
    }

    override fun stopScan() {
        if (!isBluetoothAvailable()) throw FlutterError(
            "BluetoothNotEnabled",
            "Bluetooth not enabled",
        )
        // check if already scanning
        bluetoothManager.adapter.bluetoothLeScanner?.stopScan(scanCallback)
    }

    override fun connect(deviceId: String) {
        val currentState = devicesStateMap[deviceId]

        // If already connected, send connected message,
        // if connecting, do nothing
        knownGatts.find { it.device.address == deviceId }?.let {
            if (currentState == BluetoothGatt.STATE_CONNECTED) {
                Log.e(TAG, "$deviceId Already connected")
                mainThreadHandler?.post {
                    callbackChannel?.onConnectionChanged(
                        deviceId,
                        BleConnectionState.Connected.value
                    ) {}
                }
                return
            } else if (currentState == BluetoothGatt.STATE_CONNECTING) {
                throw FlutterError("Connecting", "Connection already in progress", null)
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
        knownGatts.add(gatt)
    }

    override fun disconnect(deviceId: String) {
        // val currentState = devicesStateMap[deviceId]
        // If `disconnect` is called before BluetoothGatt.STATE_CONNECTED or BluetoothGatt.STATE_CONNECTING
        // there will be no `disconnected` message any more from callback
        //        if (currentState != null && currentState != BluetoothGatt.STATE_CONNECTED) {
        //            Log.e(TAG, "$deviceId Already disconnected or disconnecting")
        //            mainThreadHandler?.post {
        //                callbackChannel?.onConnectionChanged(
        //                    deviceId,
        //                    BleConnectionState.Disconnected.value
        //                ) {}
        //            }
        //            return
        //}
        cleanConnection(deviceId.toBluetoothGatt())
    }

    override fun discoverServices(
        deviceId: String,
        callback: (Result<List<UniversalBleService>>) -> Unit,
    ) {
        if (!deviceId.toBluetoothGatt().discoverServices()) {
            callback(Result.failure(FlutterError("Failed", "Failed to discover services", null)))
            return
        }
        discoverServicesFutureList.add(DiscoverServicesFuture(deviceId, callback))
    }

    override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
        if (status != BluetoothGatt.GATT_SUCCESS) {
            discoverServicesFutureList.filter { it.deviceId == gatt.device.address }.forEach {
                discoverServicesFutureList.remove(it)
                it.result(
                    Result.failure(FlutterError("Failed", "Failed to discover services", null))
                )
            }
            return
        }
        setCachedServices(gatt.device.address, gatt.services.map { it.uuid.toString() })
        val universalBleServices = gatt.services.map { service ->
            UniversalBleService(
                uuid = service.uuid.toString(),
                characteristics = service.characteristics.map {
                    UniversalBleCharacteristic(
                        uuid = it.uuid.toString(),
                        properties = it.getPropertiesList()
                    )
                }
            )
        }
        discoverServicesFutureList.filter { it.deviceId == gatt.device.address }.forEach {
            discoverServicesFutureList.remove(it)
            it.result(Result.success(universalBleServices))
        }
    }


    override fun setNotifiable(
        deviceId: String,
        service: String,
        characteristic: String,
        bleInputProperty: Long,
    ) {
        val gatt = deviceId.toBluetoothGatt()
        val gattCharacteristic = gatt.getCharacteristic(service, characteristic)
            ?: throw FlutterError(
                "IllegalArgument",
                "Unknown characteristic: $characteristic",
                null
            )
        gatt.setNotifiable(gattCharacteristic, bleInputProperty)
    }

    override fun readValue(
        deviceId: String,
        service: String,
        characteristic: String,
        callback: (Result<ByteArray>) -> Unit,
    ) {
        try {
            val gatt = deviceId.toBluetoothGatt()
            val gattCharacteristic = gatt.getCharacteristic(service, characteristic)
            if (gattCharacteristic == null) {
                callback(
                    Result.failure(FlutterError("IllegalArgument", "Unknown characteristic", null))
                )
                return
            }
            if (!gatt.readCharacteristic(gattCharacteristic)) {
                callback(
                    Result.failure(unknownCharacteristicError(characteristic))
                )
                return
            }

            bleCharacteristicFutureList.add(
                BleCharacteristicFuture(
                    gatt.device.address,
                    gattCharacteristic.uuid.toString(),
                    gattCharacteristic.service.uuid.toString(),
                    callback
                )
            )
        } catch (e: FlutterError) {
            callback(Result.failure(e))
        }
    }

    override fun onCharacteristicRead(
        gatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic,
        value: ByteArray,
        status: Int,
    ) {
        bleCharacteristicFutureList.filter {
            it.deviceId == gatt.device.address &&
                    it.characteristicId == characteristic.uuid.toString() &&
                    it.serviceId == characteristic.service.uuid.toString()
        }.forEach {
            bleCharacteristicFutureList.remove(it)
            if (status == BluetoothGatt.GATT_SUCCESS) {
                it.result(Result.success(value))
            } else {
                it.result(
                    Result.failure(
                        FlutterError(
                            status.toString(),
                            "Failed to read: (${status.parseGattErrorCode()})",
                            null,
                        )
                    )
                )
            }

        }
    }

    override fun onCharacteristicRead(
        gatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic,
        status: Int,
    ) {
        // Pass data to new api
        onCharacteristicRead(gatt, characteristic, characteristic.value, status)
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
            val gatt = deviceId.toBluetoothGatt()
            val gattCharacteristic = gatt.getCharacteristic(service, characteristic)
            if (gattCharacteristic == null) {
                callback(Result.failure(unknownCharacteristicError(characteristic)))
                return
            }

            var writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
            if (bleOutputProperty == BleOutputProperty.withResponse.value) {
                if (gattCharacteristic.properties and BluetoothGattCharacteristic.PROPERTY_WRITE == 0) {
                    callback(
                        Result.failure(
                            FlutterError(
                                "IllegalArgument",
                                "Characteristic does not support write withResponse",
                                null
                            )
                        )
                    )
                    return
                }
                writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
            } else if (bleOutputProperty == BleOutputProperty.withoutResponse.value) {
                if (gattCharacteristic.properties and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE == 0) {
                    callback(
                        Result.failure(
                            FlutterError(
                                "IllegalArgument",
                                "Characteristic does not support write withoutResponse",
                                null
                            )
                        )
                    )
                    return
                }
                writeType = BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
            }
//        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
//            val result = gatt.writeCharacteristic(gattCharacteristic, value, writeType)
//            Log.v(TAG,"writeResult $characteristic: $result => ${result.parseBluetoothStatusCodeError()}")
//            return
//        }
            gattCharacteristic.value = value
            gattCharacteristic.writeType = writeType
            val result = gatt.writeCharacteristic(gattCharacteristic)
            if (!result) {
                callback(Result.failure(FlutterError("Failed", "Failed to write", null)))
                return
            }
            if (writeType == BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT) {
                // wait for the result
                writeResultFutureList.add(
                    WriteResultFuture(
                        gatt.device.address,
                        gattCharacteristic.uuid.toString(),
                        gattCharacteristic.service.uuid.toString(),
                        callback
                    )
                )
            } else {
                callback(Result.success(Unit))
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
        writeResultFutureList.filter {
            it.deviceId == gatt?.device?.address &&
                    it.characteristicId == characteristic.uuid.toString() &&
                    it.serviceId == characteristic.service.uuid.toString()
        }.forEach {
            writeResultFutureList.remove(it)
            if (status == BluetoothGatt.GATT_SUCCESS) {
                it.result(Result.success(Unit))
            } else {
                it.result(
                    Result.failure(
                        FlutterError(
                            status.toString(),
                            "Failed to write: (${status.parseGattErrorCode()})",
                            null,
                        )
                    )
                )
            }
        }
    }


    override fun requestMtu(deviceId: String, expectedMtu: Long, callback: (Result<Long>) -> Unit) {
        val gatt = deviceId.toBluetoothGatt()
        gatt.requestMtu(expectedMtu.toInt())
        mtuResultFutureList.add(MtuResultFuture(deviceId, callback))
    }

    override fun onMtuChanged(gatt: BluetoothGatt?, mtu: Int, status: Int) {
        val deviceId = gatt?.device?.address ?: return
        mtuResultFutureList.filter { it.deviceId == deviceId }.forEach {
            mtuResultFutureList.remove(it)
            if (status == BluetoothGatt.GATT_SUCCESS) {
                it.result(Result.success(mtu.toLong()))
            } else {
                it.result(Result.failure(FlutterError("Failed to change MTU", null, null)))
            }
        }
    }

    override fun isPaired(deviceId: String, callback: (Result<Boolean>) -> Unit) {
        val remoteDevice: BluetoothDevice =
            bluetoothManager.adapter.getRemoteDevice(deviceId)
        callback(Result.success(remoteDevice.bondState == BOND_BONDED))
    }

    override fun pair(deviceId: String) {
        val remoteDevice =
            bluetoothManager.adapter.getRemoteDevice(deviceId)
        if (remoteDevice.bondState == BOND_NONE) {
            if (!remoteDevice.createBond()) {
                throw FlutterError("Failed", "Failed to pair", null)
            }
        } else {
            throw FlutterError("AlreadyPair", "Already paired", null)
        }
    }

    override fun unPair(deviceId: String) {
        val remoteDevice: BluetoothDevice =
            bluetoothManager.adapter.getRemoteDevice(deviceId)
        if (remoteDevice.bondState == BOND_BONDED) {
            remoteDevice.removeBond()
        }
    }

    override fun getConnectedDevices(
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
                        manufacturerDataHead = null,
                        manufacturerData = null,
                        rssi = null,
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
        } catch (e: InterruptedException) {
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
        knownGatts.find { it.device.address == device.address }?.let {
            it.services?.let { services ->
                updateCallback(services.map { service -> service.uuid.toString() })
                return
            }

            if (it.discoverServices()) {
                discoverServicesFutureList.add(
                    DiscoverServicesFuture(device.address) { uuids: Result<List<UniversalBleService>> ->
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
                        if (!knownGatts.any { it.device.address == device.address }) {
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
                if (!knownGatts.any { it.device.address == device.address }) {
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
        knownGatts.remove(gatt)
        gatt.disconnect()
        bleCharacteristicFutureList.removeAll {
            it.deviceId == gatt.device.address
        }
        mtuResultFutureList.removeAll {
            it.deviceId == gatt.device.address
        }
        discoverServicesFutureList.removeAll {
            it.deviceId == gatt.device.address
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
                val device: BluetoothDevice =
                    intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE) ?: return
                // get pairing failed error
                when (intent.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, BluetoothDevice.ERROR)) {
                    BluetoothDevice.BOND_BONDING -> {
                        Log.v(TAG, "${device.address} BOND_BONDING")
                    }

                    BluetoothDevice.ERROR -> {
                        mainThreadHandler?.post {
                            callbackChannel?.onPairStateChange(
                                device.address,
                                false,
                                "No pairing state received"
                            ) {}
                        }
                    }

                    BOND_BONDED -> {
                        mainThreadHandler?.post {
                            callbackChannel?.onPairStateChange(
                                device.address,
                                true,
                                null
                            ) {}
                        }
                    }


                    BOND_NONE -> {
                        mainThreadHandler?.post {
                            callbackChannel?.onPairStateChange(
                                device.address,
                                false,
                                null
                            ) {}
                        }
                    }
                }
            }
        }
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanFailed(errorCode: Int) {
            Log.e(TAG, "OnScanFailed: ${errorCode.parseScanErrorMessage()}")
        }

        override fun onScanResult(callbackType: Int, result: ScanResult) {
            // Log.v(TAG, "onScanResult: $result")
            var serviceUuids: Array<String> = arrayOf<String>()
            result.device.uuids?.forEach {
                serviceUuids += it.uuid.toString()
            }
            result.scanRecord?.serviceUuids?.forEach {
                if (!serviceUuids.contains(it.uuid.toString())) {
                    serviceUuids += it.uuid.toString()
                }
            }
            mainThreadHandler?.post {
                callbackChannel?.onScanResult(
                    UniversalBleScanResult(
                        name = result.device.name,
                        deviceId = result.device.address,
                        isPaired = result.device.bondState == BOND_BONDED,
                        manufacturerDataHead = result.manufacturerDataHead,
                        rssi = result.rssi.toLong(),
                        services = serviceUuids.toList()
                    )
                ) {}
            }
        }
    
        override fun onBatchScanResults(results: MutableList<ScanResult>?) {
            Log.v(TAG, "onBatchScanResults: $results")
        }
    }


    override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
        devicesStateMap[gatt.device.address] = newState
        if (newState == BluetoothGatt.STATE_CONNECTED && status == BluetoothGatt.GATT_SUCCESS) {
            mainThreadHandler?.post {
                callbackChannel?.onConnectionChanged(
                    gatt.device.address,
                    BleConnectionState.Connected.value
                ) {}
            }
        } else {
            cleanConnection(gatt)
            mainThreadHandler?.post {
                callbackChannel?.onConnectionChanged(
                    gatt.device.address,
                    BleConnectionState.Disconnected.value
                ) {}
            }
        }
    }

    override fun onCharacteristicChanged(
        gatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic,
    ) {
        mainThreadHandler?.post {
            callbackChannel?.onValueChanged(
                deviceIdArg = gatt.device.address,
                characteristicIdArg = characteristic.uuid.toString(),
                valueArg = characteristic.value
            ) {}
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
        cachedServicesSharedPref.edit().putStringSet(deviceId, services.toSet()).apply()
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

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == bluetoothEnableRequestCode) {
            val future = bluetoothEnableRequestFuture ?: return false
            future(Result.success(resultCode == Activity.RESULT_OK))
            bluetoothEnableRequestFuture = null
            return true
        }
        return false
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onDetachedFromActivityForConfigChanges() {}
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {}
}








