#if os(iOS)
  import Flutter
#elseif os(macOS)
  import Cocoa
  import FlutterMacOS
#endif
import CoreBluetooth
import Foundation

final class UniversalBlePeripheralPlugin: NSObject, UniversalBlePeripheralChannel,
  CBPeripheralManagerDelegate
{
  private let callbackChannel: UniversalBlePeripheralCallback
  private var advertisingState: PeripheralAdvertisingState = .idle
  private lazy var peripheralManager: CBPeripheralManager =
    .init(delegate: self, queue: nil, options: nil)
  private let centralsLock = NSLock()
  private var centralsById = [String: CBCentral]()
  private var centralCharacteristicSubscriptions = [String: Set<String>]()

  init(callbackChannel: UniversalBlePeripheralCallback) {
    self.callbackChannel = callbackChannel
    super.init()
    _ = peripheralManager.isAdvertising
  }

  deinit {
    peripheralManager.stopAdvertising()
    peripheralManager.removeAllServices()
    clearPeripheralCaches()
    clearCentrals()
  }

  func getAdvertisingState() throws -> PeripheralAdvertisingState {
    advertisingState
  }

  func getReadinessState() throws -> PeripheralReadinessState {
    switch peripheralManager.state {
    case .poweredOn:
      return .ready
    case .poweredOff:
      return .bluetoothOff
    case .unauthorized:
      return .unauthorized
    case .unsupported:
      return .unsupported
    case .unknown, .resetting:
      return .unknown
    @unknown default:
      return .unknown
    }
  }

  func stopAdvertising() throws {
    advertisingState = .stopping
    callbackChannel.onAdvertisingStateChange(state: .stopping, error: nil) { _ in }
    peripheralManager.stopAdvertising()
    advertisingState = .idle
    callbackChannel.onAdvertisingStateChange(state: .idle, error: nil) { _ in }
  }

  func addService(service: PeripheralService) throws {
    peripheralManager.add(service.toCBService())
  }

  func removeService(serviceId: String) throws {
    if let service = serviceId.findPeripheralService() {
      peripheralManager.remove(service)
      peripheralServicesList.removeAll {
        $0.uuid.uuidString.lowercased() == service.uuid.uuidString.lowercased()
      }
    }
  }

  func clearServices() throws {
    peripheralManager.removeAllServices()
    peripheralServicesList.removeAll()
  }

  func getServices() throws -> [String] {
    peripheralServicesList.map { $0.uuid.uuidString }
  }

  func startAdvertising(
    services: [String],
    localName: String?,
    timeout: Int64?,
    manufacturerData: UniversalManufacturerData?,
    platformConfig: PeripheralPlatformConfig?
  ) throws {
    if let timeout, timeout > 0 {
      throw NSError(
        domain: "UniversalBlePeripheral",
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: "Advertising timeout is not supported on Darwin."]
      )
    }
    let cbServices = services.map { CBUUID(string: $0) }
    var advertisementData: [String: Any] = [CBAdvertisementDataServiceUUIDsKey: cbServices]
    if let localName {
      advertisementData[CBAdvertisementDataLocalNameKey] = localName
    }
    if let manufacturerData {
      // CoreBluetooth expects the full AD manufacturer field: company ID (LE uint16)
      // followed by payload. Dart's `ManufacturerData` keeps id and payload separate.
      let companyId = UInt16(truncatingIfNeeded: manufacturerData.companyIdentifier)
      var manufacturerField = Data()
      manufacturerField.append(UInt8(companyId & 0x00ff))
      manufacturerField.append(UInt8((companyId >> 8) & 0x00ff))
      manufacturerField.append(manufacturerData.data.data)
      advertisementData[CBAdvertisementDataManufacturerDataKey] = manufacturerField
    }
    advertisingState = .starting
    callbackChannel.onAdvertisingStateChange(state: .starting, error: nil) { _ in }
    peripheralManager.startAdvertising(advertisementData)
  }

  func updateCharacteristic(
    characteristicId: String,
    value: FlutterStandardTypedData,
    deviceId: String?
  ) throws {
    guard let characteristic = characteristicId.findPeripheralCharacteristic() else {
      throw UniversalBlePeripheralError.notFound("\(characteristicId) characteristic not found")
    }
    if let deviceId {
      guard let central = central(for: deviceId) else {
        throw UniversalBlePeripheralError.notFound("\(deviceId) device not found")
      }
      peripheralManager.updateValue(
        value.toData(),
        for: characteristic,
        onSubscribedCentrals: [central]
      )
    } else {
      peripheralManager.updateValue(value.toData(), for: characteristic, onSubscribedCentrals: nil)
    }
  }

  nonisolated func peripheralManagerDidStartAdvertising(
    _: CBPeripheralManager,
    error: Error?
  ) {
    advertisingState = error == nil ? .advertising : .error
    callbackChannel.onAdvertisingStateChange(
      state: advertisingState,
      error: error?.localizedDescription
    ) { _ in }
  }

  nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    if peripheral.state != .poweredOn {
      advertisingState = .idle
      callbackChannel.onAdvertisingStateChange(state: .idle, error: nil) { _ in }
    }
  }

  nonisolated func peripheralManager(
    _: CBPeripheralManager,
    didAdd service: CBService,
    error: Error?
  ) {
    callbackChannel.onServiceAdded(
      serviceId: service.uuid.uuidString,
      error: error?.localizedDescription
    ) { _ in }
  }

  nonisolated func peripheralManager(
    _: CBPeripheralManager,
    central: CBCentral,
    didSubscribeTo characteristic: CBCharacteristic
  ) {
    upsertCentralSubscription(
      central: central,
      characteristicId: characteristic.uuid.uuidString
    )
    callbackChannel.onCharacteristicSubscriptionChange(
      deviceId: central.identifier.uuidString,
      characteristicId: characteristic.uuid.uuidString,
      isSubscribed: true,
      name: nil
    ) { _ in }
    callbackChannel.onMtuChange(
      deviceId: central.identifier.uuidString,
      mtu: Int64(central.maximumUpdateValueLength)
    ) { _ in }
  }

  nonisolated func peripheralManager(
    _: CBPeripheralManager,
    central: CBCentral,
    didUnsubscribeFrom characteristic: CBCharacteristic
  ) {
    removeCentralSubscription(
      centralId: central.identifier.uuidString,
      characteristicId: characteristic.uuid.uuidString
    )
    callbackChannel.onCharacteristicSubscriptionChange(
      deviceId: central.identifier.uuidString,
      characteristicId: characteristic.uuid.uuidString,
      isSubscribed: false,
      name: nil
    ) { _ in }
  }

  nonisolated func peripheralManager(
    _: CBPeripheralManager,
    didReceiveRead request: CBATTRequest
  ) {
    callbackChannel.onReadRequest(
      deviceId: request.central.identifier.uuidString,
      characteristicId: request.characteristic.uuid.uuidString,
      offset: Int64(request.offset),
      value: request.value?.toFlutterBytes()
    ) { readReq in
      do {
        let result = try readReq.get()
        let status = result?.status?.toCBATTErrorCode() ?? .success
        guard status == .success else {
          self.peripheralManager.respond(to: request, withResult: status)
          return
        }
        guard let fullData = result?.value.toData() as Data? else {
          self.peripheralManager.respond(to: request, withResult: .requestNotSupported)
          return
        }
        let offset = Int(request.offset)
        guard offset <= fullData.count else {
          self.peripheralManager.respond(to: request, withResult: .invalidOffset)
          return
        }
        let sliced = fullData.subdata(in: offset..<fullData.count)
        request.value = sliced
        self.peripheralManager.respond(to: request, withResult: .success)
      } catch {
        self.peripheralManager.respond(to: request, withResult: .requestNotSupported)
      }
    }
  }

  nonisolated func peripheralManager(
    _: CBPeripheralManager,
    didReceiveWrite requests: [CBATTRequest]
  ) {
    requests.forEach { req in
      callbackChannel.onWriteRequest(
        deviceId: req.central.identifier.uuidString,
        characteristicId: req.characteristic.uuid.uuidString,
        offset: Int64(req.offset),
        value: req.value?.toFlutterBytes()
      ) { writeRes in
        do {
          let response = try writeRes.get()
          let status = response?.status?.toCBATTErrorCode() ?? .success
          self.peripheralManager.respond(to: req, withResult: status)
        } catch {
          self.peripheralManager.respond(to: req, withResult: .requestNotSupported)
        }
      }
    }
  }

  private func upsertCentralSubscription(
    central: CBCentral,
    characteristicId: String
  ) {
    let centralId = central.identifier.uuidString
    centralsLock.lock()
    centralsById[centralId] = central
    var subscriptions = centralCharacteristicSubscriptions[centralId] ?? Set<String>()
    subscriptions.insert(characteristicId)
    centralCharacteristicSubscriptions[centralId] = subscriptions
    centralsLock.unlock()
  }

  private func removeCentralSubscription(centralId: String, characteristicId: String) {
    centralsLock.lock()
    var subscriptions = centralCharacteristicSubscriptions[centralId] ?? Set<String>()
    subscriptions.remove(characteristicId)
    if subscriptions.isEmpty {
      centralCharacteristicSubscriptions.removeValue(forKey: centralId)
      centralsById.removeValue(forKey: centralId)
    } else {
      centralCharacteristicSubscriptions[centralId] = subscriptions
    }
    centralsLock.unlock()
  }

  private func central(for id: String) -> CBCentral? {
    centralsLock.lock()
    let central = centralsById[id]
    centralsLock.unlock()
    return central
  }

  private func clearCentrals() {
    centralsLock.lock()
    centralsById.removeAll()
    centralCharacteristicSubscriptions.removeAll()
    centralsLock.unlock()
  }

  func getSubscribedClients(characteristicId: String) throws -> [String] {
    let target = characteristicId.uppercased()
    centralsLock.lock()
    defer { centralsLock.unlock() }
    return centralCharacteristicSubscriptions.compactMap { centralId, chars in
      chars.contains(where: { $0.uppercased() == target }) ? centralId : nil
    }
  }

  func getMaximumNotifyLength(deviceId: String) throws -> Int64? {
    guard let central = central(for: deviceId) else {
      return nil
    }
    return Int64(central.maximumUpdateValueLength)
  }
}
