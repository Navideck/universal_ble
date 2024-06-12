// Autogenerated from Pigeon (v18.0.1), do not edit directly.
// See also: https://pub.dev/packages/pigeon

import Foundation

#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#else
  #error("Unsupported platform.")
#endif

private func wrapResult(_ result: Any?) -> [Any?] {
  return [result]
}

private func wrapError(_ error: Any) -> [Any?] {
  if let flutterError = error as? FlutterError {
    return [
      flutterError.code,
      flutterError.message,
      flutterError.details,
    ]
  }
  return [
    "\(error)",
    "\(type(of: error))",
    "Stacktrace: \(Thread.callStackSymbols)",
  ]
}

private func createConnectionError(withChannelName channelName: String) -> FlutterError {
  return FlutterError(code: "channel-error", message: "Unable to establish connection on channel: '\(channelName)'.", details: "")
}

private func isNullish(_ value: Any?) -> Bool {
  return value is NSNull || value == nil
}

private func nilOrValue<T>(_ value: Any?) -> T? {
  if value is NSNull { return nil }
  return value as! T?
}

/// Generated class from Pigeon that represents data sent in messages.
struct UniversalBleScanResult {
  var deviceId: String
  var name: String? = nil
  var isPaired: Bool? = nil
  var rssi: Int64? = nil
  var manufacturerData: FlutterStandardTypedData? = nil
  var manufacturerDataHead: FlutterStandardTypedData? = nil
  var services: [String?]? = nil

  // swift-format-ignore: AlwaysUseLowerCamelCase
  static func fromList(_ __pigeon_list: [Any?]) -> UniversalBleScanResult? {
    let deviceId = __pigeon_list[0] as! String
    let name: String? = nilOrValue(__pigeon_list[1])
    let isPaired: Bool? = nilOrValue(__pigeon_list[2])
    let rssi: Int64? = isNullish(__pigeon_list[3]) ? nil : (__pigeon_list[3] is Int64? ? __pigeon_list[3] as! Int64? : Int64(__pigeon_list[3] as! Int32))
    let manufacturerData: FlutterStandardTypedData? = nilOrValue(__pigeon_list[4])
    let manufacturerDataHead: FlutterStandardTypedData? = nilOrValue(__pigeon_list[5])
    let services: [String?]? = nilOrValue(__pigeon_list[6])

    return UniversalBleScanResult(
      deviceId: deviceId,
      name: name,
      isPaired: isPaired,
      rssi: rssi,
      manufacturerData: manufacturerData,
      manufacturerDataHead: manufacturerDataHead,
      services: services
    )
  }
  func toList() -> [Any?] {
    return [
      deviceId,
      name,
      isPaired,
      rssi,
      manufacturerData,
      manufacturerDataHead,
      services,
    ]
  }
}

/// Generated class from Pigeon that represents data sent in messages.
struct UniversalBleService {
  var uuid: String
  var characteristics: [UniversalBleCharacteristic?]? = nil

  // swift-format-ignore: AlwaysUseLowerCamelCase
  static func fromList(_ __pigeon_list: [Any?]) -> UniversalBleService? {
    let uuid = __pigeon_list[0] as! String
    let characteristics: [UniversalBleCharacteristic?]? = nilOrValue(__pigeon_list[1])

    return UniversalBleService(
      uuid: uuid,
      characteristics: characteristics
    )
  }
  func toList() -> [Any?] {
    return [
      uuid,
      characteristics,
    ]
  }
}

/// Generated class from Pigeon that represents data sent in messages.
struct UniversalBleCharacteristic {
  var uuid: String
  var properties: [Int64?]

  // swift-format-ignore: AlwaysUseLowerCamelCase
  static func fromList(_ __pigeon_list: [Any?]) -> UniversalBleCharacteristic? {
    let uuid = __pigeon_list[0] as! String
    let properties = __pigeon_list[1] as! [Int64?]

    return UniversalBleCharacteristic(
      uuid: uuid,
      properties: properties
    )
  }
  func toList() -> [Any?] {
    return [
      uuid,
      properties,
    ]
  }
}

/// Scan Filters
///
/// Generated class from Pigeon that represents data sent in messages.
struct UniversalScanFilter {
  var withServices: [String?]
  var withManufacturerData: [UniversalManufacturerDataFilter?]

  // swift-format-ignore: AlwaysUseLowerCamelCase
  static func fromList(_ __pigeon_list: [Any?]) -> UniversalScanFilter? {
    let withServices = __pigeon_list[0] as! [String?]
    let withManufacturerData = __pigeon_list[1] as! [UniversalManufacturerDataFilter?]

    return UniversalScanFilter(
      withServices: withServices,
      withManufacturerData: withManufacturerData
    )
  }
  func toList() -> [Any?] {
    return [
      withServices,
      withManufacturerData,
    ]
  }
}

/// Generated class from Pigeon that represents data sent in messages.
struct UniversalManufacturerDataFilter {
  var companyIdentifier: Int64? = nil
  var data: FlutterStandardTypedData? = nil
  var mask: FlutterStandardTypedData? = nil

  // swift-format-ignore: AlwaysUseLowerCamelCase
  static func fromList(_ __pigeon_list: [Any?]) -> UniversalManufacturerDataFilter? {
    let companyIdentifier: Int64? = isNullish(__pigeon_list[0]) ? nil : (__pigeon_list[0] is Int64? ? __pigeon_list[0] as! Int64? : Int64(__pigeon_list[0] as! Int32))
    let data: FlutterStandardTypedData? = nilOrValue(__pigeon_list[1])
    let mask: FlutterStandardTypedData? = nilOrValue(__pigeon_list[2])

    return UniversalManufacturerDataFilter(
      companyIdentifier: companyIdentifier,
      data: data,
      mask: mask
    )
  }
  func toList() -> [Any?] {
    return [
      companyIdentifier,
      data,
      mask,
    ]
  }
}

private class UniversalBlePlatformChannelCodecReader: FlutterStandardReader {
  override func readValue(ofType type: UInt8) -> Any? {
    switch type {
    case 128:
      return UniversalBleCharacteristic.fromList(self.readValue() as! [Any?])
    case 129:
      return UniversalBleScanResult.fromList(self.readValue() as! [Any?])
    case 130:
      return UniversalBleService.fromList(self.readValue() as! [Any?])
    case 131:
      return UniversalManufacturerDataFilter.fromList(self.readValue() as! [Any?])
    case 132:
      return UniversalScanFilter.fromList(self.readValue() as! [Any?])
    default:
      return super.readValue(ofType: type)
    }
  }
}

private class UniversalBlePlatformChannelCodecWriter: FlutterStandardWriter {
  override func writeValue(_ value: Any) {
    if let value = value as? UniversalBleCharacteristic {
      super.writeByte(128)
      super.writeValue(value.toList())
    } else if let value = value as? UniversalBleScanResult {
      super.writeByte(129)
      super.writeValue(value.toList())
    } else if let value = value as? UniversalBleService {
      super.writeByte(130)
      super.writeValue(value.toList())
    } else if let value = value as? UniversalManufacturerDataFilter {
      super.writeByte(131)
      super.writeValue(value.toList())
    } else if let value = value as? UniversalScanFilter {
      super.writeByte(132)
      super.writeValue(value.toList())
    } else {
      super.writeValue(value)
    }
  }
}

private class UniversalBlePlatformChannelCodecReaderWriter: FlutterStandardReaderWriter {
  override func reader(with data: Data) -> FlutterStandardReader {
    return UniversalBlePlatformChannelCodecReader(data: data)
  }

  override func writer(with data: NSMutableData) -> FlutterStandardWriter {
    return UniversalBlePlatformChannelCodecWriter(data: data)
  }
}

class UniversalBlePlatformChannelCodec: FlutterStandardMessageCodec {
  static let shared = UniversalBlePlatformChannelCodec(readerWriter: UniversalBlePlatformChannelCodecReaderWriter())
}

/// Flutter -> Native
///
/// Generated protocol from Pigeon that represents a handler of messages from Flutter.
protocol UniversalBlePlatformChannel {
  func getBluetoothAvailabilityState(completion: @escaping (Result<Int64, Error>) -> Void)
  func enableBluetooth(completion: @escaping (Result<Bool, Error>) -> Void)
  func startScan(filter: UniversalScanFilter?) throws
  func stopScan() throws
  func connect(deviceId: String) throws
  func disconnect(deviceId: String) throws
  func setNotifiable(deviceId: String, service: String, characteristic: String, bleInputProperty: Int64, completion: @escaping (Result<Void, Error>) -> Void)
  func discoverServices(deviceId: String, completion: @escaping (Result<[UniversalBleService], Error>) -> Void)
  func readValue(deviceId: String, service: String, characteristic: String, completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void)
  func requestMtu(deviceId: String, expectedMtu: Int64, completion: @escaping (Result<Int64, Error>) -> Void)
  func writeValue(deviceId: String, service: String, characteristic: String, value: FlutterStandardTypedData, bleOutputProperty: Int64, completion: @escaping (Result<Void, Error>) -> Void)
  func isPaired(deviceId: String, completion: @escaping (Result<Bool, Error>) -> Void)
  func pair(deviceId: String) throws
  func unPair(deviceId: String) throws
  func getConnectedDevices(withServices: [String], completion: @escaping (Result<[UniversalBleScanResult], Error>) -> Void)
  func isConnected(deviceId: String) throws -> Bool
}

/// Generated setup class from Pigeon to handle messages through the `binaryMessenger`.
class UniversalBlePlatformChannelSetup {
  /// The codec used by UniversalBlePlatformChannel.
  static var codec: FlutterStandardMessageCodec { UniversalBlePlatformChannelCodec.shared }
  /// Sets up an instance of `UniversalBlePlatformChannel` to handle messages through the `binaryMessenger`.
  static func setUp(binaryMessenger: FlutterBinaryMessenger, api: UniversalBlePlatformChannel?, messageChannelSuffix: String = "") {
    let channelSuffix = messageChannelSuffix.count > 0 ? ".\(messageChannelSuffix)" : ""
    let getBluetoothAvailabilityStateChannel = FlutterBasicMessageChannel(name: "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.getBluetoothAvailabilityState\(channelSuffix)", binaryMessenger: binaryMessenger, codec: codec)
    if let api = api {
      getBluetoothAvailabilityStateChannel.setMessageHandler { _, reply in
        api.getBluetoothAvailabilityState { result in
          switch result {
          case .success(let res):
            reply(wrapResult(res))
          case .failure(let error):
            reply(wrapError(error))
          }
        }
      }
    } else {
      getBluetoothAvailabilityStateChannel.setMessageHandler(nil)
    }
    let enableBluetoothChannel = FlutterBasicMessageChannel(name: "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.enableBluetooth\(channelSuffix)", binaryMessenger: binaryMessenger, codec: codec)
    if let api = api {
      enableBluetoothChannel.setMessageHandler { _, reply in
        api.enableBluetooth { result in
          switch result {
          case .success(let res):
            reply(wrapResult(res))
          case .failure(let error):
            reply(wrapError(error))
          }
        }
      }
    } else {
      enableBluetoothChannel.setMessageHandler(nil)
    }
    let startScanChannel = FlutterBasicMessageChannel(name: "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.startScan\(channelSuffix)", binaryMessenger: binaryMessenger, codec: codec)
    if let api = api {
      startScanChannel.setMessageHandler { message, reply in
        let args = message as! [Any?]
        let filterArg: UniversalScanFilter? = nilOrValue(args[0])
        do {
          try api.startScan(filter: filterArg)
          reply(wrapResult(nil))
        } catch {
          reply(wrapError(error))
        }
      }
    } else {
      startScanChannel.setMessageHandler(nil)
    }
    let stopScanChannel = FlutterBasicMessageChannel(name: "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.stopScan\(channelSuffix)", binaryMessenger: binaryMessenger, codec: codec)
    if let api = api {
      stopScanChannel.setMessageHandler { _, reply in
        do {
          try api.stopScan()
          reply(wrapResult(nil))
        } catch {
          reply(wrapError(error))
        }
      }
    } else {
      stopScanChannel.setMessageHandler(nil)
    }
    let connectChannel = FlutterBasicMessageChannel(name: "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.connect\(channelSuffix)", binaryMessenger: binaryMessenger, codec: codec)
    if let api = api {
      connectChannel.setMessageHandler { message, reply in
        let args = message as! [Any?]
        let deviceIdArg = args[0] as! String
        do {
          try api.connect(deviceId: deviceIdArg)
          reply(wrapResult(nil))
        } catch {
          reply(wrapError(error))
        }
      }
    } else {
      connectChannel.setMessageHandler(nil)
    }
    let disconnectChannel = FlutterBasicMessageChannel(name: "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.disconnect\(channelSuffix)", binaryMessenger: binaryMessenger, codec: codec)
    if let api = api {
      disconnectChannel.setMessageHandler { message, reply in
        let args = message as! [Any?]
        let deviceIdArg = args[0] as! String
        do {
          try api.disconnect(deviceId: deviceIdArg)
          reply(wrapResult(nil))
        } catch {
          reply(wrapError(error))
        }
      }
    } else {
      disconnectChannel.setMessageHandler(nil)
    }
    let setNotifiableChannel = FlutterBasicMessageChannel(name: "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.setNotifiable\(channelSuffix)", binaryMessenger: binaryMessenger, codec: codec)
    if let api = api {
      setNotifiableChannel.setMessageHandler { message, reply in
        let args = message as! [Any?]
        let deviceIdArg = args[0] as! String
        let serviceArg = args[1] as! String
        let characteristicArg = args[2] as! String
        let bleInputPropertyArg = args[3] is Int64 ? args[3] as! Int64 : Int64(args[3] as! Int32)
        api.setNotifiable(deviceId: deviceIdArg, service: serviceArg, characteristic: characteristicArg, bleInputProperty: bleInputPropertyArg) { result in
          switch result {
          case .success:
            reply(wrapResult(nil))
          case .failure(let error):
            reply(wrapError(error))
          }
        }
      }
    } else {
      setNotifiableChannel.setMessageHandler(nil)
    }
    let discoverServicesChannel = FlutterBasicMessageChannel(name: "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.discoverServices\(channelSuffix)", binaryMessenger: binaryMessenger, codec: codec)
    if let api = api {
      discoverServicesChannel.setMessageHandler { message, reply in
        let args = message as! [Any?]
        let deviceIdArg = args[0] as! String
        api.discoverServices(deviceId: deviceIdArg) { result in
          switch result {
          case .success(let res):
            reply(wrapResult(res))
          case .failure(let error):
            reply(wrapError(error))
          }
        }
      }
    } else {
      discoverServicesChannel.setMessageHandler(nil)
    }
    let readValueChannel = FlutterBasicMessageChannel(name: "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.readValue\(channelSuffix)", binaryMessenger: binaryMessenger, codec: codec)
    if let api = api {
      readValueChannel.setMessageHandler { message, reply in
        let args = message as! [Any?]
        let deviceIdArg = args[0] as! String
        let serviceArg = args[1] as! String
        let characteristicArg = args[2] as! String
        api.readValue(deviceId: deviceIdArg, service: serviceArg, characteristic: characteristicArg) { result in
          switch result {
          case .success(let res):
            reply(wrapResult(res))
          case .failure(let error):
            reply(wrapError(error))
          }
        }
      }
    } else {
      readValueChannel.setMessageHandler(nil)
    }
    let requestMtuChannel = FlutterBasicMessageChannel(name: "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.requestMtu\(channelSuffix)", binaryMessenger: binaryMessenger, codec: codec)
    if let api = api {
      requestMtuChannel.setMessageHandler { message, reply in
        let args = message as! [Any?]
        let deviceIdArg = args[0] as! String
        let expectedMtuArg = args[1] is Int64 ? args[1] as! Int64 : Int64(args[1] as! Int32)
        api.requestMtu(deviceId: deviceIdArg, expectedMtu: expectedMtuArg) { result in
          switch result {
          case .success(let res):
            reply(wrapResult(res))
          case .failure(let error):
            reply(wrapError(error))
          }
        }
      }
    } else {
      requestMtuChannel.setMessageHandler(nil)
    }
    let writeValueChannel = FlutterBasicMessageChannel(name: "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.writeValue\(channelSuffix)", binaryMessenger: binaryMessenger, codec: codec)
    if let api = api {
      writeValueChannel.setMessageHandler { message, reply in
        let args = message as! [Any?]
        let deviceIdArg = args[0] as! String
        let serviceArg = args[1] as! String
        let characteristicArg = args[2] as! String
        let valueArg = args[3] as! FlutterStandardTypedData
        let bleOutputPropertyArg = args[4] is Int64 ? args[4] as! Int64 : Int64(args[4] as! Int32)
        api.writeValue(deviceId: deviceIdArg, service: serviceArg, characteristic: characteristicArg, value: valueArg, bleOutputProperty: bleOutputPropertyArg) { result in
          switch result {
          case .success:
            reply(wrapResult(nil))
          case .failure(let error):
            reply(wrapError(error))
          }
        }
      }
    } else {
      writeValueChannel.setMessageHandler(nil)
    }
    let isPairedChannel = FlutterBasicMessageChannel(name: "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.isPaired\(channelSuffix)", binaryMessenger: binaryMessenger, codec: codec)
    if let api = api {
      isPairedChannel.setMessageHandler { message, reply in
        let args = message as! [Any?]
        let deviceIdArg = args[0] as! String
        api.isPaired(deviceId: deviceIdArg) { result in
          switch result {
          case .success(let res):
            reply(wrapResult(res))
          case .failure(let error):
            reply(wrapError(error))
          }
        }
      }
    } else {
      isPairedChannel.setMessageHandler(nil)
    }
    let pairChannel = FlutterBasicMessageChannel(name: "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.pair\(channelSuffix)", binaryMessenger: binaryMessenger, codec: codec)
    if let api = api {
      pairChannel.setMessageHandler { message, reply in
        let args = message as! [Any?]
        let deviceIdArg = args[0] as! String
        do {
          try api.pair(deviceId: deviceIdArg)
          reply(wrapResult(nil))
        } catch {
          reply(wrapError(error))
        }
      }
    } else {
      pairChannel.setMessageHandler(nil)
    }
    let unPairChannel = FlutterBasicMessageChannel(name: "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.unPair\(channelSuffix)", binaryMessenger: binaryMessenger, codec: codec)
    if let api = api {
      unPairChannel.setMessageHandler { message, reply in
        let args = message as! [Any?]
        let deviceIdArg = args[0] as! String
        do {
          try api.unPair(deviceId: deviceIdArg)
          reply(wrapResult(nil))
        } catch {
          reply(wrapError(error))
        }
      }
    } else {
      unPairChannel.setMessageHandler(nil)
    }
    let getConnectedDevicesChannel = FlutterBasicMessageChannel(name: "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.getConnectedDevices\(channelSuffix)", binaryMessenger: binaryMessenger, codec: codec)
    if let api = api {
      getConnectedDevicesChannel.setMessageHandler { message, reply in
        let args = message as! [Any?]
        let withServicesArg = args[0] as! [String]
        api.getConnectedDevices(withServices: withServicesArg) { result in
          switch result {
          case .success(let res):
            reply(wrapResult(res))
          case .failure(let error):
            reply(wrapError(error))
          }
        }
      }
    } else {
      getConnectedDevicesChannel.setMessageHandler(nil)
    }
    let isConnectedChannel = FlutterBasicMessageChannel(name: "dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.isConnected\(channelSuffix)", binaryMessenger: binaryMessenger, codec: codec)
    if let api = api {
      isConnectedChannel.setMessageHandler { message, reply in
        let args = message as! [Any?]
        let deviceIdArg = args[0] as! String
        do {
          let result = try api.isConnected(deviceId: deviceIdArg)
          reply(wrapResult(result))
        } catch {
          reply(wrapError(error))
        }
      }
    } else {
      isConnectedChannel.setMessageHandler(nil)
    }
  }
}
private class UniversalBleCallbackChannelCodecReader: FlutterStandardReader {
  override func readValue(ofType type: UInt8) -> Any? {
    switch type {
    case 128:
      return UniversalBleScanResult.fromList(self.readValue() as! [Any?])
    default:
      return super.readValue(ofType: type)
    }
  }
}

private class UniversalBleCallbackChannelCodecWriter: FlutterStandardWriter {
  override func writeValue(_ value: Any) {
    if let value = value as? UniversalBleScanResult {
      super.writeByte(128)
      super.writeValue(value.toList())
    } else {
      super.writeValue(value)
    }
  }
}

private class UniversalBleCallbackChannelCodecReaderWriter: FlutterStandardReaderWriter {
  override func reader(with data: Data) -> FlutterStandardReader {
    return UniversalBleCallbackChannelCodecReader(data: data)
  }

  override func writer(with data: NSMutableData) -> FlutterStandardWriter {
    return UniversalBleCallbackChannelCodecWriter(data: data)
  }
}

class UniversalBleCallbackChannelCodec: FlutterStandardMessageCodec {
  static let shared = UniversalBleCallbackChannelCodec(readerWriter: UniversalBleCallbackChannelCodecReaderWriter())
}

/// Native -> Flutter
///
/// Generated protocol from Pigeon that represents Flutter messages that can be called from Swift.
protocol UniversalBleCallbackChannelProtocol {
  func onAvailabilityChanged(state stateArg: Int64, completion: @escaping (Result<Void, FlutterError>) -> Void)
  func onPairStateChange(deviceId deviceIdArg: String, isPaired isPairedArg: Bool, error errorArg: String?, completion: @escaping (Result<Void, FlutterError>) -> Void)
  func onScanResult(result resultArg: UniversalBleScanResult, completion: @escaping (Result<Void, FlutterError>) -> Void)
  func onValueChanged(deviceId deviceIdArg: String, characteristicId characteristicIdArg: String, value valueArg: FlutterStandardTypedData, completion: @escaping (Result<Void, FlutterError>) -> Void)
  func onConnectionChanged(deviceId deviceIdArg: String, state stateArg: Int64, completion: @escaping (Result<Void, FlutterError>) -> Void)
}
class UniversalBleCallbackChannel: UniversalBleCallbackChannelProtocol {
  private let binaryMessenger: FlutterBinaryMessenger
  private let messageChannelSuffix: String
  init(binaryMessenger: FlutterBinaryMessenger, messageChannelSuffix: String = "") {
    self.binaryMessenger = binaryMessenger
    self.messageChannelSuffix = messageChannelSuffix.count > 0 ? ".\(messageChannelSuffix)" : ""
  }
  var codec: FlutterStandardMessageCodec {
    return UniversalBleCallbackChannelCodec.shared
  }
  func onAvailabilityChanged(state stateArg: Int64, completion: @escaping (Result<Void, FlutterError>) -> Void) {
    let channelName: String = "dev.flutter.pigeon.universal_ble.UniversalBleCallbackChannel.onAvailabilityChanged\(messageChannelSuffix)"
    let channel = FlutterBasicMessageChannel(name: channelName, binaryMessenger: binaryMessenger, codec: codec)
    channel.sendMessage([stateArg] as [Any?]) { response in
      guard let listResponse = response as? [Any?] else {
        completion(.failure(createConnectionError(withChannelName: channelName)))
        return
      }
      if listResponse.count > 1 {
        let code: String = listResponse[0] as! String
        let message: String? = nilOrValue(listResponse[1])
        let details: String? = nilOrValue(listResponse[2])
        completion(.failure(FlutterError(code: code, message: message, details: details)))
      } else {
        completion(.success(Void()))
      }
    }
  }
  func onPairStateChange(deviceId deviceIdArg: String, isPaired isPairedArg: Bool, error errorArg: String?, completion: @escaping (Result<Void, FlutterError>) -> Void) {
    let channelName: String = "dev.flutter.pigeon.universal_ble.UniversalBleCallbackChannel.onPairStateChange\(messageChannelSuffix)"
    let channel = FlutterBasicMessageChannel(name: channelName, binaryMessenger: binaryMessenger, codec: codec)
    channel.sendMessage([deviceIdArg, isPairedArg, errorArg] as [Any?]) { response in
      guard let listResponse = response as? [Any?] else {
        completion(.failure(createConnectionError(withChannelName: channelName)))
        return
      }
      if listResponse.count > 1 {
        let code: String = listResponse[0] as! String
        let message: String? = nilOrValue(listResponse[1])
        let details: String? = nilOrValue(listResponse[2])
        completion(.failure(FlutterError(code: code, message: message, details: details)))
      } else {
        completion(.success(Void()))
      }
    }
  }
  func onScanResult(result resultArg: UniversalBleScanResult, completion: @escaping (Result<Void, FlutterError>) -> Void) {
    let channelName: String = "dev.flutter.pigeon.universal_ble.UniversalBleCallbackChannel.onScanResult\(messageChannelSuffix)"
    let channel = FlutterBasicMessageChannel(name: channelName, binaryMessenger: binaryMessenger, codec: codec)
    channel.sendMessage([resultArg] as [Any?]) { response in
      guard let listResponse = response as? [Any?] else {
        completion(.failure(createConnectionError(withChannelName: channelName)))
        return
      }
      if listResponse.count > 1 {
        let code: String = listResponse[0] as! String
        let message: String? = nilOrValue(listResponse[1])
        let details: String? = nilOrValue(listResponse[2])
        completion(.failure(FlutterError(code: code, message: message, details: details)))
      } else {
        completion(.success(Void()))
      }
    }
  }
  func onValueChanged(deviceId deviceIdArg: String, characteristicId characteristicIdArg: String, value valueArg: FlutterStandardTypedData, completion: @escaping (Result<Void, FlutterError>) -> Void) {
    let channelName: String = "dev.flutter.pigeon.universal_ble.UniversalBleCallbackChannel.onValueChanged\(messageChannelSuffix)"
    let channel = FlutterBasicMessageChannel(name: channelName, binaryMessenger: binaryMessenger, codec: codec)
    channel.sendMessage([deviceIdArg, characteristicIdArg, valueArg] as [Any?]) { response in
      guard let listResponse = response as? [Any?] else {
        completion(.failure(createConnectionError(withChannelName: channelName)))
        return
      }
      if listResponse.count > 1 {
        let code: String = listResponse[0] as! String
        let message: String? = nilOrValue(listResponse[1])
        let details: String? = nilOrValue(listResponse[2])
        completion(.failure(FlutterError(code: code, message: message, details: details)))
      } else {
        completion(.success(Void()))
      }
    }
  }
  func onConnectionChanged(deviceId deviceIdArg: String, state stateArg: Int64, completion: @escaping (Result<Void, FlutterError>) -> Void) {
    let channelName: String = "dev.flutter.pigeon.universal_ble.UniversalBleCallbackChannel.onConnectionChanged\(messageChannelSuffix)"
    let channel = FlutterBasicMessageChannel(name: channelName, binaryMessenger: binaryMessenger, codec: codec)
    channel.sendMessage([deviceIdArg, stateArg] as [Any?]) { response in
      guard let listResponse = response as? [Any?] else {
        completion(.failure(createConnectionError(withChannelName: channelName)))
        return
      }
      if listResponse.count > 1 {
        let code: String = listResponse[0] as! String
        let message: String? = nilOrValue(listResponse[1])
        let details: String? = nilOrValue(listResponse[2])
        completion(.failure(FlutterError(code: code, message: message, details: details)))
      } else {
        completion(.success(Void()))
      }
    }
  }
}
