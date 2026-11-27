package com.navideck.universal_ble

import android.bluetooth.BluetoothDevice
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.os.Handler
import android.os.SystemClock
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import org.mockito.ArgumentMatchers.any
import org.mockito.Mockito

/*
 * The helper is unit-tested on its own in ScanResultConnectableTest, but nothing
 * would fail if the scan callback went back to reading `result.isConnectable`
 * directly - which is the crash #383 fixed. This drives the real callback so
 * the call site itself is pinned.
 *
 * JVM unit tests run with Build.VERSION.SDK_INT == 0, so connectableOrNull()
 * takes the "unknown" branch and never touches ScanResult; a reverted call site
 * reads the mock's default `false` instead, which both assertions below reject.
 */
internal class ScanCallbackConnectableTest {
    private val scanResults = mutableListOf<UniversalBleScanResult>()

    private fun plugin(): UniversalBlePlugin {
        // Callbacks are posted to the main looper; run them inline.
        val plugin = pluginWithInlineLooper()
        plugin.setField(
            "callbackChannel",
            Mockito.mock(UniversalBleCallbackChannel::class.java) { invocation ->
                if (invocation.method.name == "onScanResult") {
                    scanResults.add(invocation.getArgument(0))
                }
                null
            },
        )
        return plugin
    }

    private fun scanResult(): ScanResult {
        val device = Mockito.mock(BluetoothDevice::class.java)
        Mockito.`when`(device.address).thenReturn("AA:BB:CC:DD:EE:FF")
        val result = Mockito.mock(ScanResult::class.java)
        Mockito.`when`(result.device).thenReturn(device)
        return result
    }

    private fun onScanResult(plugin: UniversalBlePlugin, result: ScanResult) {
        val scanCallback: ScanCallback = plugin.getField("scanCallback")
        // The callback converts the packet timestamp through the monotonic
        // clock, which the JVM stub throws on.
        Mockito.mockStatic(SystemClock::class.java).use {
            scanCallback.onScanResult(ScanSettings.CALLBACK_TYPE_ALL_MATCHES, result)
        }
    }

    @Test
    fun scanCallbackReportsUnknownConnectabilityBelowApi26() {
        val plugin = plugin()
        val result = scanResult()

        onScanResult(plugin, result)

        assertEquals(1, scanResults.size)
        assertNull(scanResults.single().connectable)
        Mockito.verify(result, Mockito.never()).isConnectable
    }
}
