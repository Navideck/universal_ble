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

/**
 * Per-client CCCD value, identified by the client, the characteristic instance
 * and the descriptor. A structured key is used instead of a delimited string so
 * a caller-supplied [PeripheralCharacteristic.instanceId] cannot break it apart:
 * an id containing the delimiter would otherwise be mistaken for another
 * characteristic's entry when a service is removed.
 */
private data class CccdKey(
    val deviceId: String?,
    val characteristicIdentity: String?,
    val descriptorUuid: String,
)

private val cccdValues: MutableMap<CccdKey, ByteArray> = HashMap()

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

/**
 * Drops the cached state that belongs to [service] only: its characteristic
 * lookups and instance ids, configured descriptor values, per-client CCCD
 * values and subscriptions. Other registered services keep theirs — including
 * when they expose the same characteristic UUID, which HID and vendor services
 * routinely do.
 *
 * Call this whenever [service] leaves the GATT server. Its characteristics are
 * then no longer registered, so a cached lookup must not keep resolving them:
 * a later registration of the same UUID would otherwise notify through orphaned
 * objects and the central would receive nothing.
 */
fun clearPeripheralCaches(service: BluetoothGattService) {
    // Identities are read before the maps holding them are touched: the CCCD and
    // subscription keys are built from them.
    val removedCharacteristics = service.characteristics.orEmpty().toList()
    val removedIdentities = removedCharacteristics.map(::identityOf).toSet()
    synchronized(bluetoothGattCharacteristics) {
        bluetoothGattCharacteristics.entries.removeAll { it.value.service === service }
        // A UUID alias may have pointed at a characteristic of this service while
        // another registered service exposes the same UUID: re-point the alias at
        // the survivor, so that service stays reachable by UUID.
        removedCharacteristics.forEach { removed ->
            val alias = removed.uuid.toString().lowercase()
            if (bluetoothGattCharacteristics.containsKey(alias)) return@forEach
            val survivor = bluetoothGattCharacteristics.values.firstOrNull {
                it.uuid.toString().equals(alias, ignoreCase = true)
            }
            if (survivor != null) bluetoothGattCharacteristics[alias] = survivor
        }
    }
    synchronized(characteristicInstanceIds) {
        characteristicInstanceIds.keys.removeAll { it.service === service }
    }
    synchronized(descriptorValueReadMap) {
        descriptorValueReadMap.keys.removeAll { it.characteristic?.service === service }
    }
    if (removedIdentities.isEmpty()) return
    // Whatever identity another cached characteristic still exposes must keep its
    // CCCD values and subscriptions: two services can share a UUID, and the
    // remaining registration is still alive and still subscribed.
    val surviving = synchronized(bluetoothGattCharacteristics) {
        bluetoothGattCharacteristics.values.toList()
    }
    val droppedIdentities = removedIdentities - surviving.map(::identityOf).toSet()
    if (droppedIdentities.isEmpty()) return
    synchronized(cccdValues) {
        cccdValues.keys.removeAll { it.characteristicIdentity in droppedIdentities }
    }
    synchronized(subscribedCharDevicesMap) {
        subscribedCharDevicesMap.values.forEach { ids ->
            ids.removeAll { it.lowercase() in droppedIdentities }
        }
        subscribedCharDevicesMap.values.removeAll { it.isEmpty() }
    }
}

/**
 * The identity CCCD values and subscriptions are keyed by for [characteristic]:
 * its instance id when it declared one, its UUID otherwise.
 */
private fun identityOf(characteristic: BluetoothGattCharacteristic): String =
    (characteristic.instanceId() ?: characteristic.uuid.toString()).lowercase()

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
        return byteArrayOf(0, 0)
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

private fun cccdKey(deviceId: String?, instanceId: String?, descriptorUuid: String): CccdKey =
    CccdKey(deviceId?.lowercase(), instanceId?.lowercase(), descriptorUuid.lowercase())

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
    return synchronized(bluetoothGattCharacteristics) {
        bluetoothGattCharacteristics.values.firstOrNull {
            it.service?.uuid?.toString().equals(this, ignoreCase = true)
        }?.service
    }
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
