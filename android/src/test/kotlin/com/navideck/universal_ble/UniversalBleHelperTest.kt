package com.navideck.universal_ble

import android.bluetooth.le.ScanRecord
import android.bluetooth.le.ScanResult
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.mockito.Mockito.mock
import org.mockito.Mockito.`when`

internal class UniversalBleHelperTest {

    private fun scanResultWithRawBytes(raw: ByteArray?): ScanResult {
        val scanResult = mock(ScanResult::class.java)
        val scanRecord = mock(ScanRecord::class.java)
        `when`(scanResult.scanRecord).thenReturn(scanRecord)
        `when`(scanRecord.bytes).thenReturn(raw)
        return scanResult
    }

    @Test
    fun mergesDuplicateCompanyId() {
        val raw = byteArrayOf(
            5, 0xFF.toByte(), 0x4C, 0x00, 0x01, 0x02,
            5, 0xFF.toByte(), 0x4C, 0x00, 0x03, 0x04,
            0, 0, 0,
        )

        val dataList = scanResultWithRawBytes(raw).manufacturerDataList

        assertEquals(1, dataList.size)
        assertEquals(0x004CL, dataList[0].companyIdentifier)
        assertContentEquals(byteArrayOf(0x01, 0x02, 0x03, 0x04), dataList[0].data)
    }

    @Test
    fun parsesSingleManufacturerData() {
        val raw = byteArrayOf(5, 0xFF.toByte(), 0x90.toByte(), 0x33, 0xBC.toByte(), 0x02)

        val dataList = scanResultWithRawBytes(raw).manufacturerDataList

        assertEquals(1, dataList.size)
        assertEquals(0x3390L, dataList[0].companyIdentifier)
        assertContentEquals(byteArrayOf(0xBC.toByte(), 0x02), dataList[0].data)
    }

    @Test
    fun keepsDifferentCompanyIdsSeparate() {
        val raw = byteArrayOf(
            4, 0xFF.toByte(), 0x90.toByte(), 0x33, 0xBC.toByte(),
            4, 0xFF.toByte(), 0x4C, 0x00, 0x4F,
        )

        val dataList = scanResultWithRawBytes(raw).manufacturerDataList

        assertEquals(2, dataList.size)
        assertEquals(0x3390L, dataList[0].companyIdentifier)
        assertContentEquals(byteArrayOf(0xBC.toByte()), dataList[0].data)
        assertEquals(0x004CL, dataList[1].companyIdentifier)
        assertContentEquals(byteArrayOf(0x4F), dataList[1].data)
    }

    @Test
    fun realWorldFw30DataGrabberPacket() {
        val sensor = byteArrayOf(
            0xBC.toByte(), 0x02, 0xC5.toByte(), 0xA8.toByte(), 0x26, 0x6A, 0x8F.toByte(),
            0x01, 0x34, 0x03, 0x0D, 0xDB.toByte(), 0x4F, 0xF5.toByte(), 0x00, 0x00,
            0x26, 0xB6.toByte(), 0x26, 0x6A,
        )
        val beacon = byteArrayOf(
            0x4F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0C, 0x00, 0x00,
            0x00, 0x00, 0x38, 0x38, 0x33, 0x32, 0x35, 0x33, 0x33, 0x41, 0x41, 0x41,
            0x32, 0x37, 0x00,
        )
        val raw = manufacturerAd(0x3390, sensor) + manufacturerAd(0x3390, beacon)

        val dataList = scanResultWithRawBytes(raw).manufacturerDataList

        assertEquals(1, dataList.size)
        assertEquals(0x3390L, dataList[0].companyIdentifier)
        assertContentEquals(sensor + beacon, dataList[0].data)
        assertEquals(0xBC, dataList[0].data[0].toInt() and 0xFF)
        assertEquals(0x02, dataList[0].data[1].toInt() and 0xFF)
    }

    @Test
    fun truncatedLengthDoesNotThrow() {
        val raw = byteArrayOf(0x20, 0xFF.toByte(), 0x90.toByte(), 0x33, 0xBC.toByte())

        assertTrue(scanResultWithRawBytes(raw).manufacturerDataList.isEmpty())
    }

    @Test
    fun zeroLengthFieldTerminatesParsing() {
        val raw = byteArrayOf(4, 0xFF.toByte(), 0x90.toByte(), 0x33, 0xBC.toByte(), 0x00, 0x00)

        val dataList = scanResultWithRawBytes(raw).manufacturerDataList

        assertEquals(1, dataList.size)
        assertContentEquals(byteArrayOf(0xBC.toByte()), dataList[0].data)
    }

    @Test
    fun noManufacturerStructureReturnsEmpty() {
        val raw = byteArrayOf(2, 0x01, 0x06)

        assertTrue(scanResultWithRawBytes(raw).manufacturerDataList.isEmpty())
    }

    @Test
    fun nullScanRecordReturnsEmpty() {
        val scanResult = mock(ScanResult::class.java)
        `when`(scanResult.scanRecord).thenReturn(null)

        assertTrue(scanResult.manufacturerDataList.isEmpty())
    }

    private fun manufacturerAd(companyId: Int, payload: ByteArray): ByteArray {
        val companyBytes = byteArrayOf(
            (companyId and 0xFF).toByte(),
            ((companyId shr 8) and 0xFF).toByte(),
        )
        val body = companyBytes + payload
        return byteArrayOf((body.size + 1).toByte(), 0xFF.toByte()) + body
    }
}
