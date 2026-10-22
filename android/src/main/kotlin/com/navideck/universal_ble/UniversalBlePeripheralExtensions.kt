package com.navideck.universal_ble

import android.app.Activity
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattService
import android.content.pm.PackageManager
import android.util.Log
import java.util.Collections
import java.util.IdentityHashMap
import java.util.UUID

/**
 * Registered peripheral characteristics, keyed by their stable instance id.
 *
 * A GATT service may contain several characteristics with the same UUID (HID
 * exposes one Report characteristic per report). The instance id is the
 * caller-supplied [PeripheralCharacteristic.instanceId], or a derived
 * `uuid#<ordinal>` for duplicate UUIDs that did not declare one. UUID-only
 * lookups keep returning the first registered instance, so existing callers are
 * unaffected.
 */
private val bluetoothGattCharacteristics:
    MutableMap<String, BluetoothGattCharacteristic> = HashMap()
private val characteristicInstanceIds:
    MutableMap<BluetoothGattCharacteristic, String> = IdentityHashMap()
private val descriptorValueReadMap: MutableMap<BluetoothGattDescriptor, ByteArray> =
    IdentityHashMap()

/** Per-client CCCD values, keyed by `device|instance|descriptor`. */
private val cccdValues: MutableMap<String, ByteArray> = HashMap()

/**
 * Instances a client subscribed to, keyed by client address. Values are stable
 * characteristic instance ids, so two subscriptions to different Report
 * characteristics with the same UUID stay distinct.
 */
val subscribedCharDevicesMap: MutableMap<String, MutableSet<String>> = HashMap()
const val peripheralDescriptorCCUUID = "00002902-0000-1000-8000-00805f9b34fb"

fun clearPeripheralCaches() {
    synchronized(bluetoothGattCharacteristics) {
        bluetoothGattCharacteristics.clear()
    }
    synchronized(characteristicInstanceIds) {
        characteristicInstanceIds.clear()
    }
    synchronized(descriptorValueReadMap) {
        descriptorValueReadMap.clear()
    }
    synchronized(cccdValues) {
        cccdValues.clear()
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
    val ordinalByUuid = HashMap<String, Int>()
    characteristics.forEach {
        service.addCharacteristic(it.toGattCharacteristic(ordinalByUuid))
    }
    return service
}

fun PeripheralCharacteristic.toGattCharacteristic(): BluetoothGattCharacteristic =
    toGattCharacteristic(HashMap())

fun PeripheralCharacteristic.toGattCharacteristic(
    ordinalByUuid: MutableMap<String, Int>,
): BluetoothGattCharacteristic {
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

    val normalizedUuid = uuid.lowercase()
    val ordinal = (ordinalByUuid[normalizedUuid] ?: 0) + 1
    ordinalByUuid[normalizedUuid] = ordinal
    val resolvedInstanceId = instanceId ?: if (ordinal == 1) null else "$normalizedUuid#$ordinal"
    if (resolvedInstanceId != null) {
        synchronized(bluetoothGattCharacteristics) {
            bluetoothGattCharacteristics[resolvedInstanceId.lowercase()] = characteristic
        }
        synchronized(characteristicInstanceIds) {
            characteristicInstanceIds[characteristic] = resolvedInstanceId
        }
    }
    // UUID-only callers keep resolving to the first registered instance.
    synchronized(bluetoothGattCharacteristics) {
        bluetoothGattCharacteristics.putIfAbsent(normalizedUuid, characteristic)
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
    // A fresh subscription is off until the client enables it.
    cccd.value = BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE
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
            descriptorValueReadMap[descriptor] = it
        }
    }
    return descriptor
}

fun BluetoothGattDescriptor.getCacheValue(): ByteArray? =
    synchronized(descriptorValueReadMap) {
        descriptorValueReadMap[this]
    }

/**
 * The descriptor value this client should read. Configured descriptor values
 * are served when no caller-supplied handler overrides them; CCCDs are tracked
 * per client so one subscriber cannot change what another subscriber reads.
 */
fun BluetoothGattDescriptor.getClientValue(deviceId: String?): ByteArray? {
    if (uuid.toString().equals(peripheralDescriptorCCUUID, ignoreCase = true)) {
        val instanceId = characteristic?.instanceId() ?: characteristic?.uuid?.toString()
        val key = cccdKey(deviceId, instanceId, uuid.toString())
        synchronized(cccdValues) {
            cccdValues[key]?.let { return it }
        }
        return value ?: BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE
    }
    return value ?: getCacheValue()
}

fun BluetoothGattDescriptor.storeClientValue(deviceId: String?, value: ByteArray?) {
    if (!uuid.toString().equals(peripheralDescriptorCCUUID, ignoreCase = true)) return
    val instanceId = characteristic?.instanceId() ?: characteristic?.uuid?.toString()
    val key = cccdKey(deviceId, instanceId, uuid.toString())
    synchronized(cccdValues) {
        if (value == null) {
            cccdValues.remove(key)
        } else {
            cccdValues[key] = value.copyOf()
        }
    }
}

private fun cccdKey(deviceId: String?, instanceId: String?, descriptorUuid: String): String =
    "${deviceId?.lowercase()}|${instanceId?.lowercase()}|${descriptorUuid.lowercase()}"

/** Stable identity of a registered characteristic, if it declared one. */
fun BluetoothGattCharacteristic.instanceId(): String? =
    synchronized(characteristicInstanceIds) {
        characteristicInstanceIds[this]
    }

fun String.findGattCharacteristic(instanceId: String? = null): BluetoothGattCharacteristic? =
    synchronized(bluetoothGattCharacteristics) {
        if (instanceId != null) {
            bluetoothGattCharacteristics[instanceId.lowercase()]?.let { return it }
        }
        bluetoothGattCharacteristics[this.lowercase()]
    }

fun String.findService(): BluetoothGattService? {
    val characteristic = findGattCharacteristic() ?: return null
    return characteristic.service
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
