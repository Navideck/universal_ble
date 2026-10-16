#if os(iOS)
  import Flutter
#elseif os(macOS)
  import Cocoa
  import FlutterMacOS
#endif
import CoreBluetooth
import Foundation

final class UniversalBlePeripheralPlugin: NSObject, UniversalBlePeripheralChannel,
  CBPeripheralManagerDelegate, DartCallbackSender
{
  let callbackChannel: UniversalBlePeripheralCallback
  private var advertisingState: PeripheralAdvertisingState = .idle
  private var peripheralManager: CBPeripheralManager?
  private let centralsLock = NSLock()
  private var centralsById = [String: CBCentral]()
  private var centralCharacteristicSubscriptions = [String: Set<String>]()
  // Per plugin instance (one per FlutterEngine): the services this peripheral
  // advertises. Tearing one engine down (or clearing its services) must not wipe
  // another engine's advertising state.
  private let serviceRegistry = PeripheralServiceRegistry()

  /// How long to wait for a Dart reply to a peripheral read/write request before
  /// answering the central with a failure, so a dropped reply cannot pin the
  /// CoreBluetooth request open indefinitely.
  private static let peripheralRequestTimeout: TimeInterval = 10

  init(callbackChannel: UniversalBlePeripheralCallback) {
    self.callbackChannel = callbackChannel
    super.init()
  }

  deinit {
    peripheralManager?.stopAdvertising()
    peripheralManager?.removeAllServices()
    clearCentrals()
  }

  private func ensurePeripheralManager() -> CBPeripheralManager {
    if let peripheralManager {
      return peripheralManager
    }
    let manager = CBPeripheralManager(delegate: self, queue: nil, options: nil)
    peripheralManager = manager
    return manager
  }

  func getAdvertisingState() throws -> PeripheralAdvertisingState {
    if let peripheralManager {
      if peripheralManager.isAdvertising {
        if advertisingState == .idle {
          advertisingState = .advertising
        }
      } else if advertisingState == .advertising {
        advertisingState = .idle
      } else {
        completeStopIfNeeded()
      }
    }
    return advertisingState
  }

  private func completeStopIfNeeded() {
    guard advertisingState == .stopping else { return }
    advertisingState = .idle
    sendToDart { try await $0.onAdvertisingStateChange(state: .idle, error: nil) }
  }

  func getReadinessState() throws -> PeripheralReadinessState {
    switch ensurePeripheralManager().state {
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
    sendToDart { try await $0.onAdvertisingStateChange(state: .stopping, error: nil) }
    guard let peripheralManager else {
      completeStopIfNeeded()
      return
    }
    peripheralManager.stopAdvertising()
    if !peripheralManager.isAdvertising {
      completeStopIfNeeded()
    }
  }

  func addService(service: PeripheralService) throws {
    let cbService = service.toCBService()
    serviceRegistry.register(cbService)
    ensurePeripheralManager().add(cbService)
  }

  func removeService(serviceId: String) throws {
    if let service = serviceRegistry.service(serviceId) {
      ensurePeripheralManager().remove(service)
      serviceRegistry.remove(service)
    }
  }

  func clearServices() throws {
    peripheralManager?.removeAllServices()
    serviceRegistry.clear()
  }

  func getServices() throws -> [String] {
    serviceRegistry.serviceIds
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
    sendToDart { try await $0.onAdvertisingStateChange(state: .starting, error: nil) }
    ensurePeripheralManager().startAdvertising(advertisementData)
  }

  func updateCharacteristic(
    characteristicId: String,
    value: FlutterStandardTypedData,
    deviceId: String?
  ) throws {
    guard let characteristic = serviceRegistry.characteristic(characteristicId) else {
      throw UniversalBlePeripheralError.notFound("\(characteristicId) characteristic not found")
    }
    let centrals: [CBCentral]?
    if let deviceId {
      guard let central = central(for: deviceId) else {
        throw UniversalBlePeripheralError.notFound("\(deviceId) device not found")
      }
      centrals = [central]
    } else {
      centrals = nil
    }
    let success = ensurePeripheralManager().updateValue(
      value.toData(),
      for: characteristic,
      onSubscribedCentrals: centrals
    )
    if !success {
      throw UniversalBlePeripheralError.failed("Peripheral transmit queue full")
    }
  }

  nonisolated func peripheralManagerDidStartAdvertising(
    _: CBPeripheralManager,
    error: Error?
  ) {
    let state: PeripheralAdvertisingState = error == nil ? .advertising : .error
    advertisingState = state
    sendToDart { try await $0.onAdvertisingStateChange(
        state: state,
        error: error?.localizedDescription
      )
    }
  }

  nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    if peripheral.state != .poweredOn {
      advertisingState = .idle
      sendToDart { try await $0.onAdvertisingStateChange(state: .idle, error: nil) }
    }
  }

  nonisolated func peripheralManager(
    _: CBPeripheralManager,
    didAdd service: CBService,
    error: Error?
  ) {
    sendToDart { try await $0.onServiceAdded(
        serviceId: service.uuid.uuidString,
        error: error?.localizedDescription
      )
    }
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
    sendToDart { try await $0.onCharacteristicSubscriptionChange(
        deviceId: central.identifier.uuidString,
        characteristicId: characteristic.uuid.uuidString,
        isSubscribed: true,
        name: nil
      )
    }
    sendToDart { try await $0.onMtuChange(
        deviceId: central.identifier.uuidString,
        mtu: Int64(central.maximumUpdateValueLength)
      )
    }
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
    sendToDart { try await $0.onCharacteristicSubscriptionChange(
        deviceId: central.identifier.uuidString,
        characteristicId: characteristic.uuid.uuidString,
        isSubscribed: false,
        name: nil
      )
    }
  }

  nonisolated func peripheralManager(
    _ peripheral: CBPeripheralManager,
    didReceiveRead request: CBATTRequest
  ) {
    Task { @MainActor in
      var responded = false
      // CoreBluetooth holds the request open until we respond; a Dart reply that
      // never arrives must not pin it (and the connection) forever.
      let timeout = DispatchWorkItem {
        guard !responded else { return }
        responded = true
        peripheral.respond(to: request, withResult: .requestNotSupported)
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + Self.peripheralRequestTimeout, execute: timeout)
      defer { timeout.cancel() }

      do {
        let result = try await callbackChannel.onReadRequest(
          deviceId: request.central.identifier.uuidString,
          characteristicId: request.characteristic.uuid.uuidString,
          offset: Int64(request.offset),
          value: request.value?.toFlutterBytes()
        )
        guard !responded else { return }
        responded = true
        let status = result?.status?.toCBATTErrorCode() ?? .success
        guard status == .success else {
          peripheral.respond(to: request, withResult: status)
          return
        }
        guard let fullData = result?.value.toData() as Data? else {
          peripheral.respond(to: request, withResult: .requestNotSupported)
          return
        }
        let offset = Int(request.offset)
        guard offset <= fullData.count else {
          peripheral.respond(to: request, withResult: .invalidOffset)
          return
        }
        let sliced = fullData.subdata(in: offset..<fullData.count)
        request.value = sliced
        peripheral.respond(to: request, withResult: .success)
      } catch {
        UniversalBleLogger.shared.logError("Peripheral read request failed: \(error)")
        guard !responded else { return }
        responded = true
        peripheral.respond(to: request, withResult: .requestNotSupported)
      }
    }
  }

  nonisolated func peripheralManager(
    _ peripheral: CBPeripheralManager,
    didReceiveWrite requests: [CBATTRequest]
  ) {
    requests.forEach { req in
      Task { @MainActor in
        var responded = false
        let timeout = DispatchWorkItem {
          guard !responded else { return }
          responded = true
          peripheral.respond(to: req, withResult: .requestNotSupported)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.peripheralRequestTimeout, execute: timeout)
        defer { timeout.cancel() }

        do {
          let response = try await callbackChannel.onWriteRequest(
            deviceId: req.central.identifier.uuidString,
            characteristicId: req.characteristic.uuid.uuidString,
            offset: Int64(req.offset),
            value: req.value?.toFlutterBytes()
          )
          guard !responded else { return }
          responded = true
          let status = response?.status?.toCBATTErrorCode() ?? .success
          peripheral.respond(to: req, withResult: status)
        } catch {
          UniversalBleLogger.shared.logError("Peripheral write request failed: \(error)")
          guard !responded else { return }
          responded = true
          peripheral.respond(to: req, withResult: .requestNotSupported)
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
    let central = centralsById[id] ?? centralsById[id.uppercased()] ?? centralsById[id.lowercased()]
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

/// Services this peripheral advertises, and the characteristics they expose.
/// Ownership is per plugin instance (one per FlutterEngine), so registering or
/// clearing here never touches another engine's advertised state. Characteristics
/// are always derived from the currently registered services, so a replaced,
/// removed, or cleared service cannot be updated through a stale characteristic,
/// and removing one service never drops a characteristic another service still
/// exposes.
private final class PeripheralServiceRegistry {
  private var services = [CBMutableService]()

  func register(_ service: CBMutableService) {
    services.removeAll {
      $0.uuid.uuidString.lowercased() == service.uuid.uuidString.lowercased()
    }
    services.append(service)
  }

  func remove(_ service: CBMutableService) {
    services.removeAll {
      $0.uuid.uuidString.lowercased() == service.uuid.uuidString.lowercased()
    }
  }

  func clear() {
    services.removeAll()
  }

  func service(_ serviceId: String) -> CBMutableService? {
    let target = serviceId.lowercased()
    return services.first { $0.uuid.uuidString.lowercased() == target }
  }

  func characteristic(_ characteristicId: String) -> CBMutableCharacteristic? {
    let target = characteristicId.lowercased()
    for service in services {
      for case let characteristic as CBMutableCharacteristic in service.characteristics ?? [] {
        if characteristic.uuid.uuidString.lowercased() == target {
          return characteristic
        }
      }
    }
    return nil
  }

  var serviceIds: [String] { services.map { $0.uuid.uuidString } }
}
