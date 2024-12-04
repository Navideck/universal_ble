package com.navideck.universal_ble

import android.annotation.SuppressLint
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanSettings
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.util.LinkedList

private const val NUM_SCAN_DURATIONS_KEPT = 5
private const val EXCESSIVE_SCANNING_PERIOD_MS = 30 * 1000L
private const val TAG = "UniversalBlePlugin"

@SuppressLint("MissingPermission")
class SafeScanner(private val scanner: BluetoothLeScanner) {
    private val handler = Handler(Looper.myLooper()!!)
    private val startTimes = LinkedList<Long>()
    private var awaitingScan = false

    fun startScan(filters: List<ScanFilter>, settings: ScanSettings, callback: ScanCallback) {
        val now = System.currentTimeMillis()
        startTimes.removeAll { now - it > EXCESSIVE_SCANNING_PERIOD_MS }

        if (startTimes.size >= NUM_SCAN_DURATIONS_KEPT) {
            if (awaitingScan) {
                Log.e(TAG, "startScan: too frequent, awaiting scan..")
                return
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                callback.onScanFailed(ScanCallback.SCAN_FAILED_SCANNING_TOO_FREQUENTLY)
            }

            awaitingScan = true
            val delay = startTimes.first + EXCESSIVE_SCANNING_PERIOD_MS - now + 2_000
            Log.e(TAG, "startScan: too frequent, schedule auto-start after $delay ms $startTimes")

            handler.postDelayed({
                Log.d(TAG, "Retrying scan after delay")
                awaitingScan = false
                startScan(filters, settings, callback)
            }, delay)
        } else {
            awaitingScan = false
            startTimes.addLast(now)
            try {
                scanner.startScan(filters, settings, callback)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start Scan : $e")
            }
        }
    }

    fun stopScan(callback: ScanCallback) {
        awaitingScan = false
        handler.removeCallbacksAndMessages(null)
        scanner.stopScan(callback)
    }
}