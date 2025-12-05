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

// Cache last advertised local name for peripherals
// since iOS and MacOS don't do that for system devices
private var advertisementNameCache = [String: String]()

private class BleCentralDarwin: NSObject, UniversalBlePlatformChannel, CBCentralManagerDelegate, CBPeripheralDelegate {
  var callbackChannel: UniversalBleCallbackChannel
  private var universalBleFilterUtil = UniversalBleFilterUtil()
  private lazy var manager: CBCentralManager = .init(delegate: self, queue: nil)
  private var availabilityStateUpdateHandlers: [(Result<Int64, Error>) -> Void] = []
  private var requestPermissionStateUpdateHandlers: [(Result<Void, Error>) -> Void] = []
  private var activeServiceDiscoveries: [String: UniversalBleAsyncServiceDiscovery] = [:]
  private var characteristicReadFutures = [CharacteristicReadFuture]()
  private var characteristicWriteFutures = [CharacteristicWriteFuture]()
  private var characteristicWriteWithoutResponseFutures = [CharacteristicWriteFuture]()
  private var characteristicNotifyFutures = [CharacteristicNotifyFuture]()
  private var discoverServicesFutures = [DiscoverServicesFuture]()
  private var isManageScanning = false

  init(callbackChannel: UniversalBleCallbackChannel) {
    self.callbackChannel = callbackChannel
    super.init()
  }

  func getBluetoothAvailabilityState(completion: @escaping (Result<Int64, Error>) -> Void) {
    if manager.state != .unknown {
      completion(.success(manager.state.toAvailabilityState().rawValue))
    } else {
      availabilityStateUpdateHandlers.append(completion)
      _ = manager
    }
  }

  func requestPermissions(withAndroidFineLocation _: Bool, completion: @escaping (Result<Void, any Error>) -> Void) {
    if manager.state != .unknown {
      completePermissionRequest(completion: completion)
    } else {
      requestPermissionStateUpdateHandlers.append(completion)
      _ = manager
    }
  }

  func completePermissionRequest(completion: @escaping (Result<Void, any Error>) -> Void) {
    let state = manager.state
    switch state {
    case .unauthorized:
      completion(.failure(createFlutterError(code: .bluetoothUnauthorized, message: "Not authorized to access Bluetooth")))
    case .unsupported:
      completion(.failure(createFlutterError(code: .notSupported, message: "Bluetooth is not supported")))
    default:
      completion(.success(()))
    }
  }

  func enableBluetooth(completion: @escaping (Result<Bool, Error>) -> Void) {
    completion(Result.failure(createFlutterError(code: .notSupported)))
  }

  func disableBluetooth(completion: @escaping (Result<Bool, any Error>) -> Void) {
    completion(Result.failure(createFlutterError(code: .notSupported)))
  }

  func startScan(filter: UniversalScanFilter?) throws {
    // If filter has any other filter other than official one
    let usesCustomFilters = filter?.usesCustomFilters ?? false

    // Apply services filter
    var withServices: [CBUUID] = try filter?.withServices.compactMap { $0 }.toCBUUID() ?? []

    if usesCustomFilters {
      print("Using Custom Filters")
      universalBleFilterUtil.scanFilter = filter
      universalBleFilterUtil.scanFilterServicesUUID = withServices
      withServices = []
    } else {
      universalBleFilterUtil.scanFilter = nil
      universalBleFilterUtil.scanFilterServicesUUID = []
    }

    let options = [CBCentralManagerScanOptionAllowDuplicatesKey: true]

    manager.scanForPeripherals(withServices: withServices, options: options)
    isManageScanning = true
  }

  func stopScan() throws {
    manager.stopScan()
    isManageScanning = false
  }

  func isScanning() throws -> Bool {
    var hasAuthorization = true
    #if os(iOS)
      if #available(iOS 13.1, *) {
        hasAuthorization = CBCentralManager.authorization == .allowedAlways
      } else {
        return isManageScanning
      }
    #elseif os(macOS)
      hasAuthorization = CBCentralManager.authorization == .allowedAlways
    #endif

    if hasAuthorization {
      return manager.isScanning
    }

    return isManageScanning
  }

  func connect(deviceId: String) throws {
    let peripheral = try deviceId.getPeripheral(manager: manager)
    peripheral.delegate = self
    manager.connect(peripheral)
  }

  func disconnect(deviceId: String) throws {
    guard let peripheral = deviceId.findPeripheral(manager: manager) else {
      callbackChannel.onConnectionChanged(deviceId: deviceId, connected: false, error: nil) { _ in }
      return
    }
    if peripheral.state != CBPeripheralState.disconnected {
      manager.cancelPeripheralConnection(peripheral)
    }
    cleanUpConnection(deviceId: deviceId)
  }

  func getConnectionState(deviceId: String) throws -> Int64 {
    guard let peripheral = deviceId.findPeripheral(manager: manager) else {
      return BlueConnectionState.disconnected.rawValue
    }
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
      return BlueConnectionState.disconnected.rawValue
    }
  }

  func cleanUpConnection(deviceId: String) {
    characteristicReadFutures.removeAll { future in
      if future.deviceId == deviceId {
        future.result(
          Result.failure(createFlutterError(code: .deviceDisconnected, message: "Device Disconnected"))
        )
        return true
      }
      return false
    }
    characteristicWriteFutures.removeAll { future in
      if future.deviceId == deviceId {
        future.result(
          Result.failure(createFlutterError(code: .deviceDisconnected, message: "Device Disconnected"))
        )
        return true
      }
      return false
    }
    characteristicNotifyFutures.removeAll { future in
      if future.deviceId == deviceId {
        future.result(
          Result.failure(createFlutterError(code: .deviceDisconnected, message: "Device Disconnected"))
        )
        return true
      }
      return false
    }
    discoverServicesFutures.removeAll { future in
      if future.deviceId == deviceId {
        future.result(
          Result.failure(createFlutterError(code: .deviceDisconnected, message: "Device Disconnected"))
        )
        return true
      }
      return false
    }
    activeServiceDiscoveries[deviceId]?.cleanup()
    activeServiceDiscoveries[deviceId] = nil
  }

  func discoverServices(deviceId: String, completion: @escaping (Result<[UniversalBleService], Error>) -> Void) {
    guard let peripheral = deviceId.findPeripheral(manager: manager) else {
      completion(
        Result.failure(createFlutterError(code: .deviceNotFound, message: "Unknown deviceId:\(deviceId)"))
      )
      return
    }

    // Check if discovery is already in progress
    if activeServiceDiscoveries[deviceId] != nil {
      print("Services discovery already in progress for :\(deviceId), waiting for completion.")
      discoverServicesFutures.append(DiscoverServicesFuture(deviceId: deviceId, result: completion))
      return
    }

    let wrappedCompletion: (Result<[UniversalBleService], Error>) -> Void = { result in
      completion(result)
      self.discoverServicesFutures.removeAll { future in
        if future.deviceId == deviceId {
          future.result(result)
          return true
        }
        return false
      }
      self.activeServiceDiscoveries[deviceId] = nil
    }

    let discovery = UniversalBleAsyncServiceDiscovery(
      peripheral: peripheral,
      deviceId: deviceId,
      completion: wrappedCompletion
    )

    activeServiceDiscoveries[deviceId] = discovery
    discovery.startDiscovery()
  }

  func setNotifiable(deviceId: String, service: String, characteristic: String, bleInputProperty: Int64, completion: @escaping (Result<Void, any Error>) -> Void) {
    guard let peripheral = deviceId.findPeripheral(manager: manager) else {
      completion(Result.failure(createFlutterError(code: .deviceNotFound, message: "Unknown deviceId:\(deviceId)")))
      return
    }

    guard let gattCharacteristic = peripheral.getCharacteristic(characteristic, of: service) else {
      completion(Result.failure(createFlutterError(code: .characteristicNotFound, message: "Unknown characteristic:\(characteristic)")))
      return
    }

    if bleInputProperty == BleInputProperty.notification.rawValue && !gattCharacteristic.properties.contains(.notify) {
      completion(Result.failure(createFlutterError(code: .characteristicDoesNotSupportNotify, message: "Characteristic does not support notify")))
      return
    }

    if bleInputProperty == BleInputProperty.indication.rawValue && !gattCharacteristic.properties.contains(.indicate) {
      completion(Result.failure(createFlutterError(code: .characteristicDoesNotSupportIndicate, message: "Characteristic does not support indicate")))
      return
    }

    let shouldNotify = bleInputProperty != BleInputProperty.disabled.rawValue
    peripheral.setNotifyValue(shouldNotify, for: gattCharacteristic)
    characteristicNotifyFutures.append(CharacteristicNotifyFuture(deviceId: deviceId, characteristicId: gattCharacteristic.uuid.uuidStr, serviceId: gattCharacteristic.service?.uuid.uuidStr, result: completion))
  }

  func readValue(deviceId: String, service: String, characteristic: String, completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) {
    guard let peripheral = deviceId.findPeripheral(manager: manager) else {
      completion(Result.failure(createFlutterError(code: .deviceNotFound, message: "Unknown deviceId:\(self)")))
      return
    }
    guard let gattCharacteristic = peripheral.getCharacteristic(characteristic, of: service) else {
      completion(Result.failure(createFlutterError(code: .characteristicNotFound, message: "Unknown characteristic:\(characteristic)")))
      return
    }
    if !gattCharacteristic.properties.contains(.read) {
      completion(Result.failure(createFlutterError(code: .characteristicDoesNotSupportRead, message: "Characteristic does not support read")))
      return
    }
    peripheral.readValue(for: gattCharacteristic)
    characteristicReadFutures.append(CharacteristicReadFuture(deviceId: deviceId, characteristicId: gattCharacteristic.uuid.uuidStr, serviceId: gattCharacteristic.service?.uuid.uuidStr, result: completion))
  }

  func writeValue(deviceId: String, service: String, characteristic: String, value: FlutterStandardTypedData, bleOutputProperty: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
    guard let peripheral = deviceId.findPeripheral(manager: manager) else {
      completion(Result.failure(createFlutterError(code: .deviceNotFound, message: "Unknown deviceId:\(self)")))
      return
    }
    guard let gattCharacteristic = peripheral.getCharacteristic(characteristic, of: service) else {
      completion(Result.failure(createFlutterError(code: .characteristicNotFound, message: "Unknown characteristic:\(characteristic)")))
      return
    }

    let type = bleOutputProperty == BleOutputProperty.withoutResponse.rawValue ? CBCharacteristicWriteType.withoutResponse : CBCharacteristicWriteType.withResponse

    if type == CBCharacteristicWriteType.withResponse {
      if !gattCharacteristic.properties.contains(.write) {
        completion(Result.failure(createFlutterError(code: .characteristicDoesNotSupportWrite, message: "Characteristic does not support write withResponse")))
        return
      }
    } else if type == CBCharacteristicWriteType.withoutResponse {
      if !gattCharacteristic.properties.contains(.writeWithoutResponse) {
        completion(Result.failure(createFlutterError(code: .characteristicDoesNotSupportWriteWithoutResponse, message: "Characteristic does not support write withoutResponse")))
        return
      }
    }
    peripheral.writeValue(value.data, for: gattCharacteristic, type: type)

    // Wait for future response
    let future = CharacteristicWriteFuture(deviceId: deviceId, characteristicId: gattCharacteristic.uuid.uuidStr, serviceId: gattCharacteristic.service?.uuid.uuidStr, result: completion)
    if type == CBCharacteristicWriteType.withResponse {
      characteristicWriteFutures.append(future)
    } else {
      characteristicWriteWithoutResponseFutures.append(future)
    }
  }

  func requestMtu(deviceId: String, expectedMtu _: Int64, completion: @escaping (Result<Int64, Error>) -> Void) {
    guard let peripheral = deviceId.findPeripheral(manager: manager) else {
      completion(Result.failure(createFlutterError(code: .deviceNotFound, message: "Unknown deviceId:\(self)")))
      return
    }
    let mtu = peripheral.maximumWriteValueLength(for: CBCharacteristicWriteType.withoutResponse)
    let GATT_HEADER_LENGTH = 3
    let mtuResult = Int64(mtu + GATT_HEADER_LENGTH)
    completion(Result.success(mtuResult))
  }

  func isPaired(deviceId _: String, completion: @escaping (Result<Bool, Error>) -> Void) {
    completion(Result.failure(createFlutterError(code: .notSupported)))
  }

  func pair(deviceId _: String, completion: @escaping (Result<Bool, Error>) -> Void) {
    completion(Result.failure(createFlutterError(code: .notImplemented)))
  }

  func unPair(deviceId _: String) throws {
    throw createFlutterError(code: .notSupported)
  }

  func getSystemDevices(withServices: [String], completion: @escaping (Result<[UniversalBleScanResult], Error>) -> Void) {
    var servicesFilter = withServices
    if servicesFilter.isEmpty {
      print("No services filter was set for getting system connected devices. Using default services...")

      // Add several generic services
      servicesFilter = ["1800", "1801", "180A", "180D", "1810", "181B", "1808", "181D", "1816", "1814", "181A", "1802", "1803", "1804", "1815", "1805", "1807", "1806", "1848", "185E", "180F", "1812", "180E", "1813"]
    }
    let filterCBUUID = servicesFilter.map { CBUUID(string: $0) }
    let bleDevices = manager.retrieveConnectedPeripherals(withServices: filterCBUUID)
    bleDevices.forEach { $0.saveCache() }
    completion(Result.success(bleDevices.map { peripheral in
      let id = peripheral.uuid.uuidString
      let name = advertisementNameCache[id] ?? discoveredPeripherals[id]?.name ?? peripheral.name ?? ""
      return UniversalBleScanResult(
        deviceId: id,
        name: name
      )
    }))
  }

  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    let state = central.state.toAvailabilityState().rawValue
    callbackChannel.onAvailabilityChanged(state: state) { _ in }
    // Complete Pending state handler
    availabilityStateUpdateHandlers.removeAll { handler in
      handler(.success(state))
      return true
    }
    // Complete Pending permission request handler
    requestPermissionStateUpdateHandlers.removeAll { handler in
      completePermissionRequest(completion: handler)
      return true
    }
  }

  public func centralManager(_: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
    // Store the discovered peripheral using its UUID as the key
    peripheral.saveCache()

    // Extract manufacturer data and service UUIDs from the advertisement data
    let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
    let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])

    var manufacturerDataList: [UniversalManufacturerData] = []
    var universalManufacturerData: UniversalManufacturerData? = nil

    if let msd = manufacturerData, msd.count > 2 {
      let companyIdentifier = msd.prefix(2).withUnsafeBytes { $0.load(as: UInt16.self) }
      let data = FlutterStandardTypedData(bytes: msd.suffix(from: 2))
      universalManufacturerData = UniversalManufacturerData(companyIdentifier: Int64(companyIdentifier), data: data)
      manufacturerDataList.append(universalManufacturerData!)
    }

    let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
    let displayName = advertisedName ?? peripheral.name
    advertisementNameCache[peripheral.uuid.uuidString] = displayName

    // Apply custom filters and return early if the peripheral doesn't match
    if !universalBleFilterUtil.filterDevice(name: displayName, manufacturerData: universalManufacturerData, services: services) {
      return
    }

    callbackChannel.onScanResult(result: UniversalBleScanResult(
      deviceId: peripheral.uuid.uuidString,
      name: displayName,
      isPaired: nil,
      rssi: RSSI as? Int64,
      manufacturerDataList: manufacturerDataList,
      services: services?.map { $0.uuidStr }
    )) { _ in }
  }

  public func centralManager(_: CBCentralManager, didConnect peripheral: CBPeripheral) {
    callbackChannel.onConnectionChanged(deviceId: peripheral.uuid.uuidString, connected: true, error: nil) { _ in }
  }

  public func centralManager(_: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error _: Error?) {
    callbackChannel.onConnectionChanged(deviceId: peripheral.uuid.uuidString, connected: false, error: nil) { _ in }
    cleanUpConnection(deviceId: peripheral.uuid.uuidString)
  }

  public func centralManager(_: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
    callbackChannel.onConnectionChanged(deviceId: peripheral.uuid.uuidString, connected: false, error: error?.localizedDescription) { _ in }
    cleanUpConnection(deviceId: peripheral.uuid.uuidString)
  }

  public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    activeServiceDiscoveries[peripheral.identifier.uuidString]?.handleDidDiscoverServices(peripheral, error: error)
  }

  public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    activeServiceDiscoveries[peripheral.identifier.uuidString]?.handleDidDiscoverCharacteristicsFor(peripheral, service: service, error: error)
  }

  public func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
    activeServiceDiscoveries[peripheral.identifier.uuidString]?.handleDidDiscoverDescriptorsFor(peripheral, characteristic: characteristic, error: error)
  }

  public func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
    characteristicWriteWithoutResponseFutures.removeAll { future in
      if future.deviceId == peripheral.uuid.uuidString {
        future.result(Result.success({}()))
        return true
      }
      return false
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
            future.result(Result.failure(createFlutterError(code: .readFailed, message: "No value")))
          }
        }
        return true
      }
      return false
    }
  }
}

extension CBPeripheral {
  func saveCache() {
    discoveredPeripherals[uuid.uuidString] = self
  }
}

extension String {
  func getPeripheral(manager: CBCentralManager) throws -> CBPeripheral {
    guard let peripheral = findPeripheral(manager: manager) else {
      throw createFlutterError(code: .deviceNotFound, message: "Unknown deviceId:\(self)")
    }
    return peripheral
  }

  func findPeripheral(manager: CBCentralManager) -> CBPeripheral? {
    if let peripheral = discoveredPeripherals[self] {
      return peripheral
    }
    if let uuid = UUID(uuidString: self) {
      let peripherals = manager.retrievePeripherals(withIdentifiers: [uuid])
      if let peripheral = peripherals.first {
        return peripheral
      }
    }
    return nil
  }
}

extension [String] {
  func toCBUUID() throws -> [CBUUID] {
    return try compactMap { serviceUUID in
      guard UUID(uuidString: serviceUUID) != nil else {
        throw createFlutterError(code: .invalidServiceUuid, message: "Invalid service UUID:\(serviceUUID)")
      }
      return CBUUID(string: serviceUUID)
    }
  }
}
