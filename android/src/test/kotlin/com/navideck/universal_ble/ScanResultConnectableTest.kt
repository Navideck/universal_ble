package com.navideck.universal_ble

import android.bluetooth.le.ScanResult
import android.os.Build
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import org.mockito.Mockito.mock
import org.mockito.Mockito.`when`
import org.mockito.Mockito.verifyNoInteractions

internal class ScanResultConnectableTest {

    @Test
    fun reportsUnknownBeforeApi26() {
        // Regression for #383: ScanResult.isConnectable() is API 26+, so reading
        // it on Android 7.x killed the process with NoSuchMethodError.
        val scanResult = mock(ScanResult::class.java)

        assertNull(scanResult.connectableOrNull(sdkInt = Build.VERSION_CODES.N_MR1))
        verifyNoInteractions(scanResult)
    }

    @Test
    fun reportsConnectableFromApi26() {
        val scanResult = mock(ScanResult::class.java)
        `when`(scanResult.isConnectable).thenReturn(true)

        assertEquals(true, scanResult.connectableOrNull(sdkInt = Build.VERSION_CODES.O))
    }

    @Test
    fun reportsNonConnectableFromApi26() {
        // A guard that returned a constant instead of the platform value would
        // keep the connectable case green, so the false case is pinned too.
        val scanResult = mock(ScanResult::class.java)
        `when`(scanResult.isConnectable).thenReturn(false)

        assertEquals(false, scanResult.connectableOrNull(sdkInt = Build.VERSION_CODES.O))
    }
}
