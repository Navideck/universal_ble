package com.navideck.universal_ble

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/*
 * PerDeviceGattQueue serializes GATT operations per device so that Android's
 * single-outstanding-operation rule (mDeviceBusy) is never violated, even when
 * the Dart layer runs QueueType.none. Operations for the same device must run
 * one at a time and release the next only after the in-flight operation's kind
 * completes; operations for different devices must be independent.
 */
internal class PerDeviceGattQueueTest {
    @Test
    fun runsSecondOperationOnlyAfterFirstCompletes() {
        val queue = PerDeviceGattQueue()
        val order = mutableListOf<String>()

        queue.submit("dev1", Q_WRITE) { order.add("write") }
        queue.submit("dev1", Q_READ) { order.add("read") }

        // write runs immediately; read is queued behind it.
        assertEquals(listOf("write"), order)

        // Completing a different kind must not advance the queue.
        queue.onOperationComplete("dev1", Q_READ)
        assertEquals(listOf("write"), order, "read completion must not release a write")

        queue.onOperationComplete("dev1", Q_WRITE)
        assertEquals(listOf("write", "read"), order)
    }

    @Test
    fun fifoOrderIsPreservedForManyPendingOperations() {
        val queue = PerDeviceGattQueue()
        val order = mutableListOf<String>()

        (0 until 5).forEach { i ->
            queue.submit("dev1", Q_WRITE) { order.add("op$i") }
        }

        assertEquals(listOf("op0"), order)
        repeat(5) { i ->
            queue.onOperationComplete("dev1", Q_WRITE)
            assertEquals(
                (0..(i + 1).coerceAtMost(4)).map { j -> "op$j" },
                order,
            )
        }
    }

    @Test
    fun devicesAreSerializedIndependently() {
        val queue = PerDeviceGattQueue()
        val order = mutableListOf<String>()

        queue.submit("dev1", Q_WRITE) { order.add("dev1-write") }
        queue.submit("dev2", Q_WRITE) { order.add("dev2-write") }

        // Both devices run immediately; no cross-device blocking.
        assertEquals(listOf("dev1-write", "dev2-write"), order)

        queue.onOperationComplete("dev1", Q_WRITE)
        queue.onOperationComplete("dev2", Q_WRITE)
        assertEquals(listOf("dev1-write", "dev2-write"), order)
    }

    @Test
    fun cancelAllDropsPendingOperations() {
        val queue = PerDeviceGattQueue()
        val order = mutableListOf<String>()
        val cancelled = mutableListOf<String>()

        queue.submit("dev1", Q_WRITE) { order.add("write") }
        queue.submit("dev1", Q_READ, onCancel = { cancelled.add("read") }) {
            order.add("read")
        }

        queue.cancelAll("dev1")

        // The cancelled in-flight op must not advance to the queued read.
        queue.onOperationComplete("dev1", Q_WRITE)
        assertEquals(listOf("write"), order)
        assertEquals(listOf("read"), cancelled)

        // New submissions for the device run immediately again.
        queue.submit("dev1", Q_WRITE) { order.add("write2") }
        assertEquals(listOf("write", "write2"), order)
    }

    @Test
    fun cancelAllPreventsDispatchedOperationFromStarting() {
        val dispatched = mutableListOf<() -> Unit>()
        val queue = PerDeviceGattQueue(dispatch = { dispatched.add(it) })
        val order = mutableListOf<String>()
        val cancelled = mutableListOf<String>()

        queue.submit("dev1", Q_WRITE) { order.add("write") }
        queue.submit("dev1", Q_READ, onCancel = { cancelled.add("read") }) {
            order.add("read")
        }

        queue.onOperationComplete("dev1", Q_WRITE)
        queue.cancelAll("dev1")
        dispatched.single().invoke()

        assertEquals(listOf("write"), order)
        assertEquals(listOf("read"), cancelled)
    }

    @Test
    fun syncCompletionReleasesWithoutAwaitingCallback() {
        val queue = PerDeviceGattQueue()
        val order = mutableListOf<String>()

        queue.submit("dev1", Q_WRITE) {
            order.add("write")
            queue.onOperationComplete("dev1", Q_WRITE)
        }
        queue.submit("dev1", Q_READ) { order.add("read") }

        assertEquals(listOf("write", "read"), order)
    }

    @Test
    fun exceptionInOperationDoesNotDeadlockQueue() {
        val queue = PerDeviceGattQueue()
        val order = mutableListOf<String>()

        queue.submit("dev1", Q_WRITE) {
            order.add("write")
            error("boom")
        }
        queue.submit("dev1", Q_READ) { order.add("read") }

        // runOperation swallows the throwable and releases the queue.
        assertEquals(listOf("write", "read"), order)
    }

    @Test
    fun aWrongKindCompletionIsIgnored() {
        val queue = PerDeviceGattQueue()
        val order = mutableListOf<String>()

        queue.submit("dev1", Q_WRITE) { order.add("write") }
        queue.submit("dev1", Q_READ) { order.add("read") }

        queue.onOperationComplete("dev1", Q_RSSI)
        assertEquals(listOf("write"), order, "spurious rssi completion must not release a write")

        queue.onOperationComplete("dev1", Q_WRITE)
        assertEquals(listOf("write", "read"), order)

        // The queue becomes idle once everything completed.
        queue.onOperationComplete("dev1", Q_READ)
        assertFalse(queue.isBusy("dev1"))
    }

    @Test
    fun operationForNewDeviceRunsAfterIdle() {
        val queue = PerDeviceGattQueue()

        queue.submit("dev1", Q_WRITE) { }
        queue.submit("dev1", Q_WRITE) { }
        queue.onOperationComplete("dev1", Q_WRITE)
        queue.onOperationComplete("dev1", Q_WRITE)
        assertFalse(queue.isBusy("dev1"))

        // A fresh submit after idle starts immediately.
        val order = mutableListOf<String>()
        queue.submit("dev1", Q_WRITE) { order.add("later") }
        assertEquals(listOf("later"), order)
        assertTrue(queue.isBusy("dev1"))
    }
}
