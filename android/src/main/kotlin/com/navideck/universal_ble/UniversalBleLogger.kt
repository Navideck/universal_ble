package com.navideck.universal_ble

import android.util.Log
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object UniversalBleLogger {
    private const val TAG = "UniversalBle"
    private var currentLogLevel: UniversalBleLogLevel = UniversalBleLogLevel.NONE
    private val timeFormatter = SimpleDateFormat("HH:mm:ss.SSS", Locale.US)

    fun setLogLevel(logLevel: UniversalBleLogLevel) {
        currentLogLevel = logLevel
    }

    fun logError(message: String) {
        if (!allows(UniversalBleLogLevel.ERROR)) return
        Log.e(TAG, withTimestamp(message))
    }

    fun logWarning(message: String) {
        if (!allows(UniversalBleLogLevel.WARNING)) return
        Log.w(TAG, withTimestamp(message))
    }

    fun logInfo(message: String) {
        if (!allows(UniversalBleLogLevel.INFO)) return
        Log.i(TAG, withTimestamp(message))
    }

    fun logDebug(message: String) {
        if (!allows(UniversalBleLogLevel.DEBUG)) return
        Log.d(TAG, withTimestamp(message))
    }

    fun logVerbose(message: String) {
        if (!allows(UniversalBleLogLevel.VERBOSE)) return
        Log.v(TAG, withTimestamp(message))
    }

    private fun allows(level: UniversalBleLogLevel): Boolean {
        return currentLogLevel != UniversalBleLogLevel.NONE && level.ordinal <= currentLogLevel.ordinal
    }

    private fun withTimestamp(message: String): String {
        return "[${timeFormatter.format(Date())}] $message"
    }
}
