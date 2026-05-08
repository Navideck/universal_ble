package com.navideck.universal_ble

import android.app.Activity
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattService
import android.content.pm.PackageManager
import android.util.Log
import java.util.Collections
import java.util.UUID

private val bluetoothGattCharacteristics:
    MutableMap<String, BluetoothGattCharacteristic> = HashMap()
private val descriptorValueReadMap: MutableMap<String, ByteArray> = HashMap()
val subscribedCharDevicesMap: MutableMap<String, MutableList<String>> = HashMap()
const val peripheralDescriptorCCUUID = "00002902-0000-1000-8000-00805f9b34fb"

fun clearPeripheralCaches() {
    synchronized(bluetoothGattCharacteristics) {
        bluetoothGattCharacteristics.clear()
    }
    synchronized(descriptorValueReadMap) {
        descriptorValueReadMap.clear()
    }
    synchronized(subscribedCharDevicesMap) {
        subscribedCharDevicesMap.clear()
    }
}

fun Activity.havePermission(permissions: Array<String>): Boolean {
    for (perm in permissions) {
        if (checkCallingOrSelfPermission(perm) != PackageManager.PERMISSION_GRANTED) {
            return false
        }
    }
    return true
}

fun PeripheralService.toGattService(): BluetoothGattService {
    val service = BluetoothGattService(
        UUID.fromString(uuid),
        if (primary) BluetoothGattService.SERVICE_TYPE_PRIMARY else BluetoothGattService.SERVICE_TYPE_SECONDARY,
    )
    characteristics.forEach {
        service.addCharacteristic(it.toGattCharacteristic())
    }
    return service
}

fun PeripheralCharacteristic.toGattCharacteristic(): BluetoothGattCharacteristic {
    val characteristic = BluetoothGattCharacteristic(
        UUID.fromString(uuid),
        properties.toPropertiesList(),
        permissions.toPermissionsList(),
    )
    value?.let { characteristic.value = it }
    descriptors?.forEach {
        characteristic.addDescriptor(it.toGattDescriptor())
    }

    addCCDescriptorIfRequired(this, characteristic)
    synchronized(bluetoothGattCharacteristics) {
        if (bluetoothGattCharacteristics[uuid] == null) {
            bluetoothGattCharacteristics[uuid] = characteristic
        }
    }
    return characteristic
}

private fun addCCDescriptorIfRequired(
    peripheralCharacteristic: PeripheralCharacteristic,
    characteristic: BluetoothGattCharacteristic,
) {
    val hasNotifyOrIndicate =
        characteristic.properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY != 0 ||
            characteristic.properties and BluetoothGattCharacteristic.PROPERTY_INDICATE != 0
    if (!hasNotifyOrIndicate) return

    var hasCccd = false
    for (descriptor in peripheralCharacteristic.descriptors ?: Collections.emptyList()) {
        if (descriptor.uuid.equals(peripheralDescriptorCCUUID, ignoreCase = true)) {
            hasCccd = true
            break
        }
    }
    if (hasCccd) return

    val cccd = BluetoothGattDescriptor(
        UUID.fromString(peripheralDescriptorCCUUID),
        BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE,
    )
    cccd.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
    characteristic.addDescriptor(cccd)
    Log.d("UniversalBlePeripheral", "Added CCCD for ${characteristic.uuid}")
}

fun PeripheralDescriptor.toGattDescriptor(): BluetoothGattDescriptor {
    val permission = permissions?.toPermissionsList()
        ?: BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE
    val descriptor = BluetoothGattDescriptor(UUID.fromString(uuid), permission)
    value?.let {
        descriptor.value = it
        synchronized(descriptorValueReadMap) {
            descriptorValueReadMap[uuid.lowercase()] = it
        }
    }
    return descriptor
}

fun BluetoothGattDescriptor.getCacheValue(): ByteArray? =
    synchronized(descriptorValueReadMap) {
        descriptorValueReadMap[uuid.toString().lowercase()]
    }

fun String.findGattCharacteristic(): BluetoothGattCharacteristic? =
    synchronized(bluetoothGattCharacteristics) {
        bluetoothGattCharacteristics[this]
    }

fun String.findService(): BluetoothGattService? {
    synchronized(bluetoothGattCharacteristics) {
        for (characteristic in bluetoothGattCharacteristics.values) {
            if (characteristic.service?.uuid.toString() == this) {
                return characteristic.service
            }
        }
    }
    return null
}

private fun List<CharacteristicProperty>.toPropertiesList(): Int =
    fold(0) { acc, property -> acc or property.toPropertyBits() }

private fun List<PeripheralAttributePermission>.toPermissionsList(): Int =
    fold(0) { acc, permission -> acc or permission.toPermissionBits() }

private fun CharacteristicProperty.toPropertyBits(): Int = when (this) {
    CharacteristicProperty.BROADCAST -> BluetoothGattCharacteristic.PROPERTY_BROADCAST
    CharacteristicProperty.READ -> BluetoothGattCharacteristic.PROPERTY_READ
    CharacteristicProperty.WRITE_WITHOUT_RESPONSE -> BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE
    CharacteristicProperty.WRITE -> BluetoothGattCharacteristic.PROPERTY_WRITE
    CharacteristicProperty.NOTIFY -> BluetoothGattCharacteristic.PROPERTY_NOTIFY
    CharacteristicProperty.INDICATE -> BluetoothGattCharacteristic.PROPERTY_INDICATE
    CharacteristicProperty.AUTHENTICATED_SIGNED_WRITES -> BluetoothGattCharacteristic.PROPERTY_SIGNED_WRITE
    CharacteristicProperty.EXTENDED_PROPERTIES -> BluetoothGattCharacteristic.PROPERTY_EXTENDED_PROPS
    // Android uses dedicated encrypted notify/indicate property bits.
}

private fun PeripheralAttributePermission.toPermissionBits(): Int = when (this) {
    PeripheralAttributePermission.READABLE -> BluetoothGattCharacteristic.PERMISSION_READ
    PeripheralAttributePermission.WRITEABLE -> BluetoothGattCharacteristic.PERMISSION_WRITE
    PeripheralAttributePermission.READ_ENCRYPTION_REQUIRED -> BluetoothGattCharacteristic.PERMISSION_READ_ENCRYPTED
    PeripheralAttributePermission.WRITE_ENCRYPTION_REQUIRED -> BluetoothGattCharacteristic.PERMISSION_WRITE_ENCRYPTED
}
