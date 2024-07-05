package com.navideck.universal_ble

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothStatusCodes
import android.bluetooth.le.ScanCallback.SCAN_FAILED_ALREADY_STARTED
import android.bluetooth.le.ScanCallback.SCAN_FAILED_APPLICATION_REGISTRATION_FAILED
import android.bluetooth.le.ScanCallback.SCAN_FAILED_FEATURE_UNSUPPORTED
import android.bluetooth.le.ScanCallback.SCAN_FAILED_INTERNAL_ERROR
import android.bluetooth.le.ScanCallback.SCAN_FAILED_OUT_OF_HARDWARE_RESOURCES
import android.bluetooth.le.ScanCallback.SCAN_FAILED_SCANNING_TOO_FREQUENTLY
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.os.Build
import android.os.ParcelUuid
import android.util.Log
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.UUID

private const val TAG = "UniversalBlePlugin"

val knownGatts = mutableListOf<BluetoothGatt>()
const val ccdCharacteristic = "00002902-0000-1000-8000-00805f9b34fb"

enum class BleConnectionState(val value: Long) {
    Connected(0),
    Disconnected(1),
    Connecting(2),
    Disconnecting(3)
}

enum class AvailabilityState(val value: Long) {
    Unknown(0),
    Resetting(1),
    Unsupported(2),
    Unauthorized(3),
    PoweredOff(4),
    PoweredOn(5);
}

enum class BleInputProperty(val value: Long) {
    Disabled(0),
    Notification(1),
    Indication(2);
}

enum class BleOutputProperty(val value: Long) {
    withResponse(0),
    withoutResponse(1);
}


enum class CharacteristicProperty(val value: Long) {
    Broadcast(0),
    Read(1),
    WriteWithoutResponse(2),
    Write(3),
    Notify(4),
    Indicate(5),
    AuthenticatedSignedWrites(6),
    ExtendedProperties(7)
}


fun Int.toBleConnectionState(): BleConnectionState {
    return when (this) {
        BluetoothGatt.STATE_CONNECTED -> BleConnectionState.Connected
        BluetoothGatt.STATE_CONNECTING -> BleConnectionState.Connecting
        BluetoothGatt.STATE_DISCONNECTING -> BleConnectionState.Disconnecting
        BluetoothGatt.STATE_DISCONNECTED -> BleConnectionState.Disconnected
        else -> BleConnectionState.Disconnected
    }
}

fun String.validFullUUID(): String {
    return when (this.count()) {
        4 -> "0000$this-0000-1000-8000-00805F9B34FB"
        8 -> "$this-0000-1000-8000-00805F9B34FB"
        else -> this
    }
}

fun String.toBluetoothGatt(): BluetoothGatt {
    return knownGatts.find { it.device.address == this }
        ?: throw FlutterError("IllegalArgument", "Unknown deviceId: $this", null)
}

fun Int.toAvailabilityState(): Long {
    return when (this) {
        BluetoothAdapter.STATE_OFF -> AvailabilityState.PoweredOff.value
        BluetoothAdapter.STATE_ON -> AvailabilityState.PoweredOn.value
        BluetoothAdapter.STATE_TURNING_ON -> AvailabilityState.Resetting.value
        BluetoothAdapter.STATE_TURNING_OFF -> AvailabilityState.Resetting.value
        else -> AvailabilityState.Unknown.value
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

fun Int.parseBluetoothStatusCodeError(): String? {
    if (this == BluetoothStatusCodes.SUCCESS) return null
    return when (this) {
        BluetoothStatusCodes.ERROR_BLUETOOTH_NOT_ENABLED -> "ERROR_BLUETOOTH_NOT_ENABLED"
        BluetoothStatusCodes.ERROR_BLUETOOTH_NOT_ALLOWED -> "ERROR_BLUETOOTH_NOT_ALLOWED"
        BluetoothStatusCodes.ERROR_DEVICE_NOT_BONDED -> "ERROR_DEVICE_NOT_BONDED"
        BluetoothStatusCodes.ERROR_GATT_WRITE_NOT_ALLOWED -> "ERROR_GATT_WRITE_NOT_ALLOWED"
        BluetoothStatusCodes.ERROR_GATT_WRITE_REQUEST_BUSY -> "ERROR_GATT_WRITE_REQUEST_BUSY"
        BluetoothStatusCodes.ERROR_MISSING_BLUETOOTH_CONNECT_PERMISSION -> "ERROR_MISSING_BLUETOOTH_CONNECT_PERMISSION"
        BluetoothStatusCodes.ERROR_PROFILE_SERVICE_NOT_BOUND -> "ERROR_PROFILE_SERVICE_NOT_BOUND"
        BluetoothStatusCodes.ERROR_UNKNOWN -> "ERROR_UNKNOWN"
        BluetoothStatusCodes.FEATURE_NOT_CONFIGURED -> "FEATURE_NOT_CONFIGURED"
        BluetoothStatusCodes.FEATURE_NOT_SUPPORTED -> "FEATURE_NOT_SUPPORTED"
        BluetoothStatusCodes.FEATURE_SUPPORTED -> "FEATURE_SUPPORTED"
        else -> "ErrorCode: $this"
    }
}

fun Int.parseGattErrorCode(): String? {
    return when (this) {
        BluetoothGatt.GATT_SUCCESS -> null
        BluetoothGatt.GATT_READ_NOT_PERMITTED -> "GATT_READ_NOT_PERMITTED"
        BluetoothGatt.GATT_WRITE_NOT_PERMITTED -> "GATT_WRITE_NOT_PERMITTED"
        BluetoothGatt.GATT_INSUFFICIENT_AUTHENTICATION -> "GATT_INSUFFICIENT_AUTHENTICATION"
        BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED -> "GATT_REQUEST_NOT_SUPPORTED"
        BluetoothGatt.GATT_INVALID_OFFSET -> "GATT_INVALID_OFFSET"
        BluetoothGatt.GATT_INSUFFICIENT_AUTHORIZATION -> "GATT_INSUFFICIENT_AUTHORIZATION"
        BluetoothGatt.GATT_INVALID_ATTRIBUTE_LENGTH -> "GATT_INVALID_ATTRIBUTE_LENGTH"
        BluetoothGatt.GATT_INSUFFICIENT_ENCRYPTION -> "GATT_INSUFFICIENT_ENCRYPTION"
        BluetoothGatt.GATT_CONNECTION_CONGESTED -> "GATT_CONNECTION_CONGESTED"
        BluetoothGatt.GATT_FAILURE -> "GATT_FAILURE"
        0x01 -> "GATT_INVALID_HANDLE"
        0x04 -> "GATT_INVALID_PDU"
        0x09 -> "GATT_PREPARE_QUEUE_FULL"
        0x0a -> "GATT_ATTR_NOT_FOUND"
        0x0b -> "GATT_ATTR_NOT_LONG"
        0x0c -> "GATT_INSUFFICIENT_KEY_SIZE"
        0x0e -> "GATT_UNLIKELY"
        0x10 -> "GATT_UNSUPPORTED_GROUP"
        0x11 -> "GATT_INSUFFICIENT_RESOURCES"
        else -> "Unknown Error: $this"
    }
}

fun UniversalScanFilter.toScanFilters(): List<ScanFilter> {
    var scanFilters: ArrayList<ScanFilter> = arrayListOf()

    // Add withServices Filter
    for (service in this.withServices) {
        try {
            val serviceUUID = service?.validFullUUID()
            serviceUUID?.let {
                val parcelUUId = ParcelUuid.fromString(it)
                scanFilters.add(
                    ScanFilter.Builder().setServiceUuid(parcelUUId).build()
                )
                Log.e(TAG, "scanFilters: $parcelUUId")
            }
        } catch (e: Exception) {
            Log.e(TAG, e.toString())
            throw FlutterError(
                "illegalIllegalArgument",
                "Invalid serviceId: $service",
                e.toString()
            )
        }
    }

    // Add ManufacturerData Filter
    for (manufacturerData in this.withManufacturerData) {
        try {
            manufacturerData?.companyIdentifier?.let {
                val data: ByteArray = manufacturerData.data ?: ByteArray(0)
                val mask: ByteArray? = manufacturerData.mask
                if (mask == null) {
                    scanFilters.add(
                        ScanFilter.Builder().setManufacturerData(
                            it.toInt(), data
                        ).build()
                    )
                } else {
                    scanFilters.add(
                        ScanFilter.Builder().setManufacturerData(
                            it.toInt(), data, mask
                        ).build()
                    )
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, e.toString())
            throw FlutterError(
                "illegalIllegalArgument",
                "Invalid manufacturerData: ${manufacturerData?.companyIdentifier} ${manufacturerData?.data} ${manufacturerData?.mask}",
                e.toString()
            )
        }
    }

    return scanFilters.toList()
}

val ScanResult.manufacturerDataHead: ByteArray?
    get() {
        val sparseArray = scanRecord?.manufacturerSpecificData ?: return null
        if (sparseArray.size() == 0) return null

        return sparseArray.keyAt(0).toShort().toByteArray() + sparseArray.valueAt(0)
    }

fun BluetoothGatt.getCharacteristic(
    service: String,
    characteristic: String,
): BluetoothGattCharacteristic? =
    getService(UUID.fromString(service)).getCharacteristic(UUID.fromString(characteristic))


@SuppressLint("MissingPermission")
@Suppress("DEPRECATION")
fun BluetoothGatt.setNotifiable(
    gattCharacteristic: BluetoothGattCharacteristic,
    bleInputProperty: Long,
): Boolean {
    val descClientCharConfirmation = UUID.fromString(ccdCharacteristic)
    val descriptor = gattCharacteristic.getDescriptor(descClientCharConfirmation)
    val bleInputPropertyEnum: BleInputProperty =
        BleInputProperty.values().first { it.value == bleInputProperty }
    val (value, enable) = when (bleInputPropertyEnum) {
        BleInputProperty.Notification -> BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE to true
        BleInputProperty.Indication -> BluetoothGattDescriptor.ENABLE_INDICATION_VALUE to true
        else -> BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE to false
    }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        writeDescriptor(descriptor, value)
    } else {
        descriptor.value = value
        writeDescriptor(descriptor)
    }
    return setCharacteristicNotification(descriptor.characteristic, enable)
}

fun BluetoothDevice.removeBond() {
    try {
        javaClass.getMethod("removeBond").invoke(this)
    } catch (e: Exception) {
        Log.e(TAG, "Removing bond failed. ${e.message}")
    }
}


fun BluetoothGattCharacteristic.getPropertiesList(): ArrayList<Long> {
    val propertiesList = arrayListOf<Long>()
    if (properties and BluetoothGattCharacteristic.PROPERTY_BROADCAST > 0) {
        propertiesList.add(CharacteristicProperty.Broadcast.value)
    }
    if (properties and BluetoothGattCharacteristic.PROPERTY_READ > 0) {
        propertiesList.add(CharacteristicProperty.Read.value)
    }
    if (properties and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE > 0) {
        propertiesList.add(CharacteristicProperty.WriteWithoutResponse.value)
    }
    if (properties and BluetoothGattCharacteristic.PROPERTY_WRITE > 0) {
        propertiesList.add(CharacteristicProperty.Write.value)
    }
    if (properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY > 0) {
        propertiesList.add(CharacteristicProperty.Notify.value)
    }
    if (properties and BluetoothGattCharacteristic.PROPERTY_INDICATE > 0) {
        propertiesList.add(CharacteristicProperty.Indicate.value)
    }
    if (properties and BluetoothGattCharacteristic.PROPERTY_SIGNED_WRITE > 0) {
        propertiesList.add(CharacteristicProperty.AuthenticatedSignedWrites.value)
    }
    if (properties and BluetoothGattCharacteristic.PROPERTY_EXTENDED_PROPS > 0) {
        propertiesList.add(CharacteristicProperty.ExtendedProperties.value)
    }
    return propertiesList
}


fun Short.toByteArray(byteOrder: ByteOrder = ByteOrder.LITTLE_ENDIAN): ByteArray =
    ByteBuffer.allocate(2 /*Short.SIZE_BYTES*/).order(byteOrder).putShort(this).array()

// Errors
fun unknownCharacteristicError(char: String) =
    FlutterError("IllegalArgument", "Unknown error", null)


val DeviceDisconnectedError: FlutterError = FlutterError(
    "DeviceDisconnected",
    "Device Disconnected",
    null
)

// Future result classes
class DiscoverServicesFuture(
    val deviceId: String,
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