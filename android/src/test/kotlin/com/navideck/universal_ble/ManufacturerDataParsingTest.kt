package com.navideck.universal_ble

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertTrue

internal class ManufacturerDataParsingTest {

    private fun adStructure(type: Int, payload: ByteArray): ByteArray {
        val out = ArrayList<Byte>()
        out.add((payload.size + 1).toByte())
        out.add(type.toByte())
        payload.forEach { out.add(it) }
        return out.toByteArray()
    }

    private fun manufacturerAd(companyId: Int, payload: ByteArray): ByteArray {
        val companyBytes = byteArrayOf(
            (companyId and 0xFF).toByte(),
            ((companyId shr 8) and 0xFF).toByte(),
        )
        return adStructure(0xFF, companyBytes + payload)
    }

    @Test
    fun singleManufacturerStructure_isParsed() {
        val payload = byteArrayOf(0xBC.toByte(), 0x02, 0x10, 0x20)
        val raw = manufacturerAd(0x3390, payload)

        val result = parseManufacturerDataFromRawBytes(raw)

        assertEquals(1, result.size)
        assertEquals(0x3390L, result[0].companyIdentifier)
        assertContentEquals(payload, result[0].data)
    }

    @Test
    fun twoStructuresSameCompanyId_areConcatenatedInOrder() {
        val sensor = byteArrayOf(0xBC.toByte(), 0x02, 0xC5.toByte(), 0xA8.toByte())
        val beacon = byteArrayOf(0x4F, 0x00, 0x00, 0x0C)
        val raw = manufacturerAd(0x3390, sensor) + manufacturerAd(0x3390, beacon)

        val result = parseManufacturerDataFromRawBytes(raw)

        assertEquals(1, result.size)
        assertEquals(0x3390L, result[0].companyIdentifier)
        assertContentEquals(sensor + beacon, result[0].data)
    }

    @Test
    fun twoStructuresDifferentCompanyIds_areKeptSeparate() {
        val firstPayload = byteArrayOf(0xBC.toByte(), 0x02)
        val secondPayload = byteArrayOf(0x4F, 0x00)
        val raw = manufacturerAd(0x3390, firstPayload) + manufacturerAd(0x004C, secondPayload)

        val result = parseManufacturerDataFromRawBytes(raw)

        assertEquals(2, result.size)
        assertEquals(0x3390L, result[0].companyIdentifier)
        assertContentEquals(firstPayload, result[0].data)
        assertEquals(0x004CL, result[1].companyIdentifier)
        assertContentEquals(secondPayload, result[1].data)
    }

    @Test
    fun manufacturerStructureAmongOtherAdTypes_isExtracted() {
        val flags = adStructure(0x01, byteArrayOf(0x06))
        val serviceUuids = adStructure(0x02, byteArrayOf(0xF5.toByte(), 0xFE.toByte()))
        val payload = byteArrayOf(0xBC.toByte(), 0x02, 0x11)
        val raw = flags + serviceUuids + manufacturerAd(0x3390, payload)

        val result = parseManufacturerDataFromRawBytes(raw)

        assertEquals(1, result.size)
        assertEquals(0x3390L, result[0].companyIdentifier)
        assertContentEquals(payload, result[0].data)
    }

    @Test
    fun realWorldFw30DataGrabberPacket_concatenatesBothStructures() {
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

        val result = parseManufacturerDataFromRawBytes(raw)

        assertEquals(1, result.size)
        assertEquals(0x3390L, result[0].companyIdentifier)
        assertContentEquals(sensor + beacon, result[0].data)
        assertEquals(0xBC, result[0].data[0].toInt() and 0xFF)
        assertEquals(0x02, result[0].data[1].toInt() and 0xFF)
    }

    @Test
    fun noManufacturerStructure_returnsEmpty() {
        val flags = adStructure(0x01, byteArrayOf(0x06))
        val raw = flags + adStructure(0x09, "Name".toByteArray())

        assertTrue(parseManufacturerDataFromRawBytes(raw).isEmpty())
    }

    @Test
    fun emptyRecord_returnsEmpty() {
        assertTrue(parseManufacturerDataFromRawBytes(ByteArray(0)).isEmpty())
    }

    @Test
    fun zeroLengthFieldTerminatesParsing() {
        val payload = byteArrayOf(0xBC.toByte(), 0x02)
        val raw = manufacturerAd(0x3390, payload) + byteArrayOf(0x00, 0x00, 0x00)

        val result = parseManufacturerDataFromRawBytes(raw)

        assertEquals(1, result.size)
        assertContentEquals(payload, result[0].data)
    }

    @Test
    fun truncatedFieldLength_isIgnored() {
        val raw = byteArrayOf(0x20, 0xFF.toByte(), 0x90.toByte(), 0x33, 0xBC.toByte())

        assertTrue(parseManufacturerDataFromRawBytes(raw).isEmpty())
    }

    @Test
    fun manufacturerFieldWithoutPayload_isSkipped() {
        val raw = manufacturerAd(0x3390, ByteArray(0))

        val result = parseManufacturerDataFromRawBytes(raw)

        assertEquals(1, result.size)
        assertEquals(0x3390L, result[0].companyIdentifier)
        assertTrue(result[0].data.isEmpty())
    }
}
