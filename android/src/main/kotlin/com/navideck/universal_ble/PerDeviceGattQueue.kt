package com.navideck.universal_ble

import java.util.ArrayDeque
import java.util.concurrent.ConcurrentHashMap

/**
 * Serializes BluetoothGatt operations per device.
 *
 * Android's BluetoothGatt cannot safely overlap asynchronous operations for
 * the same connection. The Dart-level queue is a cross-platform abstraction
 * that Apple requires to be bypassed (`QueueType.none`) for write throughput,
 * so the native layer must protect Android itself.
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
    fun submit(
        deviceId: String,
        kind: String,
        onCancel: () -> Unit = {},
        operation: () -> Unit,
    ) {
        queues.computeIfAbsent(deviceId) { DeviceQueue() }.submit(kind, onCancel, operation)
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
        private val pending = ArrayDeque<QueuedOperation>()
        private var inFlight: QueuedOperation? = null

        fun submit(kind: String, onCancel: () -> Unit, operation: () -> Unit) {
            val queuedOperation = QueuedOperation(kind, operation, onCancel)
            val runImmediately: Boolean
            synchronized(lock) {
                if (inFlight == null) {
                    inFlight = queuedOperation
                    queuedOperation.started = true
                    runImmediately = true
                } else {
                    pending.addLast(queuedOperation)
                    runImmediately = false
                }
            }
            if (runImmediately) runOperation(queuedOperation)
        }

        fun onOperationComplete(kind: String) {
            val next = synchronized(lock) {
                if (inFlight?.kind != kind) return
                pending.pollFirst().also { inFlight = it }
            }
            if (next != null) {
                dispatch {
                    val shouldRun = synchronized(lock) {
                        if (inFlight !== next || next.started) {
                            false
                        } else {
                            next.started = true
                            true
                        }
                    }
                    if (shouldRun) runOperation(next)
                }
            }
        }

        fun cancelAll() {
            val cancelled = synchronized(lock) {
                val operations = pending.toMutableList()
                pending.clear()
                inFlight?.takeIf { !it.started }?.let(operations::add)
                inFlight = null
                operations
            }
            cancelled.forEach {
                try {
                    it.onCancel()
                } catch (t: Throwable) {
                    UniversalBleLogger.logError("GATT operation cancellation failed: $t")
                }
            }
        }

        fun isBusy(): Boolean = synchronized(lock) { inFlight != null }

        private fun runOperation(queuedOperation: QueuedOperation) {
            try {
                queuedOperation.operation()
            } catch (t: Throwable) {
                UniversalBleLogger.logError("Serialized GATT operation failed: $t")
                onOperationComplete(queuedOperation.kind)
            }
        }
    }

    private data class QueuedOperation(
        val kind: String,
        val operation: () -> Unit,
        val onCancel: () -> Unit,
        var started: Boolean = false,
    )
}
