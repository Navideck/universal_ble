package com.navideck.universal_ble

import android.bluetooth.BluetoothGatt
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * One GATT client and the connection state the plugin keeps for it.
 *
 * The lifecycle used to live in several address sets (`connectedGatts`,
 * `closingGatts`, `awaitingReconnectGatts`, `autoConnectDevices`), so every
 * transition had to update each of them. It is one field now: reads such as
 * "is the link up", "is this client being torn down" and "may the stack
 * reconnect it" are answered by [state] and [autoConnect].
 */
internal class GattClient(val gatt: BluetoothGatt) {
    enum class State {
        /** connectGatt() returned; no callback has arrived yet. */
        CONNECTING,

        /** STATE_CONNECTED: the platform can deliver operations on this link. */
        CONNECTED,

        /** A link loss left the client open for autoConnect to reconnect it. */
        AWAITING_RECONNECT,

        /** disconnect() or a teardown is closing it; close() has not run yet. */
        CLOSING,

        /** close() has run; the client is no longer tracked. */
        CLOSED,
    }

    private val stateRef = AtomicReference(State.CONNECTING)

    /**
     * Whether the link came up since the previous disconnect. Android reports a
     * failed connection attempt and a peer disconnect the same way, so the
     * disconnect report reads this to tell them apart. [state] cannot answer it:
     * a `disconnect()` has already moved the client to [State.CLOSING], and the
     * `STATE_DISCONNECTED` that follows belongs to a link that was up.
     */
    private val linkCameUp = AtomicBoolean(false)

    /** Whether Android may reconnect this client after a link loss. */
    @Volatile
    var autoConnect: Boolean = false

    val address: String get() = gatt.device.address

    val state: State get() = stateRef.get()

    /** Whether this client's link is up, i.e. operations may reach the platform. */
    val isLinkUp: Boolean get() = state == State.CONNECTED

    fun setState(next: State) {
        if (next == State.CONNECTED) linkCameUp.set(true)
        stateRef.set(next)
    }

    /**
     * Reads and clears whether the link had come up, i.e. whether the disconnect
     * being reported ended a live link rather than a failed attempt. Called once
     * per `STATE_DISCONNECTED`.
     */
    fun takeLinkWasUp(): Boolean = linkCameUp.getAndSet(false)

    /**
     * Moves the client from [expected] to [next], returning false when another
     * thread got there first. Used where two paths race to finish a teardown
     * (STATE_DISCONNECTED and the close fallback timer).
     */
    fun compareAndSetState(expected: State, next: State): Boolean =
        stateRef.compareAndSet(expected, next)

    override fun toString(): String = "GattClient($address, $state)"
}

/**
 * The GATT clients owned by one [UniversalBlePlugin]. This must stay per plugin
 * instance (one per FlutterEngine) rather than process-wide: a `connect()` must
 * not reuse a client whose callbacks are wired to another (possibly destroyed)
 * engine, and detaching one engine must release only its own clients.
 *
 * [active] maps an address to the client its callbacks and API calls currently
 * belong to. [clients] tracks every client the plugin still owes a teardown,
 * including ones that are closing, so a late callback can still be attributed
 * (and ignored) and its close is still driven. A connect() can publish a
 * replacement only after the previous client's link is gone, and that client
 * may still be waiting for its own STATE_DISCONNECTED — the reason the two maps
 * exist. `connect()` tears the client it replaces down, so [clients] does not
 * accumulate replaced entries: everything it holds besides the active client is
 * on its way to [GattClient.State.CLOSED].
 */
internal class GattRegistry {
    private val active = ConcurrentHashMap<String, GattClient>()
    private val clients = ConcurrentHashMap<BluetoothGatt, GattClient>()

    /** The client API calls resolve for [deviceId], if the address has one. */
    fun find(deviceId: String): GattClient? = active[deviceId]

    /** The tracked client for [gatt], including one that is closing. */
    fun find(gatt: BluetoothGatt): GattClient? = clients[gatt]

    fun isKnown(deviceId: String): Boolean = active.containsKey(deviceId)

    fun get(deviceId: String): GattClient =
        find(deviceId) ?: throw createFlutterError(
            UniversalBleErrorCode.DEVICE_NOT_FOUND,
            "Unknown deviceId: $deviceId",
        )

    /**
     * Publishes [gatt] as the address's active client. A client the plugin
     * already tracks for this gatt keeps its state: connectGatt() is given no
     * Handler, so STATE_CONNECTED can arrive before connect() reaches this call,
     * and resetting it here would make a live link look like it is connecting.
     */
    fun put(gatt: BluetoothGatt, autoConnect: Boolean = false): GattClient {
        val client = clients.computeIfAbsent(gatt) { GattClient(it) }
        client.autoConnect = autoConnect
        active[client.address] = client
        return client
    }

    /**
     * Starts closing [client]: it leaves the active slot immediately, so API
     * calls for the address fail with `deviceNotFound`, while [clients] keeps
     * tracking it until close() runs.
     */
    fun beginClose(client: GattClient) {
        // Only unpublish it if it is still the address's client; a connect()
        // may already have published a replacement.
        active.remove(client.address, client)
        client.setState(GattClient.State.CLOSING)
    }

    /**
     * Stops tracking [client] once close() has run, returning false when
     * another path (STATE_DISCONNECTED or the fallback timer) closed it first.
     * The compare-and-set keeps the two from closing the same client twice.
     */
    fun finishClose(client: GattClient): Boolean {
        while (true) {
            val current = client.state
            if (current == GattClient.State.CLOSED) return false
            if (client.compareAndSetState(current, GattClient.State.CLOSED)) {
                active.remove(client.address, client)
                clients.remove(client.gatt)
                return true
            }
        }
    }

    /** The active clients, safe to iterate while releasing them. */
    fun snapshot(): List<GattClient> = active.values.toList()
}
