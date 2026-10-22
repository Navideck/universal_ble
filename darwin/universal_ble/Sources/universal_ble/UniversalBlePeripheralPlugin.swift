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
  private var peripheralManager: CBPeripheralManager?
  private let centralsLock = NSLock()
  private var centralsById = [String: CBCentral]()
  private var centralCharacteristicSubscriptions = [String: Set<String>]()
  private let pendingNotificationsLock = NSLock()
  private var pendingNotifications = [PendingNotification]()
  // Per plugin instance (one per FlutterEngine): the services this peripheral
  // advertises. Tearing one engine down (or clearing its services) must not wipe
  // another engine's advertising state.
  private let serviceRegistry = PeripheralServiceRegistry()

  private struct PendingNotification {
    let value: Data
    let characteristic: CBMutableCharacteristic
    let centrals: [CBCentral]?
    let instanceId: String?
  }

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
    callbackChannel.onAdvertisingStateChange(state: .idle, error: nil) { _ in }
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
    callbackChannel.onAdvertisingStateChange(state: .stopping, error: nil) { _ in }
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
    serviceRegistry.register(
      cbService,
      modelCharacteristics: service.characteristics,
      mutableCharacteristics: cbService.characteristics ?? []
    )
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
    callbackChannel.onAdvertisingStateChange(state: .starting, error: nil) { _ in }
    ensurePeripheralManager().startAdvertising(advertisementData)
  }

  func updateCharacteristic(
    characteristicId: String,
    characteristicInstanceId: String?,
    value: FlutterStandardTypedData,
    deviceId: String?
  ) throws {
    guard
      let characteristic = serviceRegistry.characteristic(
        characteristicId,
        instanceId: characteristicInstanceId
      )
    else {
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
    let data = value.toData()
    let success = ensurePeripheralManager().updateValue(
      data,
      for: characteristic,
      onSubscribedCentrals: centrals
    )
    if !success {
      // CoreBluetooth reports a full transmit queue through the delegate; keep
      // the payloads FIFO so a HID release can never overtake its press.
      pendingNotificationsLock.lock()
      pendingNotifications.append(
        PendingNotification(
          value: data,
          characteristic: characteristic,
          centrals: centrals,
          instanceId: serviceRegistry.instanceId(of: characteristic)
        )
      )
      pendingNotificationsLock.unlock()
    }
  }

  private func drainPendingNotifications() {
    pendingNotificationsLock.lock()
    let queued = pendingNotifications
    pendingNotifications.removeAll()
    pendingNotificationsLock.unlock()
    var remaining = [PendingNotification]()
    for (index, notification) in queued.enumerated() {
      let success = ensurePeripheralManager().updateValue(
        notification.value,
        for: notification.characteristic,
        onSubscribedCentrals: notification.centrals
      )
      if !success {
        remaining.append(contentsOf: queued[index...])
        break
      }
    }
    if !remaining.isEmpty {
      pendingNotificationsLock.lock()
      pendingNotifications.insert(contentsOf: remaining, at: 0)
      pendingNotificationsLock.unlock()
    }
  }

  nonisolated func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
    drainPendingNotifications()
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
    let instanceId = serviceRegistry.instanceId(of: characteristic)
    upsertCentralSubscription(
      central: central,
      subscriptionId: instanceId ?? characteristic.uuid.uuidString
    )
    callbackChannel.onCharacteristicSubscriptionChange(
      deviceId: central.identifier.uuidString,
      characteristicId: characteristic.uuid.uuidString,
      characteristicInstanceId: instanceId,
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
    let instanceId = serviceRegistry.instanceId(of: characteristic)
    removeCentralSubscription(
      centralId: central.identifier.uuidString,
      subscriptionId: instanceId ?? characteristic.uuid.uuidString
    )
    callbackChannel.onCharacteristicSubscriptionChange(
      deviceId: central.identifier.uuidString,
      characteristicId: characteristic.uuid.uuidString,
      characteristicInstanceId: instanceId,
      isSubscribed: false,
      name: nil
    ) { _ in }
  }

  nonisolated func peripheralManager(
    _ peripheral: CBPeripheralManager,
    didReceiveRead request: CBATTRequest
  ) {
    callbackChannel.onReadRequest(
      deviceId: request.central.identifier.uuidString,
      characteristicId: request.characteristic.uuid.uuidString,
      characteristicInstanceId: serviceRegistry.instanceId(of: request.characteristic),
      offset: Int64(request.offset),
      value: request.value?.toFlutterBytes()
    ) { readReq in
      do {
        let result = try readReq.get()
        let status = result?.status?.toCBATTErrorCode() ?? .success
        guard status == .success else {
          peripheral.respond(to: request, withResult: status)
          return
        }
        // No handler, or a handler without data: serve the configured value so
        // static characteristics do not depend on an app-side read handler.
        let fullData: Data?
        if let result {
          fullData = result.value.toData()
        } else {
          fullData = request.characteristic.value
        }
        guard let fullData else {
          peripheral.respond(to: request, withResult: .requestNotSupported)
          return
        }
        let offset = Int(request.offset)
        guard offset <= fullData.count else {
          peripheral.respond(to: request, withResult: .invalidOffset)
          return
        }
        request.value = fullData.subdata(in: offset..<fullData.count)
        peripheral.respond(to: request, withResult: .success)
      } catch {
        peripheral.respond(to: request, withResult: .requestNotSupported)
      }
    }
  }

  nonisolated func peripheralManager(
    _ peripheral: CBPeripheralManager,
    didReceiveWrite requests: [CBATTRequest]
  ) {
    requests.forEach { req in
      callbackChannel.onWriteRequest(
        deviceId: req.central.identifier.uuidString,
        characteristicId: req.characteristic.uuid.uuidString,
        characteristicInstanceId: serviceRegistry.instanceId(of: req.characteristic),
        offset: Int64(req.offset),
        value: req.value?.toFlutterBytes()
      ) { writeRes in
        do {
          let response = try writeRes.get()
          let status = response?.status?.toCBATTErrorCode() ?? .success
          peripheral.respond(to: req, withResult: status)
        } catch {
          peripheral.respond(to: req, withResult: .requestNotSupported)
        }
      }
    }
  }

  private func upsertCentralSubscription(
    central: CBCentral,
    subscriptionId: String
  ) {
    let centralId = central.identifier.uuidString
    centralsLock.lock()
    centralsById[centralId] = central
    var subscriptions = centralCharacteristicSubscriptions[centralId] ?? Set<String>()
    subscriptions.insert(subscriptionId)
    centralCharacteristicSubscriptions[centralId] = subscriptions
    centralsLock.unlock()
  }

  private func removeCentralSubscription(centralId: String, subscriptionId: String) {
    centralsLock.lock()
    var subscriptions = centralCharacteristicSubscriptions[centralId] ?? Set<String>()
    subscriptions.remove(subscriptionId)
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

  func getSubscribedClients(
    characteristicId: String,
    characteristicInstanceId: String?
  ) throws -> [String] {
    let target = (characteristicInstanceId ?? characteristicId).uppercased()
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
  private var characteristicsByIdentity =
    [(characteristic: CBMutableCharacteristic, instanceId: String?)]()

  func register(
    _ service: CBMutableService,
    modelCharacteristics: [PeripheralCharacteristic],
    mutableCharacteristics: [CBCharacteristic]
  ) {
    unregisterCharacteristics(of: service)
    services.removeAll {
      $0.uuid.uuidString.lowercased() == service.uuid.uuidString.lowercased()
    }
    services.append(service)
    // Model order matches `mutableCharacteristics`, so a characteristic's
    // declared instance id can be attached to its CoreBluetooth object.
    for (index, characteristic) in mutableCharacteristics.enumerated() {
      guard let mutable = characteristic as? CBMutableCharacteristic else { continue }
      let model = index < modelCharacteristics.count ? modelCharacteristics[index] : nil
      characteristicsByIdentity.append((mutable, model?.instanceId))
    }
  }

  private func unregisterCharacteristics(of service: CBMutableService) {
    let ids = Set(
      (service.characteristics ?? []).map { ObjectIdentifier($0) }
    )
    characteristicsByIdentity.removeAll { ids.contains(ObjectIdentifier($0.characteristic)) }
  }

  func remove(_ service: CBMutableService) {
    unregisterCharacteristics(of: service)
    services.removeAll {
      $0.uuid.uuidString.lowercased() == service.uuid.uuidString.lowercased()
    }
  }

  func clear() {
    services.removeAll()
    characteristicsByIdentity.removeAll()
  }

  func service(_ serviceId: String) -> CBMutableService? {
    let target = serviceId.lowercased()
    return services.first { $0.uuid.uuidString.lowercased() == target }
  }

  func characteristic(
    _ characteristicId: String,
    instanceId: String?
  ) -> CBMutableCharacteristic? {
    if let instanceId {
      return characteristicsByIdentity.first {
        $0.characteristic.uuid.uuidString.lowercased() == characteristicId.lowercased()
          && ($0.instanceId?.lowercased() == instanceId.lowercased())
      }?.characteristic
    }
    let target = characteristicId.lowercased()
    return characteristicsByIdentity.first {
      $0.characteristic.uuid.uuidString.lowercased() == target
    }?.characteristic
  }

  func instanceId(of characteristic: CBCharacteristic) -> String? {
    let identifier = ObjectIdentifier(characteristic)
    return characteristicsByIdentity.first {
      ObjectIdentifier($0.characteristic) == identifier
    }?.instanceId
  }

  var serviceIds: [String] { services.map { $0.uuid.uuidString } }
}
