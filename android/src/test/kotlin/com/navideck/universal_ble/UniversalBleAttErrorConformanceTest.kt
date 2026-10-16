package com.navideck.universal_ble

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Drives [gattStatusToUniversalBleErrorCode] from the shared conformance fixture
 * (`test/fixtures/att_error_cases.tsv`, exposed as a test resource by
 * `android/build.gradle`), so the ATT error mapping stays identical to the Dart
 * and Windows implementations.
 */
internal class UniversalBleAttErrorConformanceTest {

    @Test
    fun matchesTheSharedConformanceFixture() {
        val stream = javaClass.getResourceAsStream("/att_error_cases.tsv")
            ?: error("Fixture not found on the test classpath")
        val rows = stream.bufferedReader().readLines()
            .filter { it.isNotBlank() && !it.startsWith("#") }
            .map { it.split("|") }
            .drop(1) // header row
        assertTrue(rows.isNotEmpty(), "Fixture should contain cases")

        for (columns in rows) {
            assertEquals(3, columns.size, "Bad fixture row: ${columns.joinToString("|")}")
            val attCode = columns[0].removePrefix("0x").toInt(16)
            val expected = columns[1].toInt()
            assertEquals(
                expected,
                gattStatusToUniversalBleErrorCode(attCode).raw,
                "ATT ${columns[0]} (${columns[2]})",
            )
        }
    }
}
