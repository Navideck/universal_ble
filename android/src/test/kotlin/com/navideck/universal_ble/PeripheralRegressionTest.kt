package com.navideck.universal_ble

import android.bluetooth.*
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.Context
import java.util.UUID
import kotlin.test.*
import org.mockito.Mockito

internal class PeripheralRegressionTest {
    private val report = "00002a4d-0000-1000-8000-00805f9b34fb"
    private val otherReport = "00002a4e-0000-1000-8000-00805f9b34fb"
    private val hid = "00001812-0000-1000-8000-00805f9b34fb"
    private val otherService = "0000180f-0000-1000-8000-00805f9b34fb"
    private val deviceAddress = "AA:BB:CC:DD:EE:FF"

    @Suppress("UNCHECKED_CAST")
    private fun characteristics(): MutableMap<String, BluetoothGattCharacteristic> {
        val field = Class.forName("com.navideck.universal_ble.UniversalBlePeripheralExtensionsKt")
            .getDeclaredField("bluetoothGattCharacteristics")
        field.isAccessible = true
        return field.get(null) as MutableMap<String, BluetoothGattCharacteristic>
    }

    @Suppress("UNCHECKED_CAST")
    private fun characteristicInstanceIds(): MutableMap<BluetoothGattCharacteristic, String> {
        val field = Class.forName("com.navideck.universal_ble.UniversalBlePeripheralExtensionsKt")
            .getDeclaredField("characteristicInstanceIds")
        field.isAccessible = true
        return field.get(null) as MutableMap<BluetoothGattCharacteristic, String>
    }

    @AfterTest fun cleanup() = clearPeripheralCaches()

    private fun mockService(uuid: String, vararg characteristics: BluetoothGattCharacteristic): BluetoothGattService {
        val service = Mockito.mock(BluetoothGattService::class.java)
        Mockito.`when`(service.uuid).thenReturn(UUID.fromString(uuid))
        Mockito.`when`(service.characteristics).thenReturn(characteristics.toList())
        return service
    }

    private fun mockCharacteristic(
        uuid: String,
        service: BluetoothGattService,
    ): BluetoothGattCharacteristic {
        val characteristic = Mockito.mock(BluetoothGattCharacteristic::class.java)
        Mockito.`when`(characteristic.uuid).thenReturn(UUID.fromString(uuid))
        Mockito.`when`(characteristic.service).thenReturn(service)
        return characteristic
    }

    /**
     * The real plugin cannot be constructed in a unit test (its constructor needs
     * a main looper), so the fields the peripheral paths touch are seeded instead.
     */
    private fun peripheralPlugin(
        server: BluetoothGattServer,
        advertiser: BluetoothLeAdvertiser = Mockito.mock(BluetoothLeAdvertiser::class.java),
    ): UniversalBlePeripheralPlugin {
        val plugin = Mockito.mock(UniversalBlePeripheralPlugin::class.java, Mockito.CALLS_REAL_METHODS)
        val manager = Mockito.mock(BluetoothManager::class.java)
        // ensurePeripheralInitialized reads the adapter before it reuses the
        // already opened server.
        Mockito.`when`(manager.adapter).thenReturn(Mockito.mock(BluetoothAdapter::class.java))
        plugin.setField("applicationContext", Mockito.mock(Context::class.java))
        plugin.setField("bluetoothManager", manager)
        plugin.setField("bluetoothLeAdvertiser", advertiser)
        plugin.setField("gattServer", server)
        plugin.setField("bluetoothDevicesMap", HashMap<String, BluetoothDevice>())
        plugin.setField("mtuByDeviceId", HashMap<String, Int>())
        plugin.setField("pendingNotifications", ArrayDeque<Any>())
        plugin.setField("notificationsInFlight", HashSet<String>())
        return plugin
    }

    private fun UniversalBlePeripheralPlugin.setField(name: String, value: Any?) {
        val field = UniversalBlePeripheralPlugin::class.java.getDeclaredField(name)
        field.isAccessible = true
        field.set(this, value)
    }

    private fun <T> UniversalBlePeripheralPlugin.field(name: String): T {
        val field = UniversalBlePeripheralPlugin::class.java.getDeclaredField(name)
        field.isAccessible = true
        @Suppress("UNCHECKED_CAST")
        return field.get(this) as T
    }

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
        val plugin = peripheralPlugin(Mockito.mock(BluetoothGattServer::class.java))
        val characteristic = Mockito.mock(BluetoothGattCharacteristic::class.java)
        Mockito.`when`(characteristic.properties).thenReturn(BluetoothGattCharacteristic.PROPERTY_READ)
        characteristics()[report] = characteristic
        val value = byteArrayOf(42)
        plugin.updateCharacteristic(report, null, value, null)
        Mockito.verify(characteristic).setValue(value)
    }

    // #385: a service registered a second time must resolve to the new
    // characteristics, not the ones the server no longer holds.
    @Test fun clearServicesForgetsTheRegisteredCharacteristics() {
        val server = Mockito.mock(BluetoothGattServer::class.java)
        val plugin = peripheralPlugin(server)
        val service = mockService(hid)
        val characteristic = mockCharacteristic(report, service)
        characteristics()[report] = characteristic

        plugin.clearServices()

        assertNull(report.findGattCharacteristic())
        assertNull(hid.findService())
        val replacement = mockCharacteristic(report, service)
        characteristics().putIfAbsent(report, replacement)
        assertSame(replacement, report.findGattCharacteristic())
        Mockito.verify(server).clearServices()
    }

    // #385: removing one service must not drop another service's state.
    @Test fun removeServiceForgetsOnlyThatServicesState() {
        val server = Mockito.mock(BluetoothGattServer::class.java)
        val plugin = peripheralPlugin(server)
        val removedService = Mockito.mock(BluetoothGattService::class.java)
        val keptService = Mockito.mock(BluetoothGattService::class.java)
        val removedCharacteristic = mockCharacteristic(report, removedService)
        val keptCharacteristic = mockCharacteristic(otherReport, keptService)
        Mockito.`when`(removedService.uuid).thenReturn(UUID.fromString(hid))
        Mockito.`when`(removedService.characteristics).thenReturn(listOf(removedCharacteristic))
        Mockito.`when`(keptService.uuid).thenReturn(UUID.fromString(otherService))
        Mockito.`when`(keptService.characteristics).thenReturn(listOf(keptCharacteristic))
        characteristics()[report] = removedCharacteristic
        characteristics()["report-1"] = removedCharacteristic
        characteristicInstanceIds()[removedCharacteristic] = "report-1"
        characteristics()[otherReport] = keptCharacteristic
        characteristicInstanceIds()[keptCharacteristic] = "report-2"
        subscribedCharDevicesMap[deviceAddress] = mutableSetOf("report-1", "report-2")

        plugin.removeService(hid)

        assertNull(report.findGattCharacteristic())
        assertNull(report.findGattCharacteristic("report-1"))
        assertSame(keptCharacteristic, otherReport.findGattCharacteristic())
        assertEquals("report-2", keptCharacteristic.instanceId())
        assertEquals<Set<String>?>(setOf("report-2"), subscribedCharDevicesMap[deviceAddress])
        Mockito.verify(server).removeService(removedService)
    }
}
