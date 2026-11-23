package com.navideck.universal_ble

import android.bluetooth.BluetoothGatt

/**
 * A request awaiting a platform callback.
 *
 * Every operation the plugin tracks is one of these, so registering it,
 * matching it to its callback, sweeping it on a disconnect and failing it can
 * be expressed once instead of per operation kind.
 */
internal interface PendingOperation {
    val gatt: BluetoothGatt
    val deviceId: String

    /**
     * Fails this operation with [error]. Called by [PendingOperations] on the
     * main thread, where platform-channel replies must be sent.
     */
    fun fail(error: FlutterError)
}

/**
 * The pending requests of one kind (reads, writes, service discovery, ...).
 *
 * All access is under this object's monitor, which is also the lock the
 * submission paths take: a request is either registered in time for a
 * disconnect sweep to fail it, or refused because its link is gone (#394).
 * Completion is delivered through [post] because platform-channel replies must
 * be sent from the main thread, while callbacks arrive on binder threads.
 */
internal class PendingOperations<T : PendingOperation>(
    /** How a completion reaches the main thread. */
    private val post: (() -> Unit) -> Unit,
    /** Used in the delivery-failure log, e.g. "Write". */
    private val label: String,
) {
    private val pending = mutableListOf<T>()

    /** Adds [future] under the lock. */
    fun add(future: T) {
        synchronized(this) { pending.add(future) }
    }

    /**
     * Adds [future] only if [isLinkUp] says its client still has a live link.
     * Returns false when the caller must fail its call instead of submitting
     * the operation.
     */
    fun addIfLinkedUp(
        gatt: BluetoothGatt,
        future: T,
        isLinkUp: (BluetoothGatt) -> Boolean,
    ): Boolean = synchronized(this) {
        if (!isLinkUp(gatt)) {
            false
        } else {
            pending.add(future)
            true
        }
    }

    /** Removes [future] while it is still registered. */
    fun remove(future: T): Boolean = synchronized(this) { pending.remove(future) }

    fun isEmpty(): Boolean = synchronized(this) { pending.isEmpty() }

    fun any(predicate: (T) -> Boolean): Boolean =
        synchronized(this) { pending.any(predicate) }

    val size: Int get() = synchronized(this) { pending.size }

    /**
     * Removes and returns the oldest operation matching [predicate]. A callback
     * belongs to the oldest request of its kind: completing every match would
     * acknowledge operations still in flight.
     */
    fun takeOldest(predicate: (T) -> Boolean): T? = synchronized(this) {
        val match = pending.firstOrNull(predicate)
        match?.let { pending.remove(it) }
        match
    }

    /**
     * Removes and returns every operation matching [predicate], read under the
     * lock. Callers must evaluate the predicate against current state: the
     * registry can change between the sweep of one collection and the next.
     */
    fun drainMatching(predicate: (T) -> Boolean): List<T> = synchronized(this) {
        val matches = pending.filter(predicate)
        pending.removeAll(matches)
        matches
    }

    /** Removes and fails every operation matching [predicate]. */
    fun failMatching(error: FlutterError, predicate: (T) -> Boolean) {
        for (future in drainMatching(predicate)) {
            post {
                try {
                    future.fail(error)
                } catch (e: Exception) {
                    UniversalBleLogger.logError("$label completion delivery failed: $e")
                }
            }
        }
    }

    /** Runs [action] under this collection's lock. */
    fun <R> withLock(action: () -> R): R = synchronized(this, action)
}
