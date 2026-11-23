package com.navideck.universal_ble

import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattService
import android.os.Handler
import java.util.UUID
import org.mockito.Mockito

/**
 * Shared test wiring for the Android plugin's GATT paths.
 *
 * Every test used to rebuild the same mock device, gatt, service and
 * characteristic, and the same main-looper handler. Keeping them here means a
 * change to the plugin's internals (or to the reflection helpers in
 * [PluginTestSupport]) is updated in one place instead of a dozen.
 */

/** The address and UUIDs the fixtures default to. */
internal object GattIds {
    const val ADDRESS = "AA:BB:CC:DD:EE:FF"
    const val OTHER_ADDRESS = "11:22:33:44:55:66"

    val SERVICE: UUID = UUID.fromString("0000fff0-0000-1000-8000-00805f9b34fb")
    val CHARACTERISTIC: UUID = UUID.fromString("0000fff1-0000-1000-8000-00805f9b34fb")
    val OTHER_CHARACTERISTIC: UUID = UUID.fromString("0000fff2-0000-1000-8000-00805f9b34fb")
    val CCCD: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    val DESCRIPTOR: UUID = UUID.fromString("00002901-0000-1000-8000-00805f9b34fb")
}

/**
 * A plugin whose main-looper posts run inline. Use it when a test expects a
 * completion to be observed synchronously.
 */
internal fun pluginWithInlineLooper(): UniversalBlePlugin =
    UniversalBlePlugin().also { plugin ->
        val handler = Mockito.mock(Handler::class.java)
        Mockito.doAnswer { invocation ->
            invocation.getArgument<Runnable>(0).run()
            true
        }.`when`(handler).post(Mockito.any())
        plugin.setField("mainThreadHandler", handler)
    }

/**
 * A plugin that records main-looper posts instead of running them, so a test
 * can assert that a completion is not delivered on a binder thread and can
 * control when it runs. Drain it with [drainPosts].
 */
internal fun pluginWithRecordedLooper(posts: MutableCollection<Runnable>): UniversalBlePlugin =
    UniversalBlePlugin().also { plugin ->
        val handler = Mockito.mock(Handler::class.java)
        Mockito.doAnswer { invocation ->
            posts.add(invocation.getArgument(0))
            true
        }.`when`(handler).post(Mockito.any())
        plugin.setField("mainThreadHandler", handler)
    }

/** Runs every post recorded by [pluginWithRecordedLooper], in submission order. */
internal fun drainPosts(posts: MutableCollection<Runnable>) {
    while (posts.isNotEmpty()) {
        val next = posts.first()
        posts.remove(next)
        next.run()
    }
}

/** A gatt for [address] with no services resolved yet. */
internal fun mockGatt(address: String = GattIds.ADDRESS): BluetoothGatt {
    val device = Mockito.mock(BluetoothDevice::class.java)
    Mockito.`when`(device.address).thenReturn(address)
    return Mockito.mock(BluetoothGatt::class.java).also {
        Mockito.`when`(it.device).thenReturn(device)
    }
}

/** A characteristic in [serviceUuid], with no properties set. */
internal fun mockCharacteristic(
    serviceUuid: UUID = GattIds.SERVICE,
    characteristicUuid: UUID = GattIds.CHARACTERISTIC,
): BluetoothGattCharacteristic {
    val service = Mockito.mock(BluetoothGattService::class.java)
    Mockito.`when`(service.uuid).thenReturn(serviceUuid)
    return Mockito.mock(BluetoothGattCharacteristic::class.java).also {
        Mockito.`when`(it.uuid).thenReturn(characteristicUuid)
        Mockito.`when`(it.service).thenReturn(service)
    }
}

/**
 * One mock peripheral: a gatt whose [serviceUuid] service exposes
 * [characteristic] (with read/write properties) and, on demand, descriptors.
 */
internal class GattFixture(
    val address: String = GattIds.ADDRESS,
    val serviceUuid: UUID = GattIds.SERVICE,
    val characteristicUuid: UUID = GattIds.CHARACTERISTIC,
) {
    val service: BluetoothGattService = Mockito.mock(BluetoothGattService::class.java)
    val characteristic: BluetoothGattCharacteristic =
        Mockito.mock(BluetoothGattCharacteristic::class.java)
    val gatt: BluetoothGatt = mockGatt(address)

    init {
        Mockito.`when`(service.uuid).thenReturn(serviceUuid)
        Mockito.`when`(service.getCharacteristic(characteristicUuid)).thenReturn(characteristic)
        Mockito.`when`(characteristic.uuid).thenReturn(characteristicUuid)
        Mockito.`when`(characteristic.service).thenReturn(service)
        Mockito.`when`(characteristic.properties).thenReturn(
            BluetoothGattCharacteristic.PROPERTY_READ or
                BluetoothGattCharacteristic.PROPERTY_WRITE or
                BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE,
        )
        Mockito.`when`(gatt.getService(serviceUuid)).thenReturn(service)
    }

    /** A descriptor of [characteristic], registered for lookup by [uuid]. */
    fun descriptor(uuid: UUID = GattIds.CCCD): BluetoothGattDescriptor {
        val descriptor = Mockito.mock(BluetoothGattDescriptor::class.java)
        Mockito.`when`(descriptor.uuid).thenReturn(uuid)
        Mockito.`when`(descriptor.characteristic).thenReturn(characteristic)
        Mockito.`when`(characteristic.getDescriptor(uuid)).thenReturn(descriptor)
        return descriptor
    }

    /**
     * Stubs the pre-33 stack calls as accepted, as a live link does. JVM tests
     * run with Build.VERSION.SDK_INT == 0, so these are the overloads reached.
     */
    fun acceptOperations() {
        Mockito.`when`(
            gatt.writeCharacteristic(Mockito.any(BluetoothGattCharacteristic::class.java))
        ).thenReturn(true)
        Mockito.`when`(
            gatt.readCharacteristic(Mockito.any(BluetoothGattCharacteristic::class.java))
        ).thenReturn(true)
        Mockito.`when`(
            gatt.readDescriptor(Mockito.any(BluetoothGattDescriptor::class.java))
        ).thenReturn(true)
        Mockito.`when`(
            gatt.writeDescriptor(Mockito.any(BluetoothGattDescriptor::class.java))
        ).thenReturn(true)
        Mockito.`when`(
            gatt.setCharacteristicNotification(
                Mockito.any(BluetoothGattCharacteristic::class.java),
                Mockito.anyBoolean(),
            )
        ).thenReturn(true)
    }
}
