package com.navideck.universal_ble

import android.annotation.SuppressLint
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
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Context.RECEIVER_EXPORTED
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.ParcelUuid
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger

private const val TAG = "UniversalBlePeripheral"

@SuppressLint("MissingPermission")
class UniversalBlePeripheralPlugin(
    private val applicationContext: Context,
    messenger: BinaryMessenger,
) : UniversalBlePeripheralChannel {
    private var activity: Activity? = null
    private val callback = UniversalBlePeripheralCallback(messenger)
    private val handler = Handler(applicationContext.mainLooper)
    private val bluetoothManager =
        applicationContext.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    private var bluetoothLeAdvertiser: BluetoothLeAdvertiser? = null
    private var gattServer: BluetoothGattServer? = null
    private val bluetoothDevicesMap: MutableMap<String, BluetoothDevice> = HashMap()
    private val listOfDevicesWaitingForBond = mutableListOf<String>()
    private val emptyBytes = byteArrayOf()
    private var advertising: Boolean? = null
    private var receiverRegistered = false

    fun attachActivity(activity: Activity?) {
        this.activity = activity
    }

    fun dispose() {
        if (receiverRegistered) {
            kotlin.runCatching { applicationContext.unregisterReceiver(broadcastReceiver) }
            receiverRegistered = false
        }
        kotlin.runCatching { bluetoothLeAdvertiser?.stopAdvertising(advertiseCallback) }
        gattServer?.close()
        gattServer = null
        bluetoothDevicesMap.clear()
        synchronized(listOfDevicesWaitingForBond) {
            listOfDevicesWaitingForBond.clear()
        }
        clearPeripheralCaches()
    }

    override fun initialize() {
        val adapter = bluetoothManager.adapter
            ?: throw UnsupportedOperationException("Bluetooth is not available.")
        bluetoothLeAdvertiser = adapter.bluetoothLeAdvertiser
            ?: throw UnsupportedOperationException(
                "Bluetooth LE Advertising not supported on this device.",
            )
        gattServer = bluetoothManager.openGattServer(applicationContext, gattServerCallback)
            ?: throw UnsupportedOperationException("gattServer is null, check Bluetooth is ON.")

        if (!receiverRegistered) {
            val intentFilter = IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED)
            intentFilter.addAction(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                applicationContext.registerReceiver(broadcastReceiver, intentFilter, RECEIVER_EXPORTED)
            } else {
                @Suppress("DEPRECATION")
                applicationContext.registerReceiver(broadcastReceiver, intentFilter)
            }
            receiverRegistered = true
        }

        callback.onBleStateChange(isBluetoothEnabled()) {}
    }

    override fun isAdvertising(): Boolean? = advertising

    override fun isSupported(): Boolean {
        val adapter = bluetoothManager.adapter ?: return false
        if (!adapter.isMultipleAdvertisementSupported) {
            throw UnsupportedOperationException(
                "Bluetooth LE Advertising not supported on this device.",
            )
        }
        return true
    }

    override fun addService(service: PeripheralService) {
        gattServer?.addService(service.toGattService())
    }

    override fun removeService(serviceId: String) {
        serviceId.findService()?.let { gattServer?.removeService(it) }
    }

    override fun clearServices() {
        gattServer?.clearServices()
    }

    override fun getServices(): List<String> =
        gattServer?.services?.map { it.uuid.toString() } ?: emptyList()

    override fun startAdvertising(
        services: List<String>,
        localName: String?,
        timeout: Long?,
        manufacturerData: PeripheralManufacturerData?,
        addManufacturerDataInScanResponse: Boolean,
    ) {
        if (!isBluetoothEnabled()) {
            activity?.startActivityForResult(
                Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE),
                0xB1E,
            )
            throw Exception("Bluetooth is not enabled")
        }

        handler.post {
            localName?.let { bluetoothManager.adapter?.name = it }
            val advertiseSettings = AdvertiseSettings.Builder()
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
                .setConnectable(true)
                .setTimeout(timeout?.toInt() ?: 0)
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                .build()

            val advertiseDataBuilder = AdvertiseData.Builder()
                .setIncludeTxPowerLevel(false)
                .setIncludeDeviceName(localName != null)
            val scanResponseBuilder = AdvertiseData.Builder()
                .setIncludeTxPowerLevel(false)
                .setIncludeDeviceName(localName != null)

            manufacturerData?.let {
                if (addManufacturerDataInScanResponse) {
                    scanResponseBuilder.addManufacturerData(
                        it.manufacturerId.toInt(),
                        it.data,
                    )
                } else {
                    advertiseDataBuilder.addManufacturerData(
                        it.manufacturerId.toInt(),
                        it.data,
                    )
                }
            }
            services.forEach { advertiseDataBuilder.addServiceUuid(ParcelUuid.fromString(it)) }

            bluetoothLeAdvertiser?.startAdvertising(
                advertiseSettings,
                advertiseDataBuilder.build(),
                scanResponseBuilder.build(),
                advertiseCallback,
            )
        }
    }

    override fun stopAdvertising() {
        handler.post {
            bluetoothLeAdvertiser?.stopAdvertising(advertiseCallback)
            advertising = false
            callback.onAdvertisingStatusUpdate(false, null) {}
        }
    }

    override fun updateCharacteristic(characteristicId: String, value: ByteArray, deviceId: String?) {
        val characteristic =
            characteristicId.findCharacteristic() ?: throw Exception("Characteristic not found")
        characteristic.value = value
        val targetDevices = synchronized(bluetoothDevicesMap) {
            if (deviceId != null) {
                listOf(bluetoothDevicesMap[deviceId] ?: throw Exception("Device not found"))
            } else {
                bluetoothDevicesMap.values.toList()
            }
        }
        targetDevices.forEach { device ->
            handler.post { gattServer?.notifyCharacteristicChanged(device, characteristic, true) }
        }
    }

    private fun isBluetoothEnabled(): Boolean =
        bluetoothManager.adapter?.isEnabled ?: false

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
        subscribedCharUUID.forEach { charUUID ->
            handler.post {
                callback.onCharacteristicSubscriptionChange(
                    deviceAddress,
                    charUUID,
                    false,
                    device.name,
                ) {}
            }
        }
    }

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartFailure(errorCode: Int) {
            super.onStartFailure(errorCode)
            handler.post {
                val errorMessage = when (errorCode) {
                    ADVERTISE_FAILED_ALREADY_STARTED -> "Already started"
                    ADVERTISE_FAILED_DATA_TOO_LARGE -> "Data too large"
                    ADVERTISE_FAILED_FEATURE_UNSUPPORTED -> "Feature unsupported"
                    ADVERTISE_FAILED_INTERNAL_ERROR -> "Internal error"
                    ADVERTISE_FAILED_TOO_MANY_ADVERTISERS -> "Too many advertisers"
                    else -> "Failed to start advertising: $errorCode"
                }
                callback.onAdvertisingStatusUpdate(false, errorMessage) {}
            }
        }

        override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
            super.onStartSuccess(settingsInEffect)
            advertising = true
            handler.post { callback.onAdvertisingStatusUpdate(true, null) {} }
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
                    if (device.bondState == BluetoothDevice.BOND_NONE) {
                        synchronized(listOfDevicesWaitingForBond) {
                            listOfDevicesWaitingForBond.add(device.address)
                        }
                        device.createBond()
                    } else if (device.bondState == BluetoothDevice.BOND_BONDED) {
                        handler.post { gattServer?.connect(device, true) }
                    }
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
                handler.post { callback.onMtuChange(address, mtu.toLong()) {} }
            }
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
                    offsetArg = offset.toLong(),
                    valueArg = characteristic.value,
                ) { result ->
                    val readResult = result.getOrNull()
                    if (readResult == null) {
                        gattServer?.sendResponse(
                            device, requestId, BluetoothGatt.GATT_FAILURE, 0, emptyBytes,
                        )
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
                    offsetArg = offset.toLong(),
                    valueArg = value,
                ) { writeResponse ->
                    val writeResult = writeResponse.getOrNull()
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
                val value = descriptor.getCacheValue()
                if (value != null) {
                    gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, value)
                } else {
                    gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_FAILURE, 0, emptyBytes)
                }
            }
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice?,
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
            if (descriptor.uuid.toString().lowercase() == peripheralDescriptorCCUUID.lowercase()) {
                val isSubscribed =
                    BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE.contentEquals(value) ||
                        BluetoothGattDescriptor.ENABLE_INDICATION_VALUE.contentEquals(value)
                val characteristicId = descriptor.characteristic.uuid.toString()
                device?.address?.let { address ->
                    handler.post {
                        callback.onCharacteristicSubscriptionChange(
                            address, characteristicId, isSubscribed, device.name,
                        ) {}
                    }
                    synchronized(subscribedCharDevicesMap) {
                        val charList = subscribedCharDevicesMap[address] ?: mutableListOf()
                        if (isSubscribed) {
                            charList.add(characteristicId)
                        } else {
                            charList.remove(characteristicId)
                        }
                        subscribedCharDevicesMap[address] = charList
                    }
                }
            }
            if (responseNeeded) {
                gattServer?.sendResponse(
                    device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value ?: emptyBytes,
                )
            }
        }
    }

    private val broadcastReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                BluetoothAdapter.ACTION_STATE_CHANGED -> {
                    val state = intent.getIntExtra(
                        BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR,
                    )
                    if (state == BluetoothAdapter.STATE_OFF) {
                        handler.post { callback.onBleStateChange(false) {} }
                    } else if (state == BluetoothAdapter.STATE_ON) {
                        handler.post { callback.onBleStateChange(true) {} }
                    }
                }
                BluetoothDevice.ACTION_BOND_STATE_CHANGED -> {
                    val state = intent.getIntExtra(
                        BluetoothDevice.EXTRA_BOND_STATE, BluetoothDevice.ERROR,
                    )
                    val device: BluetoothDevice? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                    }
                    handler.post {
                        callback.onBondStateChange(
                            device?.address ?: "",
                            state.toPeripheralBondState(),
                        ) {}
                    }

                    val waitingForConnection = synchronized(listOfDevicesWaitingForBond) {
                        listOfDevicesWaitingForBond.contains(device?.address)
                    }
                    if (state == BluetoothDevice.BOND_BONDED && device != null && waitingForConnection) {
                        synchronized(listOfDevicesWaitingForBond) {
                            listOfDevicesWaitingForBond.remove(device.address)
                        }
                        synchronized(bluetoothDevicesMap) {
                            bluetoothDevicesMap[device.address] = device
                        }
                        handler.post { gattServer?.connect(device, true) }
                    }
                }
            }
        }
    }
}
