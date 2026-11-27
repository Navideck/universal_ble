package com.navideck.universal_ble

import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.mockito.Mockito

/*
 * A write can fail by throwing instead of returning a status, and a pending
 * result left registered by a call that threw makes every later write complete
 * one behind (#387). The realistic trigger is Android 15+, where
 * BluetoothGatt.writeCharacteristic(characteristic, value, writeType) throws
 * IllegalArgumentException for an attribute value longer than 512 bytes;
 * writeDescriptor does not length-check, but it throws for a stale descriptor
 * and a value over the attribute cap cannot work either.
 *
 * These tests drive the real plugin against a GATT that refuses the write. JVM
 * unit tests run with Build.VERSION.SDK_INT == 0, so the pre-33 overloads are
 * the ones actually called; the catch they exercise is shared with the API 33+
 * overloads.
 */
@Suppress("DEPRECATION") // The pre-33 overloads are the ones JVM tests reach.
internal class WriteRefusalTest {
    private val deviceAddress = GattIds.ADDRESS
    private val serviceUuid = GattIds.SERVICE
    private val charUuid = GattIds.CHARACTERISTIC
    private val descriptorUuid = GattIds.CCCD

    private val fixture = GattFixture()
    private val gatt get() = fixture.gatt
    private val characteristic get() = fixture.characteristic

    private fun pluginWithGatt(): UniversalBlePlugin =
        pluginWithInlineLooper().also { it.attachConnectedGatt(gatt) }

    private fun errorCode(result: Result<Unit>): String? =
        (result.exceptionOrNull() as? FlutterError)?.code

    @Test
    fun aRefusedWriteFailsItsCallAndWithdrawsItsPendingResult() {
        val plugin = pluginWithGatt()
        val acks = mutableListOf<Result<Unit>>()
        Mockito.doThrow(IllegalArgumentException("Characteristic must have a non-null service"))
            .`when`(gatt).writeCharacteristic(Mockito.any(BluetoothGattCharacteristic::class.java))

        plugin.writeValue(
            deviceAddress,
            serviceUuid.toString(),
            charUuid.toString(),
            ByteArray(20),
            BleOutputProperty.WITH_RESPONSE,
        ) { acks.add(it) }

        assertEquals(1, acks.size)
        assertEquals(
            UniversalBleErrorCode.WRITE_FAILED.raw.toString(),
            errorCode(acks.single()),
        )
        assertTrue(plugin.pendingWrites().isEmpty(), "a refused write must not stay pending")
    }

    @Test
    fun aWriteAfterARefusedWriteStillCompletesOnItsOwnCallback() {
        val plugin = pluginWithGatt()
        Mockito.doThrow(IllegalArgumentException("Characteristic must have a non-null service"))
            .`when`(gatt).writeCharacteristic(Mockito.any(BluetoothGattCharacteristic::class.java))

        val first = mutableListOf<Result<Unit>>()
        plugin.writeValue(
            deviceAddress,
            serviceUuid.toString(),
            charUuid.toString(),
            ByteArray(20),
            BleOutputProperty.WITH_RESPONSE,
        ) { first.add(it) }
        assertEquals(1, first.size, "the refused write must fail its own call")

        // Let the stack accept the next write.
        Mockito.doReturn(true)
            .`when`(gatt).writeCharacteristic(Mockito.any(BluetoothGattCharacteristic::class.java))

        val second = mutableListOf<Result<Unit>>()
        plugin.writeValue(
            deviceAddress,
            serviceUuid.toString(),
            charUuid.toString(),
            ByteArray(20),
            BleOutputProperty.WITH_RESPONSE,
        ) { second.add(it) }

        // Only the second write may be awaiting a completion.
        assertEquals(1, plugin.pendingWrites().size)
        assertTrue(second.isEmpty(), "the second write must wait for its own callback")

        plugin.onCharacteristicWrite(gatt, characteristic, BluetoothGatt.GATT_SUCCESS)

        assertEquals(1, second.size)
        assertTrue(second.single().isSuccess, "the second write must complete, not lag by one")
    }

    @Test
    fun anOversizedValueIsRejectedBeforeItReachesTheStack() {
        val plugin = pluginWithGatt()
        val acks = mutableListOf<Result<Unit>>()

        plugin.writeValue(
            deviceAddress,
            serviceUuid.toString(),
            charUuid.toString(),
            ByteArray(513),
            BleOutputProperty.WITHOUT_RESPONSE,
        ) { acks.add(it) }

        assertEquals(1, acks.size)
        assertEquals(
            UniversalBleErrorCode.INVALID_ATTRIBUTE_LENGTH.raw.toString(),
            errorCode(acks.single()),
        )
        assertTrue(plugin.pendingWrites().isEmpty())
        Mockito.verify(gatt, Mockito.never())
            .writeCharacteristic(Mockito.any(BluetoothGattCharacteristic::class.java))
    }

    @Test
    fun anOversizedValueStillReportsAMissingDevice() {
        // The length check runs after the lookups, so it does not shadow the
        // errors a caller got before it existed.
        val plugin = pluginWithInlineLooper()
        val acks = mutableListOf<Result<Unit>>()

        plugin.writeValue(
            deviceAddress,
            serviceUuid.toString(),
            charUuid.toString(),
            ByteArray(513),
            BleOutputProperty.WITHOUT_RESPONSE,
        ) { acks.add(it) }

        assertEquals(1, acks.size)
        assertEquals(
            UniversalBleErrorCode.DEVICE_NOT_FOUND.raw.toString(),
            errorCode(acks.single()),
        )
        assertTrue(plugin.pendingWrites().isEmpty())
    }

    @Test
    fun aRefusedDescriptorWriteWithdrawsItsPendingResult() {
        val plugin = pluginWithGatt()
        fixture.descriptor(descriptorUuid)
        Mockito.doThrow(IllegalArgumentException("Descriptor must have a non-null characteristic"))
            .`when`(gatt).writeDescriptor(Mockito.any(BluetoothGattDescriptor::class.java))

        val acks = mutableListOf<Result<Unit>>()
        plugin.writeDescriptorValue(
            deviceAddress,
            serviceUuid.toString(),
            charUuid.toString(),
            descriptorUuid.toString(),
            ByteArray(20),
        ) { acks.add(it) }

        assertEquals(1, acks.size)
        assertTrue(
            plugin.pendingDescriptorWrites().isEmpty(),
            "a refused descriptor write must not stay pending",
        )
    }

    @Test
    fun anOversizedDescriptorValueIsRejectedBeforeItReachesTheStack() {
        val plugin = pluginWithGatt()
        fixture.descriptor(descriptorUuid)

        val acks = mutableListOf<Result<Unit>>()
        plugin.writeDescriptorValue(
            deviceAddress,
            serviceUuid.toString(),
            charUuid.toString(),
            descriptorUuid.toString(),
            ByteArray(513),
        ) { acks.add(it) }

        assertEquals(1, acks.size)
        assertEquals(
            UniversalBleErrorCode.INVALID_ATTRIBUTE_LENGTH.raw.toString(),
            errorCode(acks.single()),
        )
        assertTrue(plugin.pendingDescriptorWrites().isEmpty())
        Mockito.verify(gatt, Mockito.never())
            .writeDescriptor(Mockito.any(BluetoothGattDescriptor::class.java))
    }
}
