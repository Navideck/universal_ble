package com.navideck.universal_ble

import android.bluetooth.*
import android.bluetooth.le.BluetoothLeAdvertiser
import java.util.UUID
import kotlin.test.*
import org.mockito.Mockito

internal class PeripheralRegressionTest {
    private val report = "00002a4d-0000-1000-8000-00805f9b34fb"
    private val hid = "00001812-0000-1000-8000-00805f9b34fb"

    @Suppress("UNCHECKED_CAST")
    private fun characteristics(): MutableMap<String, BluetoothGattCharacteristic> {
        val field = Class.forName("com.navideck.universal_ble.UniversalBlePeripheralExtensionsKt")
            .getDeclaredField("bluetoothGattCharacteristics")
        field.isAccessible = true
        return field.get(null) as MutableMap<String, BluetoothGattCharacteristic>
    }

    @AfterTest fun cleanup() = clearPeripheralCaches()

    @Test fun findsServiceByItsServiceUuid() {
        val service = Mockito.mock(BluetoothGattService::class.java)
        Mockito.`when`(service.uuid).thenReturn(UUID.fromString(hid))
        val characteristic = Mockito.mock(BluetoothGattCharacteristic::class.java)
        Mockito.`when`(characteristic.service).thenReturn(service)
        Mockito.`when`(characteristic.uuid).thenReturn(UUID.fromString(report))
        characteristics()[report] = characteristic
        assertSame(service, hid.findService())
    }

    @Test fun newClientDoesNotInheritAnothersCccdValue() {
        val characteristic = Mockito.mock(BluetoothGattCharacteristic::class.java)
        Mockito.`when`(characteristic.uuid).thenReturn(UUID.fromString(report))
        val descriptor = Mockito.mock(BluetoothGattDescriptor::class.java)
        Mockito.`when`(descriptor.uuid).thenReturn(UUID.fromString(peripheralDescriptorCCUUID))
        Mockito.`when`(descriptor.characteristic).thenReturn(characteristic)
        // onDescriptorWriteRequest assigns this shared value before storing the client value.
        Mockito.`when`(descriptor.value).thenReturn(byteArrayOf(1, 0))
        descriptor.storeClientValue("AA:BB:CC:DD:EE:FF", byteArrayOf(1, 0))
        assertContentEquals(byteArrayOf(0, 0), descriptor.getClientValue("11:22:33:44:55:66"))
    }

    @Test fun updateWithoutSubscribersStillUpdatesReadableValue() {
        val plugin = Mockito.mock(UniversalBlePeripheralPlugin::class.java, Mockito.CALLS_REAL_METHODS)
        fun field(name: String, value: Any) {
            val field = UniversalBlePeripheralPlugin::class.java.getDeclaredField(name)
            field.isAccessible = true
            field.set(plugin, value)
        }
        val adapter = Mockito.mock(BluetoothAdapter::class.java)
        val manager = Mockito.mock(BluetoothManager::class.java)
        Mockito.`when`(manager.adapter).thenReturn(adapter)
        field("bluetoothManager", manager)
        field("gattServer", Mockito.mock(BluetoothGattServer::class.java))
        field("bluetoothLeAdvertiser", Mockito.mock(BluetoothLeAdvertiser::class.java))
        field("bluetoothDevicesMap", HashMap<String, BluetoothDevice>())
        field("pendingNotifications", ArrayDeque<Any>())
        field("notificationsInFlight", HashSet<String>())
        val characteristic = Mockito.mock(BluetoothGattCharacteristic::class.java)
        Mockito.`when`(characteristic.properties).thenReturn(BluetoothGattCharacteristic.PROPERTY_READ)
        characteristics()[report] = characteristic
        val value = byteArrayOf(42)
        plugin.updateCharacteristic(report, null, value, null)
        Mockito.verify(characteristic).setValue(value)
    }
}
