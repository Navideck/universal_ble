package com.navideck.universal_ble

import java.util.ArrayDeque
import java.util.concurrent.ConcurrentHashMap

/**
 * Serializes BluetoothGatt operations per device.
 *
 * Android's BluetoothGatt allows only a single outstanding GATT operation per
 * device: readRemoteRssi(), writeCharacteristic(), readCharacteristic(),
 * requestMtu() and discoverServices() all contend on the same AOSP
 * `mDeviceBusy` lock and return `false` (or status 133) when it is held. The
 * Dart-level queue is a cross-platform abstraction that Apple requires to be
 * bypassed (`QueueType.none`) for write throughput, so the native layer must
 * protect Android itself.
 *
 * Operations submitted for a device run strictly one at a time; the next
 * operation starts only after the previous one's GATT callback fires (via
 * [onOperationComplete]) or it completes synchronously. Different devices are
 * independent, matching Android's model where operations on distinct
 * connections do not conflict.
 *
 * [kind] tags an operation with the GATT callback that completes it. A
 * completion is only honored when it matches the kind of the in-flight
 * operation, so a stray callback (e.g. a background service discovery from
 * `getSystemDevices`) can never release an unrelated operation.
 */
class PerDeviceGattQueue(
    private val dispatch: (() -> Unit) -> Unit = { action -> action() },
) {
    private val queues = ConcurrentHashMap<String, DeviceQueue>()

    /** Submits [operation] for [deviceId]; runs immediately when idle, else FIFO. */
    fun submit(deviceId: String, kind: String, operation: () -> Unit) {
        queues.computeIfAbsent(deviceId) { DeviceQueue() }.submit(kind, operation)
    }

    /** Signals that the in-flight operation for [deviceId] finished. */
    fun onOperationComplete(deviceId: String, kind: String) {
        queues[deviceId]?.onOperationComplete(kind)
    }

    /** Drops queued operations for [deviceId] and marks it idle (e.g. on disconnect). */
    fun cancelAll(deviceId: String) {
        queues.remove(deviceId)?.cancelAll()
    }

    /** Drops every queued operation (e.g. on engine detach). */
    fun clear() {
        queues.values.forEach { it.cancelAll() }
        queues.clear()
    }

    /** Whether [deviceId] currently has an in-flight operation. */
    fun isBusy(deviceId: String): Boolean {
        return queues[deviceId]?.isBusy() ?: false
    }

    private inner class DeviceQueue {
        private val lock = Any()
        private val pending = ArrayDeque<Pair<String, () -> Unit>>()
        private var busy = false
        private var inFlightKind: String? = null

        fun submit(kind: String, operation: () -> Unit) {
            synchronized(lock) {
                if (!busy) {
                    busy = true
                    inFlightKind = kind
                    runOperation(kind, operation)
                } else {
                    pending.addLast(kind to operation)
                }
            }
        }

        fun onOperationComplete(kind: String) {
            synchronized(lock) {
                if (!busy || inFlightKind != kind) return
                val next = pending.pollFirst()
                if (next != null) {
                    inFlightKind = next.first
                    dispatch { runOperation(next.first, next.second) }
                } else {
                    busy = false
                    inFlightKind = null
                }
            }
        }

        fun cancelAll() {
            synchronized(lock) {
                pending.clear()
                busy = false
                inFlightKind = null
            }
        }

        fun isBusy(): Boolean = synchronized(lock) { busy }

        private fun runOperation(kind: String, operation: () -> Unit) {
            try {
                operation()
            } catch (t: Throwable) {
                UniversalBleLogger.logError("Serialized GATT operation failed: $t")
                onOperationComplete(kind)
            }
        }
    }
}