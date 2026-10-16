package com.navideck.universal_ble

import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Drives [UniversalBleFilterUtil] from the shared conformance fixture
 * (`test/fixtures/scan_filter_cases.tsv`, exposed as a test resource by
 * `android/build.gradle`), so its semantics stay identical to the Dart, Swift and
 * C++ implementations.
 *
 * The fixture is language-neutral: its UUIDs are written the way the platforms
 * receive them (full 128-bit, lowercase), since short/`0x` forms are normalised in
 * the Dart layer before they reach the channel.
 */
internal class UniversalBleFilterConformanceTest {

    private class Row(val id: String, val columns: List<String>, val expected: Boolean)

    private fun loadRows(): List<Row> {
        val stream = javaClass.getResourceAsStream("/scan_filter_cases.tsv")
            ?: error("Fixture not found on the test classpath")
        val rows = stream.bufferedReader().readLines()
            .filter { it.isNotBlank() && !it.startsWith("#") }
            .map { it.split("|") }
            .drop(1) // header row
        return rows.map { columns ->
            assertEquals(10, columns.size, "Bad fixture row: ${columns.joinToString("|")}")
            Row(columns[0], columns, columns[9] == "1")
        }
    }

    private fun values(row: Row, index: Int): List<String> =
        row.columns[index].split(";").filter { it.isNotEmpty() }

    private fun companyIds(row: Row, index: Int): List<Long> =
        values(row, index).map { it.toLong() }

    private fun filterOf(row: Row): UniversalScanFilter = UniversalScanFilter(
        withServices = values(row, 1),
        withNamePrefix = values(row, 3),
        withManufacturerData = companyIds(row, 4).map {
            ManufacturerDataFilter(companyIdentifier = it, payloadPrefix = null, payloadMask = null)
        },
        withServiceData = values(row, 2),
    )

    @Test
    fun matchesTheSharedConformanceFixture() {
        val rows = loadRows()
        assertTrue(rows.isNotEmpty(), "Fixture should contain cases")

        for (row in rows) {
            val util = UniversalBleFilterUtil().apply { configure(filterOf(row)) }
            val matched = util.filterDevice(
                name = row.columns[5].ifEmpty { null },
                manufacturerDataList = companyIds(row, 8).map {
                    UniversalManufacturerData(companyIdentifier = it, data = ByteArray(0))
                },
                serviceUuids = values(row, 6).map { UUID.fromString(it) }.toTypedArray(),
                serviceDataUuids = values(row, 7).map { UUID.fromString(it) },
            )

            assertEquals(row.expected, matched, "Fixture case '${row.id}'")
        }
    }
}
