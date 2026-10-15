package com.navideck.universal_ble

import android.annotation.SuppressLint
import android.bluetooth.le.ScanFilter
import android.os.ParcelUuid
import android.util.Log
import java.util.UUID
import kotlin.experimental.and

private const val TAG = "UniversalBlePlugin"

@SuppressLint("MissingPermission")
class UniversalBleFilterUtil {
    var scanFilter: UniversalScanFilter? = null
    var serviceFilterUUIDS: List<UUID> = emptyList()
    var serviceDataFilterUUIDS: List<UUID> = emptyList()

    fun filterDevice(
        name: String?,
        manufacturerDataList: List<UniversalManufacturerData>,
        serviceUuids: Array<UUID>,
        serviceDataUuids: List<UUID>,
    ): Boolean {
        val filter = scanFilter ?: return true

        val hasNamePrefixFilter = filter.withNamePrefix.isNotEmpty()
        val hasServiceFilter = filter.withServices.isNotEmpty()
        val hasServiceDataFilter = filter.withServiceData.isNotEmpty()
        val hasManufacturerDataFilter = filter.withManufacturerData.isNotEmpty()

        // If there is no filter at all, then allow device
        if (!hasNamePrefixFilter &&
            !hasServiceFilter &&
            !hasServiceDataFilter &&
            !hasManufacturerDataFilter
        ) {
            return true
        }

        // For not, we only have DeviceName filter
        return hasNamePrefixFilter && isNameMatchingFilters(filter, name) ||
                hasServiceFilter && isServicesMatchingFilters(serviceUuids) ||
                hasServiceDataFilter && isServiceDataMatchingFilters(serviceDataUuids) ||
                hasManufacturerDataFilter && isManufacturerDataMatchingFilters(
            filter,
            manufacturerDataList
        )
    }

    private fun isNameMatchingFilters(scanFilter: UniversalScanFilter, name: String?): Boolean {
        val namePrefixFilter = scanFilter.withNamePrefix
        if (namePrefixFilter.isEmpty()) {
            return true
        }
        if (name.isNullOrEmpty()) {
            return false
        }
        return namePrefixFilter.any { name.startsWith(it) }
    }

    private fun isServicesMatchingFilters(
        serviceUuids: Array<UUID>,
    ): Boolean {
        if (serviceFilterUUIDS.isEmpty()) {
            return true
        }
        if (serviceUuids.isEmpty()) {
            return false
        }
        return serviceFilterUUIDS.any {
            serviceUuids.contains(it)
        }
    }

    /// Matches a device by the service UUIDs it carries in its advertising
    /// Service Data (the `0x16`/`0x20`/`0x21` data types). This is a different
    /// set from the advertised service UUID list matched by
    /// [isServicesMatchingFilters]: beacons such as Eddystone (`0xFEAA`) or the
    /// ATC_MiThermometer (`0x181A`) only appear here (#57).
    private fun isServiceDataMatchingFilters(
        serviceDataUuids: List<UUID>,
    ): Boolean {
        if (serviceDataFilterUUIDS.isEmpty()) {
            return true
        }
        if (serviceDataUuids.isEmpty()) {
            return false
        }
        return serviceDataFilterUUIDS.any {
            serviceDataUuids.contains(it)
        }
    }

    private fun isManufacturerDataMatchingFilters(
        scanFilter: UniversalScanFilter,
        manufacturerDataList: List<UniversalManufacturerData>,
    ): Boolean {
        val filters = scanFilter.withManufacturerData
        if (filters.isEmpty()) return true
        if (manufacturerDataList.isEmpty()) return false
        return manufacturerDataList.any { msd ->
            filters.any { filter ->
                msd.companyIdentifier == filter.companyIdentifier &&
                        isDataMatching(filter.payloadPrefix, msd.data, filter.payloadMask)
            }
        }
    }

    private fun isDataMatching(
        filterData: ByteArray?,
        deviceData: ByteArray,
        filterMask: ByteArray?,
    ): Boolean {
        if (filterData == null) return true
        if (filterData.size > deviceData.size) return false

        val mask = filterMask ?: ByteArray(filterData.size) { 0xFF.toByte() }
        if (filterData.size != mask.size) return false

        return filterData.indices.all { i ->
            (filterData[i] and mask[i]) == (deviceData[i] and mask[i])
        }
    }
}

fun UniversalScanFilter.usesCustomFilters(): Boolean {
    // NamePrefix filtering is not supported in native filters. Service Data
    // matching cannot be expressed as a native ScanFilter either: the controller
    // would drop a device that carries the UUID only inside its Service Data
    // before the app is ever notified, so both have to be applied in the scan
    // callback instead. Callers that opt in pay for it in battery (every
    // advertisement reaches the app process before being filtered).
    return withNamePrefix.isNotEmpty() || withServiceData.isNotEmpty()
}

// Convert UniversalScanFilter to ScanFilter
fun UniversalScanFilter.toScanFilters(serviceUuids: List<UUID>): List<ScanFilter> {
    val scanFilters: ArrayList<ScanFilter> = arrayListOf()

    // Add withServices Filter
    for (service in serviceUuids) {
        try {
            service.let {
                scanFilters.add(
                    ScanFilter.Builder().setServiceUuid(ParcelUuid(it)).build()
                )
                Log.e(TAG, "scanFilters: $it")
            }
        } catch (e: Exception) {
            Log.e(TAG, e.toString())
            throw createFlutterError(
                UniversalBleErrorCode.INVALID_SERVICE_UUID,
                "Invalid serviceId: $service",
                e.toString()
            )
        }
    }

    // Add ManufacturerData Filter
    for (manufacturerData in this.withManufacturerData) {
        try {
            manufacturerData.companyIdentifier.let {
                val data: ByteArray = manufacturerData.payloadPrefix ?: ByteArray(0)
                val mask: ByteArray? = manufacturerData.payloadMask
                if (mask == null) {
                    scanFilters.add(
                        ScanFilter.Builder().setManufacturerData(
                            it.toInt(), data
                        ).build()
                    )
                } else {
                    scanFilters.add(
                        ScanFilter.Builder().setManufacturerData(
                            it.toInt(), data, mask
                        ).build()
                    )
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, e.toString())
            throw createFlutterError(
                UniversalBleErrorCode.FAILED,
                "Invalid manufacturerData: ${manufacturerData.companyIdentifier} ${manufacturerData.payloadPrefix} ${manufacturerData.payloadMask}",
                e.toString()
            )
        }
    }

    return scanFilters.toList()
}
