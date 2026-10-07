package com.navideck.universal_ble

import android.bluetooth.BluetoothGatt
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/*
 * The GATT status of onConnectionStateChange is delivered to Dart twice: as the
 * unified UniversalBleErrorCode and as the raw value (nativeErrorCode).
 */
internal class ConnectionErrorCodeTest {

    @Test
    fun successHasNoCodes() {
        assertNull(BluetoothGatt.GATT_SUCCESS.toGattErrorCode())
        assertNull(BluetoothGatt.GATT_SUCCESS.toConnectionErrorCode())
    }

    @Test
    fun rawCodeIsPassedThrough() {
        assertEquals(0x08L, 0x08.toGattErrorCode())
        assertEquals(257L, BluetoothGatt.GATT_FAILURE.toGattErrorCode())
    }

    @Test
    fun timeoutCodesMapToConnectionTimeout() {
        assertEquals(UniversalBleErrorCode.CONNECTION_TIMEOUT, 0x08.toConnectionErrorCode())
        assertEquals(UniversalBleErrorCode.CONNECTION_TIMEOUT, 0x93.toConnectionErrorCode())
    }

    @Test
    fun peerDisconnectCodesMapToDeviceDisconnected() {
        assertEquals(UniversalBleErrorCode.DEVICE_DISCONNECTED, 0x13.toConnectionErrorCode())
        assertEquals(
            UniversalBleErrorCode.DEVICE_DISCONNECTED,
            BluetoothGatt.GATT_FAILURE.toConnectionErrorCode()
        )
    }

    @Test
    fun localTerminationMapsToConnectionTerminated() {
        assertEquals(UniversalBleErrorCode.CONNECTION_TERMINATED, 0x16.toConnectionErrorCode())
    }

    @Test
    fun establishmentFailuresMapToConnectionFailed() {
        assertEquals(UniversalBleErrorCode.CONNECTION_FAILED, 0x3E.toConnectionErrorCode())
        assertEquals(UniversalBleErrorCode.CONNECTION_FAILED, 0x85.toConnectionErrorCode())
        assertEquals(
            UniversalBleErrorCode.CONNECTION_FAILED,
            BluetoothGatt.GATT_CONNECTION_CONGESTED.toConnectionErrorCode()
        )
    }

    @Test
    fun otherCodesMapToUnknownError() {
        assertEquals(UniversalBleErrorCode.UNKNOWN_ERROR, 0x22.toConnectionErrorCode())
        assertEquals(UniversalBleErrorCode.UNKNOWN_ERROR, 0x3B.toConnectionErrorCode())
    }
}
