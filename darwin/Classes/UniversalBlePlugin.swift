import CoreBluetooth

#if os(iOS)
  import Flutter
  import UIKit
#elseif os(OSX)
  import Cocoa
  import FlutterMacOS
#endif

public class UniversalBlePlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    var messenger: FlutterBinaryMessenger
    #if os(iOS)
      messenger = registrar.messenger()
    #elseif os(macOS)
      messenger = registrar.messenger
    #endif
    let callbackChannel = UniversalBleCallbackChannel(binaryMessenger: messenger)
    let api = BleCentralDarwin(callbackChannel: callbackChannel)
    UniversalBlePlatformChannelSetup.setUp(binaryMessenger: messenger, api: api)
  }
}

private var discoveredPeripherals = [String: CBPeripheral]()

private class BleCentralDarwin: NSObject, UniversalBlePlatformChannel, CBCentralManagerDelegate, CBPeripheralDelegate {
  var callbackChannel: UniversalBleCallbackChannel
  private lazy var manager: CBCentralManager = .init(delegate: self, queue: nil)
  private var discoveredServicesProgressMap: [String: [UniversalBleService]] = [:]
  private var characteristicReadFutures = [CharacteristicReadFuture]()
  private var characteristicWriteFutures = [CharacteristicWriteFuture]()
  private var discoverServicesFutures = [DiscoverServicesFuture]()
  private var bluetoothAvailabilityStateCallback: ((Result<Int64, Error>) -> Void)? {
    didSet {
      oldValue?(Result.success(AvailabilityState.unknown.rawValue))
    }
  }

  init(callbackChannel: UniversalBleCallbackChannel) {
    self.callbackChannel = callbackChannel
    super.init()
  }

  func getBluetoothAvailabilityState(completion: @escaping (Result<Int64, Error>) -> Void) {
    let managerState = manager.state

    if managerState == .unknown {
      bluetoothAvailabilityStateCallback = completion
    } else {
      completion(.success(managerState.toAvailabilityState().rawValue))
    }
  }

  func enableBluetooth(completion: @escaping (Result<Bool, Error>) -> Void) {
    completion(Result.failure(FlutterError(code: "NotSupported", message: nil, details: nil)))
  }

  func startScan(filter: UniversalScanFilter?) throws {
    
    // Apply services filter
    var withServices: [CBUUID] = []
    for service in filter?.withServices ?? [] {
      if let service = service {
          if UUID(uuidString: service.validFullUUID) == nil {
          throw FlutterError(code: "IllegalArgument", message: "Invalid service UUID:\(service)", details: nil)
        }
        withServices.append(CBUUID(string: service))
      }
    }

    manager.scanForPeripherals(withServices: withServices)
  }

  func stopScan() throws {
    manager.stopScan()
  }

  func connect(deviceId: String) throws {
    let peripheral = try deviceId.getPeripheral()
    peripheral.delegate = self
    manager.connect(peripheral)
  }

  func disconnect(deviceId: String) throws {
    let peripheral = try deviceId.getPeripheral()
    if peripheral.state != CBPeripheralState.disconnected {
      manager.cancelPeripheralConnection(peripheral)
    }
    cleanUpConnection(deviceId: deviceId)
  }

  func cleanUpConnection(deviceId: String) {
    characteristicReadFutures.removeAll { future in
      future.deviceId == deviceId
    }
    discoverServicesFutures.removeAll { future in
      future.deviceId == deviceId
    }
    discoveredServicesProgressMap[deviceId] = nil
  }

  func discoverServices(deviceId: String, completion: @escaping (Result<[UniversalBleService], Error>) -> Void) {
    guard let peripheral = discoveredPeripherals[deviceId] else {
      completion(Result.failure(
        FlutterError(code: "IllegalArgument", message: "Unknown deviceId:\(self)", details: nil)))
      return
    }
    if discoveredServicesProgressMap[deviceId] != nil {
      completion(Result.failure(FlutterError(code: "AlreadyInProgress", message: "Services discovery already in progress for :\(deviceId)", details: nil)))
      return
    }
    peripheral.discoverServices(nil)
    discoverServicesFutures.append(DiscoverServicesFuture(deviceId: deviceId, result: completion))
  }

  private func onServicesDiscovered(deviceId: String, services: [UniversalBleService]) {
    discoverServicesFutures.removeAll { future in
      if future.deviceId == deviceId {
        future.result(Result.success(services))
        return true
      }
      return false
    }
  }

  func setNotifiable(deviceId: String, service: String, characteristic: String, bleInputProperty: Int64) throws {
    let peripheral = try deviceId.getPeripheral()

    guard let c = peripheral.getCharacteristic(characteristic, of: service) else {
      throw FlutterError(code: "IllegalArgument", message: "Unknown characteristic:\(characteristic)", details: nil)
    }

    if bleInputProperty == BleInputProperty.notification.rawValue && !c.properties.contains(.notify) {
      throw FlutterError(code: "InvalidAction", message: "Characteristic does not support notify", details: nil)
    }

    if bleInputProperty == BleInputProperty.indication.rawValue && !c.properties.contains(.indicate) {
      throw FlutterError(code: "InvalidAction", message: "Characteristic does not support indicate", details: nil)
    }

    let shouldNotify = bleInputProperty != BleInputProperty.disabled.rawValue
    peripheral.setNotifyValue(shouldNotify, for: c)
  }

  func readValue(deviceId: String, service: String, characteristic: String, completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) {
    guard let peripheral = discoveredPeripherals[deviceId] else {
      completion(Result.failure(FlutterError(code: "IllegalArgument", message: "Unknown deviceId:\(self)", details: nil)))
      return
    }
    guard let gattCharacteristic = peripheral.getCharacteristic(characteristic, of: service) else {
      completion(Result.failure(FlutterError(code: "IllegalArgument", message: "Unknown characteristic:\(characteristic)", details: nil)))
      return
    }
    if !gattCharacteristic.properties.contains(.read) {
      completion(Result.failure(FlutterError(code: "InvalidAction", message: "Characteristic does not support read", details: nil)))
      return
    }
    peripheral.readValue(for: gattCharacteristic)
    characteristicReadFutures.append(CharacteristicReadFuture(deviceId: deviceId, characteristicId: gattCharacteristic.uuid.uuidStr, serviceId: gattCharacteristic.service?.uuid.uuidStr, result: completion))
  }

  func writeValue(deviceId: String, service: String, characteristic: String, value: FlutterStandardTypedData, bleOutputProperty: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
    guard let peripheral = discoveredPeripherals[deviceId] else {
      completion(Result.failure(FlutterError(code: "IllegalArgument", message: "Unknown deviceId:\(self)", details: nil)))
      return
    }
    guard let gattCharacteristic = peripheral.getCharacteristic(characteristic, of: service) else {
      completion(Result.failure(FlutterError(code: "IllegalArgument", message: "Unknown characteristic:\(characteristic)", details: nil)))
      return
    }

    let type = bleOutputProperty == BleOutputProperty.withoutResponse.rawValue ? CBCharacteristicWriteType.withoutResponse : CBCharacteristicWriteType.withResponse

    if type == CBCharacteristicWriteType.withResponse {
      if !gattCharacteristic.properties.contains(.write) {
        completion(Result.failure(FlutterError(code: "InvalidAction", message: "Characteristic does not support write withResponse", details: nil)))
        return
      }
    } else if type == CBCharacteristicWriteType.withoutResponse {
      if !gattCharacteristic.properties.contains(.writeWithoutResponse) {
        completion(Result.failure(FlutterError(code: "InvalidAction", message: "Characteristic does not support write withoutResponse", details: nil)))
        return
      }
    }
    peripheral.writeValue(value.data, for: gattCharacteristic, type: type)

    if type == CBCharacteristicWriteType.withResponse {
      // Wait for future response
      characteristicWriteFutures.append(CharacteristicWriteFuture(deviceId: deviceId, characteristicId: gattCharacteristic.uuid.uuidStr, serviceId: gattCharacteristic.service?.uuid.uuidStr, result: completion))
    } else {
      completion(Result.success({}()))
    }
  }

  func requestMtu(deviceId: String, expectedMtu _: Int64, completion: @escaping (Result<Int64, Error>) -> Void) {
    guard let peripheral = discoveredPeripherals[deviceId] else {
      completion(Result.failure(FlutterError(code: "IllegalArgument", message: "Unknown deviceId:\(self)", details: nil)))
      return
    }
    let mtu = peripheral.maximumWriteValueLength(for: CBCharacteristicWriteType.withoutResponse)
    let GATT_HEADER_LENGTH = 3
    let mtuResult = Int64(mtu + GATT_HEADER_LENGTH)
    completion(Result.success(mtuResult))
  }

  func isPaired(deviceId _: String, completion: @escaping (Result<Bool, Error>) -> Void) {
    completion(Result.failure(FlutterError(code: "NotSupported", message: nil, details: nil)))
  }

  func pair(deviceId _: String) throws {
    throw FlutterError(code: "NotSupported", message: nil, details: nil)
  }

  func unPair(deviceId _: String) throws {
    throw FlutterError(code: "NotSupported", message: nil, details: nil)
  }

  func getConnectedDevices(withServices: [String], completion: @escaping (Result<[UniversalBleScanResult], Error>) -> Void) {
    var filterCBUUID = withServices.map { CBUUID(string: $0) }
    // We can't keep this filter empty, so adding a default filter
    if filterCBUUID.isEmpty { filterCBUUID.append(CBUUID(string: "1800")) }
    let bleDevices = manager.retrieveConnectedPeripherals(withServices: filterCBUUID)
    bleDevices.forEach { discoveredPeripherals[$0.uuid.uuidString] = $0 }
    completion(Result.success(bleDevices.map {
      UniversalBleScanResult(
        deviceId: $0.uuid.uuidString,
        name: $0.name ?? ""
      )
    }))
  }

  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    let state = central.state.toAvailabilityState().rawValue
    callbackChannel.onAvailabilityChanged(state: state) { _ in }

    bluetoothAvailabilityStateCallback?(Result.success(state))
  }

  public func centralManager(_: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
    discoveredPeripherals[peripheral.uuid.uuidString] = peripheral
    let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
    let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]
    callbackChannel.onScanResult(result: UniversalBleScanResult(
      deviceId: peripheral.uuid.uuidString,
      name: peripheral.name,
      isPaired: nil,
      rssi: RSSI as? Int64,
      manufacturerData: FlutterStandardTypedData(bytes: manufacturerData ?? Data()),
      services: services?.map { $0.uuidStr }
    )) { _ in }
  }

  public func centralManager(_: CBCentralManager, didConnect peripheral: CBPeripheral) {
    callbackChannel.onConnectionChanged(deviceId: peripheral.uuid.uuidString, state: BlueConnectionState.connected.rawValue) { _ in }
  }

  public func centralManager(_: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error _: Error?) {
    callbackChannel.onConnectionChanged(deviceId: peripheral.uuid.uuidString, state: BlueConnectionState.disconnected.rawValue) { _ in }
  }

  public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices _: Error?) {
    let deviceId = peripheral.identifier.uuidString
    guard let services = peripheral.services else {
      onServicesDiscovered(deviceId: deviceId, services: [])
      return
    }
    discoveredServicesProgressMap[deviceId] = services.map { UniversalBleService(uuid: $0.uuid.uuidString, characteristics: nil) }
    for service in services {
      peripheral.discoverCharacteristics(nil, for: service)
    }
  }

  public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error _: Error?) {
    let deviceId = peripheral.identifier.uuidString
    var universalBleCharacteristicsList: [UniversalBleCharacteristic] = []
    for characteristic in service.characteristics ?? [] {
      universalBleCharacteristicsList.append(
        UniversalBleCharacteristic(uuid: characteristic.uuid.uuidString, properties: characteristic.properties.toCharacteristicProperty))
    }
    // Update discoveredServicesProgressMap
    if let index = discoveredServicesProgressMap[deviceId]?.firstIndex(where: { $0.uuid == service.uuid.uuidString }) {
      discoveredServicesProgressMap[deviceId]?[index] = UniversalBleService(uuid: service.uuid.uuidString, characteristics: universalBleCharacteristicsList)
    }
    // Check if all services and their characteristics have been discovered
    if discoveredServicesProgressMap[deviceId]?.allSatisfy({ $0.characteristics != nil }) ?? false {
      onServicesDiscovered(deviceId: deviceId, services: discoveredServicesProgressMap[deviceId] ?? [])
      discoveredServicesProgressMap[deviceId] = nil
    }
  }

  public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
    print("peripheral:didWriteValueForCharacteristic \(characteristic.uuid.uuidStr) error: \(String(describing: error))")
    // Update futures for writeValue
    characteristicWriteFutures.removeAll { future in
      if future.deviceId == peripheral.uuid.uuidString && future.characteristicId == characteristic.uuid.uuidStr && future.serviceId == characteristic.service?.uuid.uuidStr {
        if let flutterError = error?.toFlutterError() {
          future.result(Result.failure(flutterError))
        } else {
          future.result(Result.success({}()))
        }
        return true
      }
      return false
    }
  }

  public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    // Update callbackChannel if notifying
    if characteristic.isNotifying {
      if let characteristicValue = characteristic.value {
        callbackChannel.onValueChanged(deviceId: peripheral.uuid.uuidString, characteristicId: characteristic.uuid.uuidStr, value: FlutterStandardTypedData(bytes: characteristicValue)) { _ in }
      }
    }

    if characteristicReadFutures.count == 0 {
      return
    }

    // Update futures for readValue
    characteristicReadFutures.removeAll { future in
      if future.deviceId == peripheral.uuid.uuidString && future.characteristicId == characteristic.uuid.uuidStr && future.serviceId == characteristic.service?.uuid.uuidStr {
        if let flutterError = error?.toFlutterError() {
          future.result(Result.failure(flutterError))
        } else {
          if let characteristicValue = characteristic.value {
            future.result(Result.success(FlutterStandardTypedData(bytes: characteristicValue)))
          } else {
            future.result(Result.failure(FlutterError(code: "ReadFailed", message: "No value", details: nil)))
          }
        }
        return true
      }
      return false
    }
  }
}

extension String {
  func getPeripheral() throws -> CBPeripheral {
    guard let peripheral = discoveredPeripherals[self] else {
      throw FlutterError(code: "IllegalArgument", message: "Unknown deviceId:\(self)", details: nil)
    }
    return peripheral
  }
}

extension FlutterError: Error {}
