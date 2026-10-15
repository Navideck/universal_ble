package com.navideck.universal_ble

import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

internal class UniversalBleFilterUtilTest {

    private val serviceDataUuid = UUID.fromString("0000181a-0000-1000-8000-00805f9b34fb")
    private val otherUuid = UUID.fromString("00002a6e-0000-1000-8000-00805f9b34fb")

    private fun scanFilter(
        withServices: List<String> = emptyList(),
        withNamePrefix: List<String> = emptyList(),
        withServiceData: List<String> = emptyList(),
    ) = UniversalScanFilter(withServices, withNamePrefix, emptyList(), withServiceData)

    private fun filterUtil(filter: UniversalScanFilter): UniversalBleFilterUtil {
        return UniversalBleFilterUtil().apply { configure(filter) }
    }

    @Test
    fun serviceDataMatchingRequiresTheFilterUuid() {
        val util = filterUtil(scanFilter(withServiceData = listOf(serviceDataUuid.toString())))

        assertTrue(util.filterDevice("ATC", emptyList(), emptyArray(), listOf(serviceDataUuid)))
        assertFalse(util.filterDevice("ATC", emptyList(), emptyArray(), listOf(otherUuid)))
        assertFalse(util.filterDevice("ATC", emptyList(), emptyArray(), emptyList()))
    }

    @Test
    fun acceptsBeaconWithoutAdvertisedServices() {
        // Regression for #57: a device that only carries the UUID in its Service
        // Data has an empty advertised service list, so plain service filters
        // could never discover it. (The Dart layer normalises UUIDs to the full
        // 128-bit form before they reach the channel, so short forms are not
        // parsed here.)
        val util = filterUtil(scanFilter(withServiceData = listOf(serviceDataUuid.toString())))

        assertTrue(
            util.filterDevice("ATC_DD7A81", emptyList(), emptyArray(), listOf(serviceDataUuid))
        )
    }

    @Test
    fun serviceDataFilterIgnoresAdvertisedServiceList() {
        val util = filterUtil(scanFilter(withServiceData = listOf(serviceDataUuid.toString())))

        // The UUID is advertised as a service here, which is a different
        // advertising data type: it must not satisfy withServiceData.
        assertFalse(util.filterDevice("ATC", emptyList(), arrayOf(serviceDataUuid), emptyList()))
    }

    @Test
    fun advertisedServiceFilterIgnoresServiceData() {
        val util = filterUtil(scanFilter(withServices = listOf(serviceDataUuid.toString())))

        assertTrue(util.filterDevice("ATC", emptyList(), arrayOf(serviceDataUuid), emptyList()))
        assertFalse(util.filterDevice("ATC", emptyList(), emptyArray(), listOf(serviceDataUuid)))
    }

    @Test
    fun filtersAreInOrRelation() {
        val util = filterUtil(
            scanFilter(
                withServices = listOf(otherUuid.toString()),
                withServiceData = listOf(serviceDataUuid.toString()),
            )
        )

        assertTrue(util.filterDevice("a", emptyList(), arrayOf(otherUuid), emptyList()))
        assertTrue(util.filterDevice("a", emptyList(), emptyArray(), listOf(serviceDataUuid)))
        assertFalse(util.filterDevice("a", emptyList(), emptyArray(), emptyList()))
    }

    @Test
    fun noFiltersAcceptEverything() {
        val util = UniversalBleFilterUtil()

        assertTrue(util.filterDevice("a", emptyList(), emptyArray(), emptyList()))
        assertTrue(util.filterDevice("a", emptyList(), arrayOf(otherUuid), listOf(serviceDataUuid)))
    }

    @Test
    fun usesCustomFiltersOnlyWhenNativeFilterCannotExpressIt() {
        // Advertised services are still handled by the controller-level ScanFilter.
        assertFalse(scanFilter(withServices = listOf("181a")).usesCustomFilters())
        // Name prefix and Service Data cannot be, so they are applied in the callback.
        assertTrue(scanFilter(withServiceData = listOf("181a")).usesCustomFilters())
        assertTrue(scanFilter(withNamePrefix = listOf("ATC")).usesCustomFilters())
    }
}
