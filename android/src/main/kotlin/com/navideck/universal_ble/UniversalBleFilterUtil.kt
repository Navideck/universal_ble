package com.navideck.universal_ble

import android.annotation.SuppressLint
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.os.ParcelUuid
import android.util.Log
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.UUID
import kotlin.experimental.and

private const val TAG = "UniversalBlePlugin"

@SuppressLint("MissingPermission")
class UniversalBleFilterUtil {
    var scanFilter: UniversalScanFilter? = null
    var serviceFilterUUIDS: List<UUID> = emptyList()

    fun filterDevice(
        name: String?,
        manufacturerData: ByteArray?,
        serviceUuids: Array<UUID>,
    ): Boolean {
        val filter = scanFilter ?: return true

        val hasNamePrefixFilter = filter.withNamePrefix.isNotEmpty()
        val hasServiceFilter = filter.withServices.isNotEmpty()
        val hasManufacturerDataFilter = filter.withManufacturerData.isNotEmpty()

        // If there is no filter at all, then allow device
        if (!hasNamePrefixFilter &&
            !hasServiceFilter &&
            !hasManufacturerDataFilter
        ) {
            return true
        }

        // For not, we only have DeviceName filter
        return hasNamePrefixFilter && isNameMatchingFilters(filter, name) ||
                hasServiceFilter && isServicesMatchingFilters(serviceUuids) ||
                hasManufacturerDataFilter && isManufacturerDataMatchingFilters(
            filter,
            manufacturerData
        )
    }

    private fun isNameMatchingFilters(scanFilter: UniversalScanFilter, name: String?): Boolean {
        val namePrefixFilter = scanFilter.withNamePrefix.filterNotNull()
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

    private fun isManufacturerDataMatchingFilters(
        scanFilter: UniversalScanFilter,
        msd: ByteArray?,
    ): Boolean {
        val filters = scanFilter.withManufacturerData.filterNotNull()
        if (filters.isEmpty()) {
            return true
        }

        msd?.takeIf { it.isNotEmpty() } ?: return false

        for (filter in filters) {
            val companyIdentifier = filter.companyIdentifier ?: continue

            val manufacturerId = ByteBuffer.wrap(msd.sliceArray(0..1))
                .order(ByteOrder.LITTLE_ENDIAN).short.toInt() and 0xFFFF

            val manufacturerData = msd.sliceArray(2 until msd.size)

            if (manufacturerId == companyIdentifier.toInt() &&
                findData(filter.data, manufacturerData, filter.mask)
            ) {
                return true
            }
        }
        return false
    }

    private fun findData(find: ByteArray?, data: ByteArray, mask: ByteArray?): Boolean {
        if (find != null) {
            val maskToUse = mask ?: ByteArray(find.size) { 0xFF.toByte() }
            if (find.size != maskToUse.size) {
                return false
            }
            for (i in find.indices) {
                if ((find[i] and maskToUse[i]) != (data[i] and maskToUse[i])) {
                    return false
                }
            }
        }
        return true
    }

}

fun UniversalScanFilter.hasCustomFilter(): Boolean {
    // Only NamePrefix Filtering is not allowed in native filters
    return withNamePrefix.isNotEmpty()
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
            throw FlutterError(
                "illegalIllegalArgument",
                "Invalid serviceId: $service",
                e.toString()
            )
        }
    }

    // Add ManufacturerData Filter
    for (manufacturerData in this.withManufacturerData) {
        try {
            manufacturerData?.companyIdentifier?.let {
                val data: ByteArray = manufacturerData.data ?: ByteArray(0)
                val mask: ByteArray? = manufacturerData.mask
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
            throw FlutterError(
                "illegalIllegalArgument",
                "Invalid manufacturerData: ${manufacturerData?.companyIdentifier} ${manufacturerData?.data} ${manufacturerData?.mask}",
                e.toString()
            )
        }
    }

    return scanFilters.toList()
}
