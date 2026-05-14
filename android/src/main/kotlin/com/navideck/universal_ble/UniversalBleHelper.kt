package com.navideck.universal_ble

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothStatusCodes
import android.bluetooth.le.ScanCallback.SCAN_FAILED_ALREADY_STARTED
import android.bluetooth.le.ScanCallback.SCAN_FAILED_APPLICATION_REGISTRATION_FAILED
import android.bluetooth.le.ScanCallback.SCAN_FAILED_FEATURE_UNSUPPORTED
import android.bluetooth.le.ScanCallback.SCAN_FAILED_INTERNAL_ERROR
import android.bluetooth.le.ScanCallback.SCAN_FAILED_OUT_OF_HARDWARE_RESOURCES
import android.bluetooth.le.ScanCallback.SCAN_FAILED_SCANNING_TOO_FREQUENTLY
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Context.RECEIVER_EXPORTED
import android.content.Context.RECEIVER_NOT_EXPORTED
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.util.Log
import android.util.SparseArray
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.UUID
import androidx.core.util.size

private const val TAG = "UniversalBlePlugin"

private val knownGatts = mutableMapOf<String, BluetoothGatt>()
val ccdCharacteristic: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

data class BondStateChange(
    val device: BluetoothDevice,
    val state: Int,
)


fun Int.toBleConnectionState(): BleConnectionState {
    return when (this) {
        BluetoothGatt.STATE_CONNECTED -> BleConnectionState.CONNECTED
        BluetoothGatt.STATE_CONNECTING -> BleConnectionState.CONNECTING
        BluetoothGatt.STATE_DISCONNECTING -> BleConnectionState.DISCONNECTING
        BluetoothGatt.STATE_DISCONNECTED -> BleConnectionState.DISCONNECTED
        else -> BleConnectionState.DISCONNECTED
    }
}

fun List<String>.toUUIDList(): List<UUID> {
    return this.map { UUID.fromString(it) }
}


fun String.toBluetoothGatt(): BluetoothGatt {
    return this.findGatt()
        ?: throw createFlutterError(
            UniversalBleErrorCode.DEVICE_NOT_FOUND,
            "Unknown deviceId: $this",
        )
}

fun String.isKnownGatt(): Boolean {
    return this.findGatt() != null
}

fun String.findGatt(): BluetoothGatt? {
    return knownGatts[this]
}

fun BluetoothManager.isBluetoothEnabled(): Boolean {
    return adapter?.isEnabled == true
}

fun Intent.getBluetoothDeviceCompat(): BluetoothDevice? {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
    } else {
        @Suppress("DEPRECATION")
        getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
    }
}

fun Intent.getBondStateChange(): BondStateChange? {
    if (action != BluetoothDevice.ACTION_BOND_STATE_CHANGED) return null
    val device = getBluetoothDeviceCompat() ?: return null
    val state = getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, BluetoothDevice.ERROR)
    return BondStateChange(device, state)
}

fun BluetoothDevice.isBonded(): Boolean = bondState == BluetoothDevice.BOND_BONDED

fun Context.registerReceiverCompat(
    receiver: BroadcastReceiver,
    filter: IntentFilter,
    exported: Boolean,
) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        val receiverFlag = if (exported) RECEIVER_EXPORTED else RECEIVER_NOT_EXPORTED
        registerReceiver(receiver, filter, receiverFlag)
    } else {
        @Suppress("DEPRECATION")
        registerReceiver(receiver, filter)
    }
}

fun BluetoothGatt.saveCacheIfNeeded() {
    knownGatts[this.device.address] = this
}

fun BluetoothGatt.removeCache() {
    knownGatts.remove(this.device.address)
}


fun Int.toAvailabilityState(): AvailabilityState {
    return when (this) {
        BluetoothAdapter.STATE_OFF -> AvailabilityState.POWERED_OFF
        BluetoothAdapter.STATE_ON -> AvailabilityState.POWERED_ON
        BluetoothAdapter.STATE_TURNING_ON -> AvailabilityState.RESETTING
        BluetoothAdapter.STATE_TURNING_OFF -> AvailabilityState.RESETTING
        else -> AvailabilityState.UNKNOWN
    }
}

fun Int.parseScanErrorMessage(): String {
    return when (this) {
        SCAN_FAILED_ALREADY_STARTED -> "SCAN_FAILED_ALREADY_STARTED"
        SCAN_FAILED_APPLICATION_REGISTRATION_FAILED -> "SCAN_FAILED_APPLICATION_REGISTRATION_FAILED"
        SCAN_FAILED_FEATURE_UNSUPPORTED -> "SCAN_FAILED_FEATURE_UNSUPPORTED"
        SCAN_FAILED_INTERNAL_ERROR -> "SCAN_FAILED_INTERNAL_ERROR"
        SCAN_FAILED_OUT_OF_HARDWARE_RESOURCES -> "SCAN_FAILED_OUT_OF_HARDWARE_RESOURCES"
        SCAN_FAILED_SCANNING_TOO_FREQUENTLY -> "SCAN_FAILED_SCANNING_TOO_FREQUENTLY"
        else -> "ErrorCode: $this"
    }
}

val ScanResult.manufacturerDataList: List<UniversalManufacturerData>
    get() {
        return scanRecord?.manufacturerSpecificData?.toList()?.map { (key, value) ->
            UniversalManufacturerData(key.toLong(), value)
        } ?: emptyList()
    }

val ScanResult.serviceData: Map<String, ByteArray>
    get() {
        return scanRecord?.serviceData?.mapKeys { it.key.uuid.toString() } ?: emptyMap()
    }

fun <T> SparseArray<T>.toList(): List<Pair<Int, T>> {
    return (0 until size).map { index ->
        keyAt(index) to valueAt(index)
    }
}

fun BluetoothGatt.getCharacteristic(
    service: String,
    characteristic: String,
): BluetoothGattCharacteristic? {
    return getService(UUID.fromString(service))?.getCharacteristic(UUID.fromString(characteristic))
}

fun BluetoothDevice.removeBond() {
    try {
        javaClass.getMethod("removeBond").invoke(this)
    } catch (e: Exception) {
        Log.e(TAG, "Removing bond failed. ${e.message}")
    }
}

fun BluetoothGattCharacteristic.getPropertiesList(): ArrayList<CharacteristicProperty> {
    val propertiesList = arrayListOf<CharacteristicProperty>()
    if (properties and BluetoothGattCharacteristic.PROPERTY_BROADCAST > 0) {
        propertiesList.add(CharacteristicProperty.BROADCAST)
    }
    if (properties and BluetoothGattCharacteristic.PROPERTY_READ > 0) {
        propertiesList.add(CharacteristicProperty.READ)
    }
    if (properties and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE > 0) {
        propertiesList.add(CharacteristicProperty.WRITE_WITHOUT_RESPONSE)
    }
    if (properties and BluetoothGattCharacteristic.PROPERTY_WRITE > 0) {
        propertiesList.add(CharacteristicProperty.WRITE)
    }
    if (properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY > 0) {
        propertiesList.add(CharacteristicProperty.NOTIFY)
    }
    if (properties and BluetoothGattCharacteristic.PROPERTY_INDICATE > 0) {
        propertiesList.add(CharacteristicProperty.INDICATE)
    }
    if (properties and BluetoothGattCharacteristic.PROPERTY_SIGNED_WRITE > 0) {
        propertiesList.add(CharacteristicProperty.AUTHENTICATED_SIGNED_WRITES)
    }
    if (properties and BluetoothGattCharacteristic.PROPERTY_EXTENDED_PROPS > 0) {
        propertiesList.add(CharacteristicProperty.EXTENDED_PROPERTIES)
    }
    return propertiesList
}


fun Short.toByteArray(byteOrder: ByteOrder = ByteOrder.LITTLE_ENDIAN): ByteArray =
    ByteBuffer.allocate(2 /*Short.SIZE_BYTES*/).order(byteOrder).putShort(this).array()


fun createFlutterError(
    code: UniversalBleErrorCode,
    message: String? = null,
    details: String? = null,
) = FlutterError(code.raw.toString(), message, details ?: code.toString())

fun gattStatusToUniversalBleErrorCode(code: Int): UniversalBleErrorCode {
    return when (code) {
        BluetoothGatt.GATT_READ_NOT_PERMITTED -> UniversalBleErrorCode.READ_NOT_PERMITTED
        BluetoothGatt.GATT_WRITE_NOT_PERMITTED -> UniversalBleErrorCode.WRITE_NOT_PERMITTED
        BluetoothGatt.GATT_INSUFFICIENT_AUTHENTICATION -> UniversalBleErrorCode.INSUFFICIENT_AUTHENTICATION
        BluetoothGatt.GATT_INSUFFICIENT_AUTHORIZATION -> UniversalBleErrorCode.INSUFFICIENT_AUTHORIZATION
        BluetoothGatt.GATT_INSUFFICIENT_ENCRYPTION -> UniversalBleErrorCode.INSUFFICIENT_ENCRYPTION
        BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED -> UniversalBleErrorCode.OPERATION_NOT_SUPPORTED
        BluetoothGatt.GATT_INVALID_OFFSET -> UniversalBleErrorCode.INVALID_OFFSET
        BluetoothGatt.GATT_INVALID_ATTRIBUTE_LENGTH -> UniversalBleErrorCode.INVALID_ATTRIBUTE_LENGTH
        BluetoothGatt.GATT_CONNECTION_CONGESTED -> UniversalBleErrorCode.CONNECTION_FAILED
        BluetoothGatt.GATT_FAILURE -> UniversalBleErrorCode.FAILED
        0x01 -> UniversalBleErrorCode.INVALID_HANDLE
        0x04 -> UniversalBleErrorCode.INVALID_PDU
        0x09 -> UniversalBleErrorCode.OPERATION_IN_PROGRESS
        0x0a -> UniversalBleErrorCode.SERVICE_NOT_FOUND
        0x0b -> UniversalBleErrorCode.INVALID_ATTRIBUTE_LENGTH
        0x0c -> UniversalBleErrorCode.INSUFFICIENT_KEY_SIZE
        0x0e -> UniversalBleErrorCode.FAILED
        0x10 -> UniversalBleErrorCode.OPERATION_NOT_SUPPORTED
        0x11 -> UniversalBleErrorCode.FAILED
        else -> UniversalBleErrorCode.UNKNOWN_ERROR
    }
}

fun AndroidScanMode.parse(): Int? {
    return when (this) {
        AndroidScanMode.BALANCED -> ScanSettings.SCAN_MODE_BALANCED
        AndroidScanMode.LOW_LATENCY -> ScanSettings.SCAN_MODE_LOW_LATENCY
        AndroidScanMode.LOW_POWER -> ScanSettings.SCAN_MODE_LOW_POWER
        AndroidScanMode.OPPORTUNISTIC -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            ScanSettings.SCAN_MODE_OPPORTUNISTIC
        } else {
            UniversalBleLogger.logError("Scan mode OPPORTUNISTIC is not supported on this Android version.")
            null
        }
    }
}

fun AndroidScanCallbackType.parse(): Int? {
    return when (this) {
        AndroidScanCallbackType.ALL_MATCHES -> ScanSettings.CALLBACK_TYPE_ALL_MATCHES
        AndroidScanCallbackType.FIRST_MATCH -> ScanSettings.CALLBACK_TYPE_FIRST_MATCH
        AndroidScanCallbackType.MATCH_LOST -> ScanSettings.CALLBACK_TYPE_MATCH_LOST
    }
}

fun AndroidScanMatchMode.parse(): Int? {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
        UniversalBleLogger.logError("Match mode is not supported on this Android version.")
        return null
    }
    return when (this) {
        AndroidScanMatchMode.AGGRESSIVE -> ScanSettings.MATCH_MODE_AGGRESSIVE
        AndroidScanMatchMode.STICKY -> ScanSettings.MATCH_MODE_STICKY
    }
}

fun AndroidScanNumOfMatches.parse(): Int? {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
        UniversalBleLogger.logError("Num of matches is not supported on this Android version.")
        return null
    }
    return when (this) {
        AndroidScanNumOfMatches.ONE -> ScanSettings.MATCH_NUM_ONE_ADVERTISEMENT
        AndroidScanNumOfMatches.FEW -> ScanSettings.MATCH_NUM_FEW_ADVERTISEMENT
        AndroidScanNumOfMatches.MAX -> ScanSettings.MATCH_NUM_MAX_ADVERTISEMENT
    }
}

fun Int.parseBluetoothStatusCodeError(): UniversalBleErrorCode? {
    if (this == BluetoothStatusCodes.SUCCESS) return null
    return when (this) {
        BluetoothStatusCodes.ERROR_BLUETOOTH_NOT_ENABLED -> UniversalBleErrorCode.BLUETOOTH_NOT_ENABLED
        BluetoothStatusCodes.ERROR_BLUETOOTH_NOT_ALLOWED -> UniversalBleErrorCode.BLUETOOTH_NOT_ALLOWED
        BluetoothStatusCodes.ERROR_DEVICE_NOT_BONDED -> UniversalBleErrorCode.NOT_PAIRED
        BluetoothStatusCodes.ERROR_GATT_WRITE_NOT_ALLOWED -> UniversalBleErrorCode.WRITE_NOT_PERMITTED
        BluetoothStatusCodes.ERROR_GATT_WRITE_REQUEST_BUSY -> UniversalBleErrorCode.WRITE_REQUEST_BUSY
        BluetoothStatusCodes.ERROR_MISSING_BLUETOOTH_CONNECT_PERMISSION -> UniversalBleErrorCode.CONNECTION_FAILED
        BluetoothStatusCodes.ERROR_PROFILE_SERVICE_NOT_BOUND -> UniversalBleErrorCode.SERVICE_NOT_FOUND
        BluetoothStatusCodes.ERROR_UNKNOWN -> UniversalBleErrorCode.UNKNOWN_ERROR
        BluetoothStatusCodes.FEATURE_NOT_CONFIGURED -> UniversalBleErrorCode.NOT_IMPLEMENTED
        BluetoothStatusCodes.FEATURE_NOT_SUPPORTED -> UniversalBleErrorCode.NOT_SUPPORTED
        else -> null
    }
}

fun Int.parseHciErrorCode(): String? {
    return when (this) {
        BluetoothGatt.GATT_SUCCESS -> null
        0x01 -> "Unknown HCI Command"
        0x02 -> "Unknown Connection Identifier"
        0x03 -> "Hardware Failure"
        0x04 -> "Page Timeout"
        0x05 -> "Authentication Failure"
        0x06 -> "PIN or Key Missing"
        0x07 -> "Memory Capacity Exceeded"
        0x08 -> "Connection Timeout"
        0x09 -> "Connection Limit Exceeded"
        0x0A -> "Synchronous Connection Limit To A Device Exceeded"
        0x0B -> "Connection Already Exists"
        0x0C -> "Command Disallowed"
        0x0D -> "Connection Rejected due to Limited Resources"
        0x0E -> "Connection Rejected Due To Security Reasons"
        0x0F -> "Connection Rejected due to Unacceptable BD_ADDR"
        0x10 -> "Connection Accept Timeout Exceeded"
        0x11 -> "Unsupported Feature or Parameter Value"
        0x12 -> "Invalid HCI Command Parameters"
        0x13 -> "Remote User Terminated Connection"
        0x14 -> "Remote Device Terminated Connection due to Low Resources"
        0x15 -> "Remote Device Terminated Connection due to Power Off"
        0x16 -> "Connection Terminated By Local Host"
        0x17 -> "Repeated Attempts"
        0x18 -> "Pairing Not Allowed"
        0x19 -> "Unknown LMP PDU"
        0x1A -> "Unsupported Remote Feature / Unsupported LMP Feature"
        0x1B -> "SCO Offset Rejected"
        0x1C -> "SCO Interval Rejected"
        0x1D -> "SCO Air Mode Rejected"
        0x1E -> "Invalid LMP Parameters / Invalid LL Parameters"
        0x1F -> "Unspecified Error"
        0x20 -> "Unsupported LMP Parameter Value / Unsupported LL Parameter Value"
        0x21 -> "Role Change Not Allowed"
        0x22 -> "LMP Response Timeout / LL Response Timeout"
        0x23 -> "LMP Error Transaction Collision / LL Procedure Collision"
        0x24 -> "LMP PDU Not Allowed"
        0x25 -> "Encryption Mode Not Acceptable"
        0x26 -> "Link Key cannot be Changed"
        0x27 -> "Requested QoS Not Supported"
        0x28 -> "Instant Passed"
        0x29 -> "Pairing With Unit Key Not Supported"
        0x2A -> "Different Transaction Collision"
        0x2B -> "Reserved for future use"
        0x2C -> "QoS Unacceptable Parameter"
        0x2D -> "QoS Rejected"
        0x2E -> "Channel Classification Not Supported"
        0x2F -> "Insufficient Security"
        0x30 -> "Parameter Out Of Mandatory Range"
        0x31 -> "Reserved for future use"
        0x32 -> "Role Switch Pending"
        0x33 -> "Reserved for future use"
        0x34 -> "Reserved Slot Violation"
        0x35 -> "Role Switch Failed"
        0x36 -> "Extended Inquiry Response Too Large"
        0x37 -> "Secure Simple Pairing Not Supported By Host"
        0x38 -> "Host Busy - Pairing"
        0x39 -> "Connection Rejected due to No Suitable Channel Found"
        0x3A -> "Controller Busy"
        0x3B -> "Unacceptable Connection Parameters"
        0x3C -> "Advertising Timeout"
        0x3D -> "Connection Terminated due to MIC Failure"
        0x3E -> "Connection Failed to be Established / Synchronization Timeout"
        0x3F -> "MAC Connection Failed"
        0x40 -> "Coarse Clock Adjustment Rejected but Will Try to Adjust Using Clock Dragging"
        0x41 -> "Type0 Submap Not Defined"
        0x42 -> "Unknown Advertising Identifier"
        0x43 -> "Limit Reached"
        0x44 -> "Operation Cancelled by Host"
        0x45 -> "Packet Too Long"
        else -> "Unknown Error $this"
    }
}

// Future result classes
class DiscoverServicesFuture(
    val deviceId: String,
    val withDescriptors: Boolean,
    val result: (Result<List<UniversalBleService>>) -> Unit,
)

class MtuResultFuture(
    val deviceId: String,
    val result: (Result<Long>) -> Unit,
)

class ReadResultFuture(
    val deviceId: String,
    val characteristicId: String,
    val serviceId: String,
    val result: (Result<ByteArray>) -> Unit,
)

class WriteResultFuture(
    val deviceId: String,
    val characteristicId: String,
    val serviceId: String,
    val result: (Result<Unit>) -> Unit,
)

class SubscriptionResultFuture(
    val deviceId: String,
    val characteristicId: String,
    val serviceId: String,
    val result: (Result<Unit>) -> Unit,
)

class RssiResultFuture(
    val deviceId: String,
    val result: (Result<Long>) -> Unit,
)