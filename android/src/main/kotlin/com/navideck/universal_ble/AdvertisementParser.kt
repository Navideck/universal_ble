package com.navideck.universal_ble

object AdvertisementParser {
    private const val DATA_TYPE_SERVICE_DATA: Int = 0x16
    private const val DATA_TYPE_MANUFACTURER_SPECIFIC_DATA: Int = 0xFF
    private const val LENGTH_BYTE_SIZE: Byte = 0x01
    private const val TYPE_BYTE_SIZE: Byte = 0x01
    private const val UUID_HEADER_LENGTH = 2

    @JvmStatic
    fun parseAdvertisementBytes(data: ByteArray): Map<Int, ByteArray> {
        val dataMap = mutableMapOf<Int, ByteArray>()
        var index = 0

        while (index < data.size) {
            val sectionLength = parseSection(index, data, dataMap) ?: break
            index += sectionLength
        }

        return dataMap
    }

    private fun parseSection(
        startIndex: Int,
        advertisingData: ByteArray,
        dataMap: MutableMap<Int, ByteArray>,
    ): Int? {
        val sectionLength = convertSignedByteToUnsigned(advertisingData[startIndex])
        if (sectionLength <= 1) return null

        val dataType = convertSignedByteToUnsigned(advertisingData[startIndex + LENGTH_BYTE_SIZE])
        val dataStart = startIndex + LENGTH_BYTE_SIZE + TYPE_BYTE_SIZE
        val dataEnd = dataStart + sectionLength - LENGTH_BYTE_SIZE

        val newData = advertisingData.copyOfRange(dataStart, dataEnd)

        val existingData = dataMap[dataType]
        val mergedData = if (existingData != null) {
            val uuidOffset = if (isUuidPrefixEqual(existingData, newData)) UUID_HEADER_LENGTH else 0
            existingData + newData.copyOfRange(uuidOffset, newData.size)
        } else {
            newData
        }

        dataMap[dataType] = mergedData
        return sectionLength + TYPE_BYTE_SIZE
    }

    private fun isUuidPrefixEqual(presentData: ByteArray, sectionData: ByteArray): Boolean {
        return presentData.size >= 2 && sectionData.size >= 2 &&
                presentData[0] == sectionData[0] &&
                presentData[1] == sectionData[1]
    }

    @JvmStatic
    fun getManufacturerSpecificData(advList: Map<Int, ByteArray>): ByteArray {
        val manufacturerData = advList[DATA_TYPE_MANUFACTURER_SPECIFIC_DATA]
            ?: return ByteArray(0)

        return byteArrayToUnsignedByteArray(manufacturerData)
    }

    @JvmStatic
    fun getServiceData(advList: Map<Int, ByteArray>): ByteArray {
        return advList[DATA_TYPE_SERVICE_DATA]
            ?.takeIf { it.size > UUID_HEADER_LENGTH }
            ?.let { data ->
                val serviceDataWithoutUuid = data.copyOfRange(UUID_HEADER_LENGTH, data.size)
                byteArrayToUnsignedByteArray(serviceDataWithoutUuid)
            } ?: ByteArray(0)
    }

    private fun convertSignedByteToUnsigned(value: Byte): Int {
        return value.toInt() and 0xFF
    }

    private fun byteArrayToUnsignedByteArray(byteArray: ByteArray): ByteArray {
        if (byteArray.isEmpty()) {
            return byteArray
        }

        val result = ByteArray(byteArray.size)
        for (i in byteArray.indices) {
            // bitwise and with 0xFF converts from signed to unsigned int (byte)
            result[i] = (byteArray[i].toInt() and 0xFF).toByte()
        }
        return result
    }
}
