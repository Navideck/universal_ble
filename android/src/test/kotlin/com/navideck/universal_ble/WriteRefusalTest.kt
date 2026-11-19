package com.navideck.universal_ble

import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattService
import android.os.Handler
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.mockito.Mockito

/*
 * The stack throws instead of returning a status for some writes: Android 13+
 * rejects an attribute value longer than 512 bytes from
 * `writeCharacteristic` / `writeDescriptor` with an IllegalArgumentException.
 * Android completes the oldest matching write, so a pending result left
 * registered by a call that threw makes every later write complete one behind
 * and the newest one time out (#387).
 *
 * These tests drive the real plugin against a GATT that refuses the write.
 */
internal class WriteRefusalTest {
  private val deviceAddress = "AA:BB:CC:DD:EE:FF"
  private val serviceUuid = UUID.fromString("0000fff0-0000-1000-8000-00805f9b34fb")
  private val charUuid = UUID.fromString("0000fff1-0000-1000-8000-00805f9b34fb")
  private val descriptorUuid = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

  private val service = Mockito.mock(BluetoothGattService::class.java)
  private val characteristic = Mockito.mock(BluetoothGattCharacteristic::class.java)
  private val gatt = Mockito.mock(BluetoothGatt::class.java)

  init {
    val device = Mockito.mock(BluetoothDevice::class.java)
    Mockito.`when`(device.address).thenReturn(deviceAddress)
    Mockito.`when`(gatt.device).thenReturn(device)

    Mockito.`when`(service.uuid).thenReturn(serviceUuid)
    Mockito.`when`(characteristic.uuid).thenReturn(charUuid)
    Mockito.`when`(characteristic.service).thenReturn(service)
    Mockito.`when`(characteristic.properties).thenReturn(
      BluetoothGattCharacteristic.PROPERTY_WRITE or
        BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE,
    )
    Mockito.`when`(service.getCharacteristic(charUuid)).thenReturn(characteristic)
    Mockito.`when`(gatt.getService(serviceUuid)).thenReturn(service)
  }

  private fun pluginWithInlineHandler(): UniversalBlePlugin {
    val plugin = UniversalBlePlugin()
    // Completions are posted to the main looper; run them inline so the test
    // observes them synchronously.
    val handler = Mockito.mock(Handler::class.java)
    Mockito.doAnswer { invocation ->
      invocation.getArgument<Runnable>(0).run()
      true
    }.`when`(handler).post(Mockito.any())
    plugin.setField("mainThreadHandler", handler)
    return plugin
  }

  private fun pluginWithGatt(): UniversalBlePlugin =
    pluginWithInlineHandler().also { it.gattRegistry().put(gatt) }

  private fun UniversalBlePlugin.pendingWrites(): List<WriteResultFuture> =
    getField("writeResultFutureList")

  private fun UniversalBlePlugin.pendingDescriptorWrites(): List<WriteDescriptorResultFuture> =
    getField("writeDescriptorResultFutureList")

  private fun errorCode(result: Result<Unit>): String? =
    (result.exceptionOrNull() as? FlutterError)?.code

  @Test
  fun aRefusedWriteFailsItsCallAndWithdrawsItsPendingResult() {
    val plugin = pluginWithGatt()
    val acks = mutableListOf<Result<Unit>>()
    Mockito.doThrow(IllegalArgumentException("Value length exceeds 512"))
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
    Mockito.doThrow(IllegalArgumentException("Value length exceeds 512"))
      .`when`(gatt).writeCharacteristic(Mockito.any(BluetoothGattCharacteristic::class.java))

    val first = mutableListOf<Result<Unit>>()
    plugin.writeValue(
      deviceAddress,
      serviceUuid.toString(),
      charUuid.toString(),
      ByteArray(20),
      BleOutputProperty.WITH_RESPONSE,
    ) { first.add(it) }

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
  fun aRefusedDescriptorWriteWithdrawsItsPendingResult() {
    val plugin = pluginWithGatt()
    val descriptor = Mockito.mock(BluetoothGattDescriptor::class.java)
    Mockito.`when`(descriptor.uuid).thenReturn(descriptorUuid)
    Mockito.`when`(characteristic.getDescriptor(descriptorUuid)).thenReturn(descriptor)
    Mockito.doThrow(IllegalArgumentException("Value length exceeds 512"))
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
}
