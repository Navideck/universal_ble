// Autogenerated from Pigeon (v18.0.1), do not edit directly.
// See also: https://pub.dev/packages/pigeon
@file:Suppress("UNCHECKED_CAST", "ArrayInDataClass")

package com.navideck.universal_ble

import android.util.Log
import io.flutter.plugin.common.BasicMessageChannel
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MessageCodec
import io.flutter.plugin.common.StandardMessageCodec
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer

private fun wrapResult(result: Any?): List<Any?> {
  return listOf(result)
}

private fun wrapError(exception: Throwable): List<Any?> {
  return if (exception is FlutterError) {
    listOf(
      exception.code,
      exception.message,
      exception.details
    )
  } else {
    listOf(
      exception.javaClass.simpleName,
      exception.toString(),
      "Cause: " + exception.cause + ", Stacktrace: " + Log.getStackTraceString(exception)
    )
  }
}

private fun createConnectionError(channelName: String): FlutterError {
  return FlutterError("channel-error",  "Unable to establish connection on channel: '$channelName'.", "")}

/**
 * Error class for passing custom error details to Flutter via a thrown PlatformException.
 * @property code The error code.
 * @property message The error message.
 * @property details The error details. Must be a datatype supported by the api codec.
 */
class FlutterError (
  val code: String,
  override val message: String? = null,
  val details: Any? = null
) : Throwable()

/** Generated class from Pigeon that represents data sent in messages. */
data class UniversalBleScanResult (
  val deviceId: String,
  val name: String? = null,
  val isPaired: Boolean? = null,
  val rssi: Long? = null,
  val manufacturerData: ByteArray? = null,
  val manufacturerDataHead: ByteArray? = null,
  val services: List<String?>? = null

) {
  companion object {
    @Suppress("LocalVariableName")
    fun fromList(__pigeon_list: List<Any?>): UniversalBleScanResult {
      val deviceId = __pigeon_list[0] as String
      val name = __pigeon_list[1] as String?
      val isPaired = __pigeon_list[2] as Boolean?
      val rssi = __pigeon_list[3].let { num -> if (num is Int) num.toLong() else num as Long? }
      val manufacturerData = __pigeon_list[4] as ByteArray?
      val manufacturerDataHead = __pigeon_list[5] as ByteArray?
      val services = __pigeon_list[6] as List<String?>?
      return UniversalBleScanResult(deviceId, name, isPaired, rssi, manufacturerData, manufacturerDataHead, services)
    }
  }
  fun toList(): List<Any?> {
    return listOf<Any?>(
      deviceId,
      name,
      isPaired,
      rssi,
      manufacturerData,
      manufacturerDataHead,
      services,
    )
  }
}

/** Generated class from Pigeon that represents data sent in messages. */
data class UniversalBleService (
  val uuid: String,
  val characteristics: List<UniversalBleCharacteristic?>? = null

) {
  companion object {
    @Suppress("LocalVariableName")
    fun fromList(__pigeon_list: List<Any?>): UniversalBleService {
      val uuid = __pigeon_list[0] as String
      val characteristics = __pigeon_list[1] as List<UniversalBleCharacteristic?>?
      return UniversalBleService(uuid, characteristics)
    }
  }
  fun toList(): List<Any?> {
    return listOf<Any?>(
      uuid,
      characteristics,
    )
  }
}

/** Generated class from Pigeon that represents data sent in messages. */
data class UniversalBleCharacteristic (
  val uuid: String,
  val properties: List<Long?>

) {
  companion object {
    @Suppress("LocalVariableName")
    fun fromList(__pigeon_list: List<Any?>): UniversalBleCharacteristic {
      val uuid = __pigeon_list[0] as String
      val properties = __pigeon_list[1] as List<Long?>
      return UniversalBleCharacteristic(uuid, properties)
    }
  }
  fun toList(): List<Any?> {
    return listOf<Any?>(
      uuid,
      properties,
    )
  }
}

/**
 * Scan Filters
 *
 * Generated class from Pigeon that represents data sent in messages.
 */
data class UniversalScanFilter (
  val withServices: List<String?>,
  val withManufacturerData: List<UniversalManufacturerDataFilter?>

) {
  companion object {
    @Suppress("LocalVariableName")
    fun fromList(__pigeon_list: List<Any?>): UniversalScanFilter {
      val withServices = __pigeon_list[0] as List<String?>
      val withManufacturerData = __pigeon_list[1] as List<UniversalManufacturerDataFilter?>
      return UniversalScanFilter(withServices, withManufacturerData)
    }
  }
  fun toList(): List<Any?> {
    return listOf<Any?>(
      withServices,
      withManufacturerData,
    )
  }
}

/** Generated class from Pigeon that represents data sent in messages. */
data class UniversalManufacturerDataFilter (
  val companyIdentifier: Long? = null,
  val data: ByteArray? = null,
  val mask: ByteArray? = null

) {
  companion object {
    @Suppress("LocalVariableName")
    fun fromList(__pigeon_list: List<Any?>): UniversalManufacturerDataFilter {
      val companyIdentifier = __pigeon_list[0].let { num -> if (num is Int) num.toLong() else num as Long? }
      val data = __pigeon_list[1] as ByteArray?
      val mask = __pigeon_list[2] as ByteArray?
      return UniversalManufacturerDataFilter(companyIdentifier, data, mask)
    }
  }
  fun toList(): List<Any?> {
    return listOf<Any?>(
      companyIdentifier,
      data,
      mask,
    )
  }
}

private object UniversalBlePlatformChannelCodec : StandardMessageCodec() {
  override fun readValueOfType(type: Byte, buffer: ByteBuffer): Any? {
    return when (type) {
      128.toByte() -> {
        return (readValue(buffer) as? List<Any?>)?.let {
          UniversalBleCharacteristic.fromList(it)
        }
      }
      129.toByte() -> {
        return (readValue(buffer) as? List<Any?>)?.let {
          UniversalBleScanResult.fromList(it)
        }
      }
      130.toByte() -> {
        return (readValue(buffer) as? List<Any?>)?.let {
          UniversalBleService.fromList(it)
        }
      }
      131.toByte() -> {
        return (readValue(buffer) as? List<Any?>)?.let {
          UniversalManufacturerDataFilter.fromList(it)
        }
      }
      132.toByte() -> {
        return (readValue(buffer) as? List<Any?>)?.let {
          UniversalScanFilter.fromList(it)
        }
      }
      else -> super.readValueOfType(type, buffer)
    }
  }
  override fun writeValue(stream: ByteArrayOutputStream, value: Any?)   {
    when (value) {
      is UniversalBleCharacteristic -> {
        stream.write(128)
        writeValue(stream, value.toList())
      }
      is UniversalBleScanResult -> {
        stream.write(129)
        writeValue(stream, value.toList())
      }
      is UniversalBleService -> {
        stream.write(130)
        writeValue(stream, value.toList())
      }
      is UniversalManufacturerDataFilter -> {
        stream.write(131)
        writeValue(stream, value.toList())
      }
      is UniversalScanFilter -> {
        stream.write(132)
        writeValue(stream, value.toList())
      }
      else -> super.writeValue(stream, value)
    }
  }
}

/**
 * Flutter -> Native
 *
 * Generated interface from Pigeon that represents a handler of messages from Flutter.
 */
interface UniversalBlePlatformChannel {
  fun getBluetoothAvailabilityState(callback: (Result<Long>) -> Unit)
  fun enableBluetooth(callback: (Result<Boolean>) -> Unit)
  fun startScan(filter: UniversalScanFilter?)
  fun stopScan()
  fun connect(deviceId: String)
  fun disconnect(deviceId: String)
  fun setNotifiable(deviceId: String, service: String, characteristic: String, bleInputProperty: Long, callback: (Result<Unit>) -> Unit)
  fun discoverServices(deviceId: String, callback: (Result<List<UniversalBleService>>) -> Unit)
  fun readValue(deviceId: String, service: String, characteristic: String, callback: (Result<ByteArray>) -> Unit)
  fun requestMtu(deviceId: String, expectedMtu: Long, callback: (Result<Long>) -> Unit)
  fun writeValue(deviceId: String, service: String, characteristic: String, value: ByteArray, bleOutputProperty: Long, callback: (Result<Unit>) -> Unit)
  fun isPaired(deviceId: String, callback: (Result<Boolean>) -> Unit)
  fun pair(deviceId: String)
  fun unPair(deviceId: String)
  fun getConnectedDevices(withServices: List<String>, callback: (Result<List<UniversalBleScanResult>>) -> Unit)

  companion object {
    /** The codec used by UniversalBlePlatformChannel. */
    val codec: MessageCodec<Any?> by lazy {
      UniversalBlePlatformChannelCodec
    }
    /** Sets up an instance of `UniversalBlePlatformChannel` to handle messages through the `binaryMessenger`. */
    fun setUp(binaryMessenger: BinaryMessenger, api: UniversalBlePlatformChannel?, messageChannelSuffix: String = "") {
      val separatedMessageChannelSuffix = if (messageChannelSuffix.isNotEmpty()) ".$messageChannelSuffix" else ""
      run {
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.getBluetoothAvailabilityState$separatedMessageChannelSuffix", codec)
        if (api != null) {
          channel.setMessageHandler { _, reply ->
            api.getBluetoothAvailabilityState() { result: Result<Long> ->
              val error = result.exceptionOrNull()
              if (error != null) {
                reply.reply(wrapError(error))
              } else {
                val data = result.getOrNull()
                reply.reply(wrapResult(data))
              }
            }
          }
        } else {
          channel.setMessageHandler(null)
        }
      }
      run {
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.enableBluetooth$separatedMessageChannelSuffix", codec)
        if (api != null) {
          channel.setMessageHandler { _, reply ->
            api.enableBluetooth() { result: Result<Boolean> ->
              val error = result.exceptionOrNull()
              if (error != null) {
                reply.reply(wrapError(error))
              } else {
                val data = result.getOrNull()
                reply.reply(wrapResult(data))
              }
            }
          }
        } else {
          channel.setMessageHandler(null)
        }
      }
      run {
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.startScan$separatedMessageChannelSuffix", codec)
        if (api != null) {
          channel.setMessageHandler { message, reply ->
            val args = message as List<Any?>
            val filterArg = args[0] as UniversalScanFilter?
            val wrapped: List<Any?> = try {
              api.startScan(filterArg)
              listOf<Any?>(null)
            } catch (exception: Throwable) {
              wrapError(exception)
            }
            reply.reply(wrapped)
          }
        } else {
          channel.setMessageHandler(null)
        }
      }
      run {
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.stopScan$separatedMessageChannelSuffix", codec)
        if (api != null) {
          channel.setMessageHandler { _, reply ->
            val wrapped: List<Any?> = try {
              api.stopScan()
              listOf<Any?>(null)
            } catch (exception: Throwable) {
              wrapError(exception)
            }
            reply.reply(wrapped)
          }
        } else {
          channel.setMessageHandler(null)
        }
      }
      run {
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.connect$separatedMessageChannelSuffix", codec)
        if (api != null) {
          channel.setMessageHandler { message, reply ->
            val args = message as List<Any?>
            val deviceIdArg = args[0] as String
            val wrapped: List<Any?> = try {
              api.connect(deviceIdArg)
              listOf<Any?>(null)
            } catch (exception: Throwable) {
              wrapError(exception)
            }
            reply.reply(wrapped)
          }
        } else {
          channel.setMessageHandler(null)
        }
      }
      run {
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.disconnect$separatedMessageChannelSuffix", codec)
        if (api != null) {
          channel.setMessageHandler { message, reply ->
            val args = message as List<Any?>
            val deviceIdArg = args[0] as String
            val wrapped: List<Any?> = try {
              api.disconnect(deviceIdArg)
              listOf<Any?>(null)
            } catch (exception: Throwable) {
              wrapError(exception)
            }
            reply.reply(wrapped)
          }
        } else {
          channel.setMessageHandler(null)
        }
      }
      run {
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.setNotifiable$separatedMessageChannelSuffix", codec)
        if (api != null) {
          channel.setMessageHandler { message, reply ->
            val args = message as List<Any?>
            val deviceIdArg = args[0] as String
            val serviceArg = args[1] as String
            val characteristicArg = args[2] as String
            val bleInputPropertyArg = args[3].let { num -> if (num is Int) num.toLong() else num as Long }
            api.setNotifiable(deviceIdArg, serviceArg, characteristicArg, bleInputPropertyArg) { result: Result<Unit> ->
              val error = result.exceptionOrNull()
              if (error != null) {
                reply.reply(wrapError(error))
              } else {
                reply.reply(wrapResult(null))
              }
            }
          }
        } else {
          channel.setMessageHandler(null)
        }
      }
      run {
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.discoverServices$separatedMessageChannelSuffix", codec)
        if (api != null) {
          channel.setMessageHandler { message, reply ->
            val args = message as List<Any?>
            val deviceIdArg = args[0] as String
            api.discoverServices(deviceIdArg) { result: Result<List<UniversalBleService>> ->
              val error = result.exceptionOrNull()
              if (error != null) {
                reply.reply(wrapError(error))
              } else {
                val data = result.getOrNull()
                reply.reply(wrapResult(data))
              }
            }
          }
        } else {
          channel.setMessageHandler(null)
        }
      }
      run {
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.readValue$separatedMessageChannelSuffix", codec)
        if (api != null) {
          channel.setMessageHandler { message, reply ->
            val args = message as List<Any?>
            val deviceIdArg = args[0] as String
            val serviceArg = args[1] as String
            val characteristicArg = args[2] as String
            api.readValue(deviceIdArg, serviceArg, characteristicArg) { result: Result<ByteArray> ->
              val error = result.exceptionOrNull()
              if (error != null) {
                reply.reply(wrapError(error))
              } else {
                val data = result.getOrNull()
                reply.reply(wrapResult(data))
              }
            }
          }
        } else {
          channel.setMessageHandler(null)
        }
      }
      run {
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.requestMtu$separatedMessageChannelSuffix", codec)
        if (api != null) {
          channel.setMessageHandler { message, reply ->
            val args = message as List<Any?>
            val deviceIdArg = args[0] as String
            val expectedMtuArg = args[1].let { num -> if (num is Int) num.toLong() else num as Long }
            api.requestMtu(deviceIdArg, expectedMtuArg) { result: Result<Long> ->
              val error = result.exceptionOrNull()
              if (error != null) {
                reply.reply(wrapError(error))
              } else {
                val data = result.getOrNull()
                reply.reply(wrapResult(data))
              }
            }
          }
        } else {
          channel.setMessageHandler(null)
        }
      }
      run {
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.writeValue$separatedMessageChannelSuffix", codec)
        if (api != null) {
          channel.setMessageHandler { message, reply ->
            val args = message as List<Any?>
            val deviceIdArg = args[0] as String
            val serviceArg = args[1] as String
            val characteristicArg = args[2] as String
            val valueArg = args[3] as ByteArray
            val bleOutputPropertyArg = args[4].let { num -> if (num is Int) num.toLong() else num as Long }
            api.writeValue(deviceIdArg, serviceArg, characteristicArg, valueArg, bleOutputPropertyArg) { result: Result<Unit> ->
              val error = result.exceptionOrNull()
              if (error != null) {
                reply.reply(wrapError(error))
              } else {
                reply.reply(wrapResult(null))
              }
            }
          }
        } else {
          channel.setMessageHandler(null)
        }
      }
      run {
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.isPaired$separatedMessageChannelSuffix", codec)
        if (api != null) {
          channel.setMessageHandler { message, reply ->
            val args = message as List<Any?>
            val deviceIdArg = args[0] as String
            api.isPaired(deviceIdArg) { result: Result<Boolean> ->
              val error = result.exceptionOrNull()
              if (error != null) {
                reply.reply(wrapError(error))
              } else {
                val data = result.getOrNull()
                reply.reply(wrapResult(data))
              }
            }
          }
        } else {
          channel.setMessageHandler(null)
        }
      }
      run {
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.pair$separatedMessageChannelSuffix", codec)
        if (api != null) {
          channel.setMessageHandler { message, reply ->
            val args = message as List<Any?>
            val deviceIdArg = args[0] as String
            val wrapped: List<Any?> = try {
              api.pair(deviceIdArg)
              listOf<Any?>(null)
            } catch (exception: Throwable) {
              wrapError(exception)
            }
            reply.reply(wrapped)
          }
        } else {
          channel.setMessageHandler(null)
        }
      }
      run {
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.unPair$separatedMessageChannelSuffix", codec)
        if (api != null) {
          channel.setMessageHandler { message, reply ->
            val args = message as List<Any?>
            val deviceIdArg = args[0] as String
            val wrapped: List<Any?> = try {
              api.unPair(deviceIdArg)
              listOf<Any?>(null)
            } catch (exception: Throwable) {
              wrapError(exception)
            }
            reply.reply(wrapped)
          }
        } else {
          channel.setMessageHandler(null)
        }
      }
      run {
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.getConnectedDevices$separatedMessageChannelSuffix", codec)
        if (api != null) {
          channel.setMessageHandler { message, reply ->
            val args = message as List<Any?>
            val withServicesArg = args[0] as List<String>
            api.getConnectedDevices(withServicesArg) { result: Result<List<UniversalBleScanResult>> ->
              val error = result.exceptionOrNull()
              if (error != null) {
                reply.reply(wrapError(error))
              } else {
                val data = result.getOrNull()
                reply.reply(wrapResult(data))
              }
            }
          }
        } else {
          channel.setMessageHandler(null)
        }
      }
    }
  }
}
private object UniversalBleCallbackChannelCodec : StandardMessageCodec() {
  override fun readValueOfType(type: Byte, buffer: ByteBuffer): Any? {
    return when (type) {
      128.toByte() -> {
        return (readValue(buffer) as? List<Any?>)?.let {
          UniversalBleScanResult.fromList(it)
        }
      }
      else -> super.readValueOfType(type, buffer)
    }
  }
  override fun writeValue(stream: ByteArrayOutputStream, value: Any?)   {
    when (value) {
      is UniversalBleScanResult -> {
        stream.write(128)
        writeValue(stream, value.toList())
      }
      else -> super.writeValue(stream, value)
    }
  }
}

/**
 * Native -> Flutter
 *
 * Generated class from Pigeon that represents Flutter messages that can be called from Kotlin.
 */
class UniversalBleCallbackChannel(private val binaryMessenger: BinaryMessenger, private val messageChannelSuffix: String = "") {
  companion object {
    /** The codec used by UniversalBleCallbackChannel. */
    val codec: MessageCodec<Any?> by lazy {
      UniversalBleCallbackChannelCodec
    }
  }
  fun onAvailabilityChanged(stateArg: Long, callback: (Result<Unit>) -> Unit)
{
    val separatedMessageChannelSuffix = if (messageChannelSuffix.isNotEmpty()) ".$messageChannelSuffix" else ""
    val channelName = "dev.flutter.pigeon.universal_ble.UniversalBleCallbackChannel.onAvailabilityChanged$separatedMessageChannelSuffix"
    val channel = BasicMessageChannel<Any?>(binaryMessenger, channelName, codec)
    channel.send(listOf(stateArg)) {
      if (it is List<*>) {
        if (it.size > 1) {
          callback(Result.failure(FlutterError(it[0] as String, it[1] as String, it[2] as String?)))
        } else {
          callback(Result.success(Unit))
        }
      } else {
        callback(Result.failure(createConnectionError(channelName)))
      } 
    }
  }
  fun onPairStateChange(deviceIdArg: String, isPairedArg: Boolean, errorArg: String?, callback: (Result<Unit>) -> Unit)
{
    val separatedMessageChannelSuffix = if (messageChannelSuffix.isNotEmpty()) ".$messageChannelSuffix" else ""
    val channelName = "dev.flutter.pigeon.universal_ble.UniversalBleCallbackChannel.onPairStateChange$separatedMessageChannelSuffix"
    val channel = BasicMessageChannel<Any?>(binaryMessenger, channelName, codec)
    channel.send(listOf(deviceIdArg, isPairedArg, errorArg)) {
      if (it is List<*>) {
        if (it.size > 1) {
          callback(Result.failure(FlutterError(it[0] as String, it[1] as String, it[2] as String?)))
        } else {
          callback(Result.success(Unit))
        }
      } else {
        callback(Result.failure(createConnectionError(channelName)))
      } 
    }
  }
  fun onScanResult(resultArg: UniversalBleScanResult, callback: (Result<Unit>) -> Unit)
{
    val separatedMessageChannelSuffix = if (messageChannelSuffix.isNotEmpty()) ".$messageChannelSuffix" else ""
    val channelName = "dev.flutter.pigeon.universal_ble.UniversalBleCallbackChannel.onScanResult$separatedMessageChannelSuffix"
    val channel = BasicMessageChannel<Any?>(binaryMessenger, channelName, codec)
    channel.send(listOf(resultArg)) {
      if (it is List<*>) {
        if (it.size > 1) {
          callback(Result.failure(FlutterError(it[0] as String, it[1] as String, it[2] as String?)))
        } else {
          callback(Result.success(Unit))
        }
      } else {
        callback(Result.failure(createConnectionError(channelName)))
      } 
    }
  }
  fun onValueChanged(deviceIdArg: String, characteristicIdArg: String, valueArg: ByteArray, callback: (Result<Unit>) -> Unit)
{
    val separatedMessageChannelSuffix = if (messageChannelSuffix.isNotEmpty()) ".$messageChannelSuffix" else ""
    val channelName = "dev.flutter.pigeon.universal_ble.UniversalBleCallbackChannel.onValueChanged$separatedMessageChannelSuffix"
    val channel = BasicMessageChannel<Any?>(binaryMessenger, channelName, codec)
    channel.send(listOf(deviceIdArg, characteristicIdArg, valueArg)) {
      if (it is List<*>) {
        if (it.size > 1) {
          callback(Result.failure(FlutterError(it[0] as String, it[1] as String, it[2] as String?)))
        } else {
          callback(Result.success(Unit))
        }
      } else {
        callback(Result.failure(createConnectionError(channelName)))
      } 
    }
  }
  fun onConnectionChanged(deviceIdArg: String, stateArg: Long, callback: (Result<Unit>) -> Unit)
{
    val separatedMessageChannelSuffix = if (messageChannelSuffix.isNotEmpty()) ".$messageChannelSuffix" else ""
    val channelName = "dev.flutter.pigeon.universal_ble.UniversalBleCallbackChannel.onConnectionChanged$separatedMessageChannelSuffix"
    val channel = BasicMessageChannel<Any?>(binaryMessenger, channelName, codec)
    channel.send(listOf(deviceIdArg, stateArg)) {
      if (it is List<*>) {
        if (it.size > 1) {
          callback(Result.failure(FlutterError(it[0] as String, it[1] as String, it[2] as String?)))
        } else {
          callback(Result.success(Unit))
        }
      } else {
        callback(Result.failure(createConnectionError(channelName)))
      } 
    }
  }
}
