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
  private var scanFilter: UniversalScanFilter? = nil
  private var discoveredServicesProgressMap: [String: [UniversalBleService]] = [:]
  private var characteristicReadFutures = [CharacteristicReadFuture]()
  private var characteristicWriteFutures = [CharacteristicWriteFuture]()
  private var characteristicNotifyFutures = [CharacteristicNotifyFuture]()
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

    // Save scanFilter for later user
    scanFilter = filter

    let options = [CBCentralManagerScanOptionAllowDuplicatesKey: true]
    manager.scanForPeripherals(withServices: withServices, options: options)
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

  func getConnectionState(deviceId: String) throws -> Int64 {
    let peripheral = try deviceId.getPeripheral()
    switch peripheral.state {
    case .connecting:
      return BlueConnectionState.connecting.rawValue
    case .connected:
      return BlueConnectionState.connected.rawValue
    case .disconnecting:
      return BlueConnectionState.disconnecting.rawValue
    case .disconnected:
      return BlueConnectionState.disconnected.rawValue
    @unknown default:
      fatalError()
    }
  }

  func cleanUpConnection(deviceId: String) {
    characteristicReadFutures.removeAll { future in
      if future.deviceId == deviceId {
        future.result(
          Result.failure(FlutterError(code: "DeviceDisconnected", message: "Device Disconnected", details: nil))
        )
        return true
      }
      return false
    }
    characteristicWriteFutures.removeAll { future in
      if future.deviceId == deviceId {
        future.result(
          Result.failure(FlutterError(code: "DeviceDisconnected", message: "Device Disconnected", details: nil))
        )
        return true
      }
      return false
    }
    characteristicNotifyFutures.removeAll { future in
      if future.deviceId == deviceId {
        future.result(
          Result.failure(FlutterError(code: "DeviceDisconnected", message: "Device Disconnected", details: nil))
        )
        return true
      }
      return false
    }
    discoverServicesFutures.removeAll { future in
      if future.deviceId == deviceId {
        future.result(
          Result.failure(FlutterError(code: "DeviceDisconnected", message: "Device Disconnected", details: nil))
        )
        return true
      }
      return false
    }
    discoveredServicesProgressMap[deviceId] = nil
  }

  func discoverServices(deviceId: String, completion: @escaping (Result<[UniversalBleService], Error>) -> Void) {
    guard let peripheral = discoveredPeripherals[deviceId] else {
      completion(
        Result.failure(FlutterError(code: "IllegalArgument", message: "Unknown deviceId:\(self)", details: nil))
      )
      return
    }

    if discoveredServicesProgressMap[deviceId] != nil {
      print("Services discovery already in progress for :\(deviceId), waiting for completion.")
      discoverServicesFutures.append(DiscoverServicesFuture(deviceId: deviceId, result: completion))
      return
    }

    if let cachedServices = peripheral.services {
      // If services already discovered no need to discover again
      if !cachedServices.isEmpty {
        // print("Services already cached for this peripheral")
        discoverServicesFutures.append(DiscoverServicesFuture(deviceId: deviceId, result: completion))
        self.peripheral(peripheral, didDiscoverServices: nil)
        return
      }
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

  func setNotifiable(deviceId: String, service: String, characteristic: String, bleInputProperty: Int64, completion: @escaping (Result<Void, any Error>) -> Void) {
    guard let peripheral = discoveredPeripherals[deviceId] else {
      completion(Result.failure(FlutterError(code: "IllegalArgument", message: "Unknown deviceId:\(self)", details: nil)))
      return
    }

    guard let gattCharacteristic = peripheral.getCharacteristic(characteristic, of: service) else {
      completion(Result.failure(FlutterError(code: "IllegalArgument", message: "Unknown characteristic:\(characteristic)", details: nil)))
      return
    }

    if bleInputProperty == BleInputProperty.notification.rawValue && !gattCharacteristic.properties.contains(.notify) {
      completion(Result.failure(FlutterError(code: "InvalidAction", message: "Characteristic does not support notify", details: nil)))
      return
    }

    if bleInputProperty == BleInputProperty.indication.rawValue && !gattCharacteristic.properties.contains(.indicate) {
      completion(Result.failure(FlutterError(code: "InvalidAction", message: "Characteristic does not support indicate", details: nil)))
      return
    }

    let shouldNotify = bleInputProperty != BleInputProperty.disabled.rawValue
    peripheral.setNotifyValue(shouldNotify, for: gattCharacteristic)
    characteristicNotifyFutures.append(CharacteristicNotifyFuture(deviceId: deviceId, characteristicId: gattCharacteristic.uuid.uuidStr, serviceId: gattCharacteristic.service?.uuid.uuidStr, result: completion))
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
    
  func getPairedDevices() throws -> [UniversalBleScanResult] {
    throw FlutterError(code: "NotSupported", message: nil, details: nil)
  }
    
  func getSystemDevices(withServices: [String], completion: @escaping (Result<[UniversalBleScanResult], Error>) -> Void) {
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

    // Handle ScanFilters
    if let filter = scanFilter {
      let manufacturerFilter = filter.withManufacturerData.compactMap { $0 }
      // If scan filters are not empty, check if manufacturer data matches filters
      if !manufacturerFilter.isEmpty, !isManufacturerDataMatchingFilters(filters: manufacturerFilter, msd: manufacturerData) {
        return
      }
    }

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
    callbackChannel.onConnectionChanged(deviceId: peripheral.uuid.uuidString, connected: true) { _ in }
  }

  public func centralManager(_: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error _: Error?) {
    callbackChannel.onConnectionChanged(deviceId: peripheral.uuid.uuidString, connected: false) { _ in }
    // Cleanup on disconnect
    cleanUpConnection(deviceId: peripheral.uuid.uuidString)
  }

  public func centralManager(_: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
    print("Failed to connect: \(peripheral.uuid.uuidString): \(String(describing: error))")
  }

  public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices _: Error?) {
    let deviceId = peripheral.identifier.uuidString
    guard let services = peripheral.services else {
      onServicesDiscovered(deviceId: deviceId, services: [])
      return
    }
    discoveredServicesProgressMap[deviceId] = services.map { UniversalBleService(uuid: $0.uuid.uuidString, characteristics: nil) }
    for service in services {
      if let cachedChar = service.characteristics {
        if !cachedChar.isEmpty {
          self.peripheral(peripheral, didDiscoverCharacteristicsFor: service, error: nil)
          continue
        }
      }
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

  public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
    characteristicNotifyFutures.removeAll { future in
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
