// Autogenerated from Pigeon (v16.0.5), do not edit directly.
// See also: https://pub.dev/packages/pigeon

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
  if (exception is FlutterError) {
    return listOf(
      exception.code,
      exception.message,
      exception.details
    )
  } else {
    return listOf(
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
  val manufacturerDataHead: ByteArray? = null

) {
  companion object {
    @Suppress("UNCHECKED_CAST")
    fun fromList(list: List<Any?>): UniversalBleScanResult {
      val deviceId = list[0] as String
      val name = list[1] as String?
      val isPaired = list[2] as Boolean?
      val rssi = list[3].let { if (it is Int) it.toLong() else it as Long? }
      val manufacturerData = list[4] as ByteArray?
      val manufacturerDataHead = list[5] as ByteArray?
      return UniversalBleScanResult(deviceId, name, isPaired, rssi, manufacturerData, manufacturerDataHead)
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
    )
  }
}

/** Generated class from Pigeon that represents data sent in messages. */
data class UniversalBleService (
  val uuid: String,
  val characteristics: List<UniversalBleCharacteristic?>? = null

) {
  companion object {
    @Suppress("UNCHECKED_CAST")
    fun fromList(list: List<Any?>): UniversalBleService {
      val uuid = list[0] as String
      val characteristics = list[1] as List<UniversalBleCharacteristic?>?
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
    @Suppress("UNCHECKED_CAST")
    fun fromList(list: List<Any?>): UniversalBleCharacteristic {
      val uuid = list[0] as String
      val properties = list[1] as List<Long?>
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

@Suppress("UNCHECKED_CAST")
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
  fun startScan()
  fun stopScan()
  fun connect(deviceId: String)
  fun disconnect(deviceId: String)
  fun setNotifiable(deviceId: String, service: String, characteristic: String, bleInputProperty: Long)
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
    @Suppress("UNCHECKED_CAST")
    fun setUp(binaryMessenger: BinaryMessenger, api: UniversalBlePlatformChannel?) {
      run {
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.getBluetoothAvailabilityState", codec)
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
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.enableBluetooth", codec)
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
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.startScan", codec)
        if (api != null) {
          channel.setMessageHandler { _, reply ->
            var wrapped: List<Any?>
            try {
              api.startScan()
              wrapped = listOf<Any?>(null)
            } catch (exception: Throwable) {
              wrapped = wrapError(exception)
            }
            reply.reply(wrapped)
          }
        } else {
          channel.setMessageHandler(null)
        }
      }
      run {
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.stopScan", codec)
        if (api != null) {
          channel.setMessageHandler { _, reply ->
            var wrapped: List<Any?>
            try {
              api.stopScan()
              wrapped = listOf<Any?>(null)
            } catch (exception: Throwable) {
              wrapped = wrapError(exception)
            }
            reply.reply(wrapped)
          }
        } else {
          channel.setMessageHandler(null)
        }
      }
      run {
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.connect", codec)
        if (api != null) {
          channel.setMessageHandler { message, reply ->
            val args = message as List<Any?>
            val deviceIdArg = args[0] as String
            var wrapped: List<Any?>
            try {
              api.connect(deviceIdArg)
              wrapped = listOf<Any?>(null)
            } catch (exception: Throwable) {
              wrapped = wrapError(exception)
            }
            reply.reply(wrapped)
          }
        } else {
          channel.setMessageHandler(null)
        }
      }
      run {
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.disconnect", codec)
        if (api != null) {
          channel.setMessageHandler { message, reply ->
            val args = message as List<Any?>
            val deviceIdArg = args[0] as String
            var wrapped: List<Any?>
            try {
              api.disconnect(deviceIdArg)
              wrapped = listOf<Any?>(null)
            } catch (exception: Throwable) {
              wrapped = wrapError(exception)
            }
            reply.reply(wrapped)
          }
        } else {
          channel.setMessageHandler(null)
        }
      }
      run {
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.setNotifiable", codec)
        if (api != null) {
          channel.setMessageHandler { message, reply ->
            val args = message as List<Any?>
            val deviceIdArg = args[0] as String
            val serviceArg = args[1] as String
            val characteristicArg = args[2] as String
            val bleInputPropertyArg = args[3].let { if (it is Int) it.toLong() else it as Long }
            var wrapped: List<Any?>
            try {
              api.setNotifiable(deviceIdArg, serviceArg, characteristicArg, bleInputPropertyArg)
              wrapped = listOf<Any?>(null)
            } catch (exception: Throwable) {
              wrapped = wrapError(exception)
            }
            reply.reply(wrapped)
          }
        } else {
          channel.setMessageHandler(null)
        }
      }
      run {
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.discoverServices", codec)
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
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.readValue", codec)
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
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.requestMtu", codec)
        if (api != null) {
          channel.setMessageHandler { message, reply ->
            val args = message as List<Any?>
            val deviceIdArg = args[0] as String
            val expectedMtuArg = args[1].let { if (it is Int) it.toLong() else it as Long }
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
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.writeValue", codec)
        if (api != null) {
          channel.setMessageHandler { message, reply ->
            val args = message as List<Any?>
            val deviceIdArg = args[0] as String
            val serviceArg = args[1] as String
            val characteristicArg = args[2] as String
            val valueArg = args[3] as ByteArray
            val bleOutputPropertyArg = args[4].let { if (it is Int) it.toLong() else it as Long }
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
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.isPaired", codec)
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
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.pair", codec)
        if (api != null) {
          channel.setMessageHandler { message, reply ->
            val args = message as List<Any?>
            val deviceIdArg = args[0] as String
            var wrapped: List<Any?>
            try {
              api.pair(deviceIdArg)
              wrapped = listOf<Any?>(null)
            } catch (exception: Throwable) {
              wrapped = wrapError(exception)
            }
            reply.reply(wrapped)
          }
        } else {
          channel.setMessageHandler(null)
        }
      }
      run {
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.unPair", codec)
        if (api != null) {
          channel.setMessageHandler { message, reply ->
            val args = message as List<Any?>
            val deviceIdArg = args[0] as String
            var wrapped: List<Any?>
            try {
              api.unPair(deviceIdArg)
              wrapped = listOf<Any?>(null)
            } catch (exception: Throwable) {
              wrapped = wrapError(exception)
            }
            reply.reply(wrapped)
          }
        } else {
          channel.setMessageHandler(null)
        }
      }
      run {
        val channel = BasicMessageChannel<Any?>(binaryMessenger, "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.getConnectedDevices", codec)
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
@Suppress("UNCHECKED_CAST")
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
@Suppress("UNCHECKED_CAST")
class UniversalBleCallbackChannel(private val binaryMessenger: BinaryMessenger) {
  companion object {
    /** The codec used by UniversalBleCallbackChannel. */
    val codec: MessageCodec<Any?> by lazy {
      UniversalBleCallbackChannelCodec
    }
  }
  fun onAvailabilityChanged(stateArg: Long, callback: (Result<Unit>) -> Unit)
{
    val channelName = "dev.flutter.pigeon.universal_ble.UniversalBleCallbackChannel.onAvailabilityChanged"
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
    val channelName = "dev.flutter.pigeon.universal_ble.UniversalBleCallbackChannel.onPairStateChange"
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
    val channelName = "dev.flutter.pigeon.universal_ble.UniversalBleCallbackChannel.onScanResult"
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
    val channelName = "dev.flutter.pigeon.universal_ble.UniversalBleCallbackChannel.onValueChanged"
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
    val channelName = "dev.flutter.pigeon.universal_ble.UniversalBleCallbackChannel.onConnectionChanged"
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