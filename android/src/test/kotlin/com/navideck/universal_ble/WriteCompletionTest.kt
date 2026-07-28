package com.navideck.universal_ble

import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattService
import android.os.Handler
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.mockito.Mockito

/*
 * Android serializes GATT operations per device, so an onCharacteristicWrite
 * callback always belongs to the oldest write submitted for that
 * characteristic. Completing every pending future that matches
 * (device, service, characteristic) conflates distinct operations: one
 * callback acknowledges writes whose bytes were never transmitted (a "false
 * ACK"), and the operation whose response later arrives finds no future left,
 * or worse, completes the next one - a sustained off-by-one.
 *
 * These tests drive the real plugin callback against seeded pending writes.
 */
internal class WriteCompletionTest {
    private val deviceAddress = "AA:BB:CC:DD:EE:FF"
    private val serviceUuid = UUID.fromString("0000fff0-0000-1000-8000-00805f9b34fb")
    private val charUuid = UUID.fromString("0000fff1-0000-1000-8000-00805f9b34fb")

    private fun pluginWithInlineHandler(): UniversalBlePlugin {
        val plugin = UniversalBlePlugin()
        // Completions are posted to the main looper; execute them inline so
        // the test observes them synchronously.
        val handler = Mockito.mock(Handler::class.java)
        Mockito.doAnswer { invocation ->
            invocation.getArgument<Runnable>(0).run()
            true
        }.`when`(handler).post(Mockito.any())
        val handlerField = UniversalBlePlugin::class.java.getDeclaredField("mainThreadHandler")
        handlerField.isAccessible = true
        handlerField.set(plugin, handler)
        return plugin
    }

    @Suppress("UNCHECKED_CAST")
    private fun pendingWrites(plugin: UniversalBlePlugin): MutableList<WriteResultFuture> {
        val listField = UniversalBlePlugin::class.java.getDeclaredField("writeResultFutureList")
        listField.isAccessible = true
        return listField.get(plugin) as MutableList<WriteResultFuture>
    }

    private fun mockGatt(): BluetoothGatt {
        val device = Mockito.mock(BluetoothDevice::class.java)
        Mockito.`when`(device.address).thenReturn(deviceAddress)
        val gatt = Mockito.mock(BluetoothGatt::class.java)
        Mockito.`when`(gatt.device).thenReturn(device)
        return gatt
    }

    private fun mockCharacteristic(): BluetoothGattCharacteristic {
        val service = Mockito.mock(BluetoothGattService::class.java)
        Mockito.`when`(service.uuid).thenReturn(serviceUuid)
        val characteristic = Mockito.mock(BluetoothGattCharacteristic::class.java)
        Mockito.`when`(characteristic.uuid).thenReturn(charUuid)
        Mockito.`when`(characteristic.service).thenReturn(service)
        return characteristic
    }

    private fun pendingFuture(acks: MutableList<Result<Unit>>) = WriteResultFuture(
        deviceAddress,
        charUuid.toString(),
        serviceUuid.toString(),
    ) { acks.add(it) }

    @Test
    fun oneWriteCompletionMustNotAckOtherPendingWrites() {
        val plugin = pluginWithInlineHandler()
        val firstAcks = mutableListOf<Result<Unit>>()
        val secondAcks = mutableListOf<Result<Unit>>()
        val pending = pendingWrites(plugin)
        synchronized(pending) {
            pending.add(pendingFuture(firstAcks))
            pending.add(pendingFuture(secondAcks))
        }

        // The ATT response of the FIRST write arrives.
        plugin.onCharacteristicWrite(mockGatt(), mockCharacteristic(), BluetoothGatt.GATT_SUCCESS)

        assertEquals(1, firstAcks.size, "oldest pending write should be acknowledged")
        assertTrue(firstAcks[0].isSuccess)
        assertEquals(
            0,
            secondAcks.size,
            "second write is still in flight: acknowledging it with the first " +
                "write's status is a false ACK",
        )

        // The second write's own response must then complete it - exactly once.
        plugin.onCharacteristicWrite(mockGatt(), mockCharacteristic(), BluetoothGatt.GATT_SUCCESS)
        assertEquals(1, secondAcks.size, "second write acknowledged by its own response")
        assertEquals(1, firstAcks.size, "first write must not be acknowledged twice")
    }

    @Test
    fun failedCompletionMustFailOnlyTheOldestPendingWrite() {
        val plugin = pluginWithInlineHandler()
        val firstAcks = mutableListOf<Result<Unit>>()
        val secondAcks = mutableListOf<Result<Unit>>()
        val pending = pendingWrites(plugin)
        synchronized(pending) {
            pending.add(pendingFuture(firstAcks))
            pending.add(pendingFuture(secondAcks))
        }

        plugin.onCharacteristicWrite(mockGatt(), mockCharacteristic(), BluetoothGatt.GATT_FAILURE)

        assertEquals(1, firstAcks.size, "oldest pending write should be failed")
        assertTrue(firstAcks[0].isFailure)
        assertEquals(
            0,
            secondAcks.size,
            "an error of the first write must not be propagated to the second, " +
                "still-in-flight write",
        )
    }
}
