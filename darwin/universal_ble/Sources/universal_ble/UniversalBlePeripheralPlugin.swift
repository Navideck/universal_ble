#if os(iOS)
  import Flutter
#elseif os(macOS)
  import Cocoa
  import FlutterMacOS
#endif
import CoreBluetooth
import Foundation

final class UniversalBlePeripheralPlugin: NSObject, UniversalBlePeripheralChannel,
  UniversalBleDarwinPeripheralChannel,
  CBPeripheralManagerDelegate
{
  private let callbackChannel: UniversalBlePeripheralCallback
  private var advertisingState: PeripheralAdvertisingState = .idle
  private var peripheralManager: CBPeripheralManager?
  private let centralsLock = NSLock()
  private var centralsById = [String: CBCentral]()
  private var centralCharacteristicSubscriptions = [String: Set<String>]()
  // Pigeon calls and CoreBluetooth delegates both run on the main queue.
  private var pendingNotifications = PeripheralNotificationQueue<PendingNotification>()
  private static let restorationOwners = NSMapTable<NSString, UniversalBlePeripheralPlugin>
    .strongToWeakObjects()
  private var requestGeneration = 0
  private var hasBeenPoweredOn = false
  private var restorationIdentifier: String?
  private var eventsReady = true
  private var bufferedEvents = [() -> Void]()
  private var desiredAdvertisement: [String: Any]?
  private var serviceModels = [String: PeripheralService]()
  private var pendingServices = [ObjectIdentifier: (CBMutableService, PeripheralService)]()
  private var initialValues = [ObjectIdentifier: Data]()
  // Per plugin instance (one per FlutterEngine): the services this peripheral
  // advertises. Tearing one engine down (or clearing its services) must not wipe
  // another engine's advertising state.
  private let serviceRegistry = PeripheralServiceRegistry()

  private struct PendingNotification {
    let value: Data
    let characteristic: CBMutableCharacteristic
    let central: CBCentral
  }

  init(callbackChannel: UniversalBlePeripheralCallback) {
    self.callbackChannel = callbackChannel
    super.init()
    if let identifier = Bundle.main.object(
      forInfoDictionaryKey: "UniversalBlePeripheralRestorationIdentifier"
    ) as? String, !identifier.isEmpty,
      Self.restorationOwners.object(forKey: identifier as NSString) == nil
    {
      Self.restorationOwners.setObject(self, forKey: identifier as NSString)
      restorationIdentifier = identifier
      eventsReady = false
      // Do not introduce a launch-time permission prompt for an unused feature.
      if CBPeripheralManager.authorization == .allowedAlways {
        _ = ensurePeripheralManager()
      }
    }
  }

  func configureRestoration(restorationIdentifier: String) throws {
    guard !restorationIdentifier.trimmingCharacters(in: .whitespaces).isEmpty else {
      throw UniversalBlePeripheralError.failed("Restoration identifier must not be empty")
    }
    if peripheralManager != nil && self.restorationIdentifier != restorationIdentifier {
      throw UniversalBlePeripheralError.failed(
        "Configure restoration before creating the peripheral manager")
    }
    if let owner = Self.restorationOwners.object(forKey: restorationIdentifier as NSString),
      owner !== self
    {
      throw UniversalBlePeripheralError.failed(
        "Restoration identifier is already owned by another engine")
    }
    Self.restorationOwners.setObject(self, forKey: restorationIdentifier as NSString)
    self.restorationIdentifier = restorationIdentifier
    _ = ensurePeripheralManager()
    eventsReady = true
    let events = bufferedEvents
    bufferedEvents.removeAll()
    events.forEach { $0() }
  }

  private func emit(_ event: @escaping () -> Void) {
    if eventsReady { event() } else { bufferedEvents.append(event) }
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
    var options: [String: Any] = [:]
    if let restorationIdentifier {
      options[CBPeripheralManagerOptionRestoreIdentifierKey] = restorationIdentifier
    }
    let manager = CBPeripheralManager(delegate: self, queue: nil, options: options)
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
    desiredAdvertisement = nil
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
    let manager = ensurePeripheralManager()
    guard manager.state == .poweredOn else {
      throw UniversalBlePeripheralError.failed("Bluetooth peripheral is not ready")
    }
    let key = CBUUID(string: service.uuid).uuid128Str
    if pendingServices.values.contains(where: { CBUUID(string: $0.1.uuid).uuid128Str == key }) {
      return  // Dart is already waiting for didAdd for this service.
    }
    serviceModels[key] = service
    if let restored = serviceRegistry.service(service.uuid) {
      // Rebind Dart's definitions to restored objects; never publish duplicates.
      guard
        zip(restored.characteristics ?? [], service.characteristics).allSatisfy({
          $0.uuid.uuid128Str == CBUUID(string: $1.uuid).uuid128Str
        }),
        restored.characteristics?.count == service.characteristics.count
      else {
        throw UniversalBlePeripheralError.failed(
          "Restored service layout changed; remove it before replacing it")
      }
      serviceRegistry.register(
        restored, modelCharacteristics: service.characteristics,
        mutableCharacteristics: restored.characteristics ?? [])
      for (characteristic, definition) in zip(
        restored.characteristics ?? [], service.characteristics)
      {
        if let data = definition.value?.toData() {
          initialValues[ObjectIdentifier(characteristic)] = data
        }
      }
      rebuildCentralSubscriptions()
      saveIdentity(of: restored)
      emit { [weak self] in
        guard let self else { return }
        self.callbackChannel.onServiceAdded(serviceId: service.uuid, error: nil) { _ in }
      }
      return
    }
    let cbService = service.toCBService()
    pendingServices[ObjectIdentifier(cbService)] = (cbService, service)
    manager.add(cbService)
  }

  func removeService(serviceId: String) throws {
    let key = CBUUID(string: serviceId).uuid128Str
    let pending = pendingServices.values.filter { CBUUID(string: $0.1.uuid).uuid128Str == key }
    for (service, _) in pending {
      pendingServices.removeValue(forKey: ObjectIdentifier(service))
      emit { [weak self] in
        self?.callbackChannel.onServiceAdded(
          serviceId: service.uuid.uuidString,
          error: "Service registration cancelled"
        ) { _ in }
      }
      peripheralManager?.remove(service)
    }
    if let service = serviceRegistry.service(serviceId) {
      invalidateSubscriptions(of: service)
      peripheralManager?.remove(service)
      serviceRegistry.remove(service)
    }
    serviceModels.removeValue(forKey: key)
    forgetSavedIdentity(serviceId)
  }

  func clearServices() throws {
    requestGeneration += 1
    for service in serviceRegistry.allServices { invalidateSubscriptions(of: service) }
    peripheralManager?.removeAllServices()
    for (_, model) in pendingServices.values {
      emit { [weak self] in
        self?.callbackChannel.onServiceAdded(
          serviceId: model.uuid,
          error: "Service registration cancelled"
        ) { _ in }
      }
    }
    pendingServices.removeAll()
    pendingNotifications.removeAll()
    serviceRegistry.clear()
    serviceModels.removeAll()
    initialValues.removeAll()
    if let restorationIdentifier {
      UserDefaults.standard.removeObject(forKey: identityKey(restorationIdentifier))
    }
  }

  func getServices() throws -> [String] {
    serviceRegistry.serviceIds
  }

  func clearPendingNotifications(deviceId: String?) throws {
    if let deviceId {
      pendingNotifications.removeAll {
        $0.central.identifier.uuidString.caseInsensitiveCompare(deviceId) == .orderedSame
      }
    } else {
      pendingNotifications.removeAll()
    }
  }

  // Dart canonicalizes UUIDs to 128 bits. Preserve the 16-bit advertising field
  // for SIG services: some system pairing screens recognize HID only there.
  static func advertisingServiceUuid(_ value: String) -> CBUUID {
    let uuid = CBUUID(string: value)
    let full = uuid.uuid128Str
    if full.hasPrefix("0000"), full.hasSuffix("-0000-1000-8000-00805f9b34fb") {
      return CBUUID(string: String(full.dropFirst(4).prefix(4)))
    }
    return uuid
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
    let cbServices = services.map(Self.advertisingServiceUuid)
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
    desiredAdvertisement = advertisementData
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
    let targets = characteristic.subscribedCentrals ?? []
    let centrals: [CBCentral]
    if let deviceId {
      guard central(for: deviceId) != nil else {
        throw UniversalBlePeripheralError.notFound("\(deviceId) device not found")
      }
      centrals = targets.filter {
        $0.identifier.uuidString.caseInsensitiveCompare(deviceId) == .orderedSame
      }
    } else {
      centrals = targets
    }
    let data = value.toData()
    initialValues[ObjectIdentifier(characteristic)] = data
    // Capture actual subscribers now. A future subscriber must never receive
    // a broadcast queued during a previous session.
    for central in centrals {
      pendingNotifications.append(
        PendingNotification(value: data, characteristic: characteristic, central: central))
    }
    drainPendingNotifications()
  }

  private func drainPendingNotifications() {
    pendingNotifications.drain { notification in
      guard let manager = peripheralManager, manager.state == .poweredOn else { return false }
      return manager.updateValue(
        notification.value, for: notification.characteristic,
        onSubscribedCentrals: [notification.central])
    }
  }

  nonisolated func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
    pendingNotifications.resume()
    drainPendingNotifications()
  }

  nonisolated func peripheralManagerDidStartAdvertising(
    _: CBPeripheralManager,
    error: Error?
  ) {
    advertisingState = error == nil ? .advertising : .error
    emit { [weak self] in
      guard let self else { return }
      self.callbackChannel.onAdvertisingStateChange(
        state: self.advertisingState,
        error: error?.localizedDescription
      ) { _ in }
    }
  }

  nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    if peripheral.state != .poweredOn {
      // An initial unknown state is not evidence that restored services died.
      if peripheral.state == .unknown && !hasBeenPoweredOn { return }
      requestGeneration += 1
      for service in serviceRegistry.allServices { invalidateSubscriptions(of: service) }
      pendingNotifications.removeAll()
      clearCentrals()
      // Fail outstanding adds, so their Dart futures cannot outlive the adapter.
      let pending = pendingServices.values.map { $0.1.uuid }
      pendingServices.removeAll()
      serviceRegistry.clear()
      initialValues.removeAll()
      for uuid in pending {
        emit { [weak self] in
          guard let self else { return }
          self.callbackChannel.onServiceAdded(
            serviceId: uuid, error: "Bluetooth peripheral became unavailable"
          ) { _ in }
        }
      }
      advertisingState = .idle
      emit { [weak self] in
        guard let self else { return }
        self.callbackChannel.onAdvertisingStateChange(state: .idle, error: nil) { _ in }
      }
    } else {
      hasBeenPoweredOn = true
      for model in Array(serviceModels.values) where serviceRegistry.service(model.uuid) == nil {
        try? addService(service: model)
      }
      restartAdvertisingIfReady()
      emit { [weak self] in
        guard let self else { return }
        self.callbackChannel.onAdvertisingStateChange(state: self.advertisingState, error: nil) {
          _ in
        }
      }
    }
  }

  nonisolated func peripheralManager(
    _ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?
  ) {
    guard let (mutable, model) = pendingServices.removeValue(forKey: ObjectIdentifier(service))
    else {
      // A removed/timed-out add can complete late. Do not leak its publication
      // into a newer service registration with the same UUID.
      if error == nil, let mutable = service as? CBMutableService,
        serviceRegistry.service(service.uuid.uuidString) !== mutable
      {
        peripheral.remove(mutable)
      }
      return
    }
    if error == nil {
      serviceRegistry.register(
        mutable, modelCharacteristics: model.characteristics,
        mutableCharacteristics: mutable.characteristics ?? [])
      for (characteristic, definition) in zip(mutable.characteristics ?? [], model.characteristics)
      {
        if let data = definition.value?.toData() {
          initialValues[ObjectIdentifier(characteristic)] = data
        }
      }
      saveIdentity(of: mutable)
    }
    emit { [weak self] in
      guard let self else { return }
      self.callbackChannel.onServiceAdded(
        serviceId: service.uuid.uuidString,
        error: error?.localizedDescription
      ) { _ in }
    }
    restartAdvertisingIfReady()
  }

  private func restartAdvertisingIfReady() {
    guard pendingServices.isEmpty, let manager = peripheralManager,
      manager.state == .poweredOn, !manager.isAdvertising,
      let desiredAdvertisement,
      serviceModels.keys.allSatisfy({ serviceRegistry.service($0) != nil })
    else { return }
    manager.startAdvertising(desiredAdvertisement)
  }

  nonisolated func peripheralManager(
    _ peripheral: CBPeripheralManager, willRestoreState dict: [String: Any]
  ) {
    peripheralManager = peripheral
    pendingNotifications.removeAll()
    serviceRegistry.clear()
    clearCentrals()
    let saved = savedIdentities()
    for service in dict[CBPeripheralManagerRestoredStateServicesKey] as? [CBMutableService] ?? [] {
      let identities = saved[service.uuid.uuid128Str] ?? []
      serviceRegistry.restore(service, identities: identities)
      for characteristic in service.characteristics ?? [] {
        // Never restore transient key state from an old process.
        for central in (characteristic as? CBMutableCharacteristic)?.subscribedCentrals ?? [] {
          self.peripheralManager(peripheral, central: central, didSubscribeTo: characteristic)
        }
      }
    }
    desiredAdvertisement =
      dict[CBPeripheralManagerRestoredStateAdvertisementDataKey] as? [String: Any]
    advertisingState = peripheral.isAdvertising ? .advertising : .idle
    emit { [weak self] in
      guard let self else { return }
      self.callbackChannel.onAdvertisingStateChange(state: self.advertisingState, error: nil) { _ in
      }
    }
  }

  private func identityKey(_ identifier: String) -> String {
    "universal_ble.peripheral.instances." + identifier
  }

  private func savedIdentities() -> [String: [[String: String]]] {
    guard let restorationIdentifier else { return [:] }
    return UserDefaults.standard.dictionary(forKey: identityKey(restorationIdentifier))
      as? [String: [[String: String]]] ?? [:]
  }

  private func saveIdentity(of service: CBMutableService) {
    guard let restorationIdentifier else { return }
    var saved = savedIdentities()
    saved[service.uuid.uuid128Str] = (service.characteristics ?? []).map {
      ["uuid": $0.uuid.uuid128Str, "instanceId": serviceRegistry.instanceId(of: $0) ?? ""]
    }
    UserDefaults.standard.set(saved, forKey: identityKey(restorationIdentifier))
  }

  private func forgetSavedIdentity(_ serviceId: String) {
    guard let restorationIdentifier else { return }
    var saved = savedIdentities()
    saved.removeValue(forKey: CBUUID(string: serviceId).uuid128Str)
    UserDefaults.standard.set(saved, forKey: identityKey(restorationIdentifier))
  }

  private func invalidateSubscriptions(of service: CBMutableService) {
    for characteristic in service.characteristics ?? [] {
      pendingNotifications.removeAll { $0.characteristic === characteristic }
      initialValues.removeValue(forKey: ObjectIdentifier(characteristic))
      let subscriptionId =
        serviceRegistry.instanceId(of: characteristic) ?? characteristic.uuid.uuidString
      centralsLock.lock()
      let subscribed = centralCharacteristicSubscriptions.compactMap { id, subscriptions in
        subscriptions.contains(subscriptionId) ? centralsById[id] : nil
      }
      centralsLock.unlock()
      for central in subscribed {
        removeCentralSubscription(
          centralId: central.identifier.uuidString,
          subscriptionId: serviceRegistry.instanceId(of: characteristic)
            ?? characteristic.uuid.uuidString)
        subscriptionEvent(central, characteristic, subscribed: false)
      }
    }
  }

  private func subscriptionEvent(
    _ central: CBCentral, _ characteristic: CBCharacteristic, subscribed: Bool
  ) {
    let instanceId = serviceRegistry.instanceId(of: characteristic)
    emit { [weak self] in
      guard let self else { return }
      self.callbackChannel.onCharacteristicSubscriptionChange(
        deviceId: central.identifier.uuidString,
        characteristicId: characteristic.uuid.uuidString, characteristicInstanceId: instanceId,
        isSubscribed: subscribed, name: nil
      ) { _ in }
    }
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
    subscriptionEvent(central, characteristic, subscribed: true)
    emit { [weak self] in
      self?.callbackChannel.onMtuChange(
        deviceId: central.identifier.uuidString,
        mtu: Int64(central.maximumUpdateValueLength)
      ) { _ in }
    }
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
    pendingNotifications.removeAll {
      $0.central.identifier == central.identifier
    }
    initialValues.removeValue(forKey: ObjectIdentifier(characteristic))
    subscriptionEvent(central, characteristic, subscribed: false)
  }

  nonisolated func peripheralManager(
    _ peripheral: CBPeripheralManager,
    didReceiveRead request: CBATTRequest
  ) {
    let generation = requestGeneration
    emit { [weak self] in
      guard let self, generation == self.requestGeneration else {
        peripheral.respond(to: request, withResult: .requestNotSupported)
        return
      }
      self.callbackChannel.onReadRequest(
        deviceId: request.central.identifier.uuidString,
        characteristicId: request.characteristic.uuid.uuidString,
        characteristicInstanceId: self.serviceRegistry.instanceId(of: request.characteristic),
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
            fullData =
              self.initialValues[ObjectIdentifier(request.characteristic)]
              ?? request.characteristic.value
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
  }

  nonisolated func peripheralManager(
    _ peripheral: CBPeripheralManager,
    didReceiveWrite requests: [CBATTRequest]
  ) {
    requests.forEach { req in
      let generation = requestGeneration
      emit { [weak self] in
        guard let self, generation == self.requestGeneration else {
          peripheral.respond(to: req, withResult: .requestNotSupported)
          return
        }
        self.callbackChannel.onWriteRequest(
          deviceId: req.central.identifier.uuidString,
          characteristicId: req.characteristic.uuid.uuidString,
          characteristicInstanceId: self.serviceRegistry.instanceId(of: req.characteristic),
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
    guard
      let characteristic = serviceRegistry.characteristic(
        characteristicId,
        instanceId: characteristicInstanceId)
    else { return [] }
    // Query CoreBluetooth's current objects, not a potentially stale app cache.
    return (characteristic.subscribedCentrals ?? []).map { $0.identifier.uuidString }
  }

  private func rebuildCentralSubscriptions() {
    clearCentrals()
    for service in serviceRegistry.allServices {
      for characteristic in service.characteristics ?? [] {
        for central in (characteristic as? CBMutableCharacteristic)?.subscribedCentrals ?? [] {
          upsertCentralSubscription(
            central: central,
            subscriptionId: serviceRegistry.instanceId(of: characteristic)
              ?? characteristic.uuid.uuidString)
        }
      }
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
final class PeripheralServiceRegistry {
  private var services = [CBMutableService]()
  private var characteristicsByIdentity =
    [(characteristic: CBMutableCharacteristic, instanceId: String?)]()

  func register(
    _ service: CBMutableService,
    modelCharacteristics: [PeripheralCharacteristic],
    mutableCharacteristics: [CBCharacteristic]
  ) {
    if let previous = self.service(service.uuid.uuidString) {
      unregisterCharacteristics(of: previous)
    }
    unregisterCharacteristics(of: service)
    services.removeAll {
      $0.uuid.uuid128Str == service.uuid.uuid128Str
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
    if let previous = self.service(service.uuid.uuidString) {
      unregisterCharacteristics(of: previous)
    }
    unregisterCharacteristics(of: service)
    services.removeAll {
      $0.uuid.uuid128Str == service.uuid.uuid128Str
    }
  }

  func clear() {
    services.removeAll()
    characteristicsByIdentity.removeAll()
  }

  func service(_ serviceId: String) -> CBMutableService? {
    let target = CBUUID(string: serviceId).uuid128Str
    return services.first { $0.uuid.uuid128Str == target }
  }

  func characteristic(
    _ characteristicId: String,
    instanceId: String?
  ) -> CBMutableCharacteristic? {
    if let instanceId {
      return characteristicsByIdentity.first {
        $0.characteristic.uuid.uuid128Str == CBUUID(string: characteristicId).uuid128Str
          && ($0.instanceId?.lowercased() == instanceId.lowercased())
      }?.characteristic
    }
    let target = CBUUID(string: characteristicId).uuid128Str
    return characteristicsByIdentity.first {
      $0.characteristic.uuid.uuid128Str == target
    }?.characteristic
  }

  func instanceId(of characteristic: CBCharacteristic) -> String? {
    let identifier = ObjectIdentifier(characteristic)
    return characteristicsByIdentity.first {
      ObjectIdentifier($0.characteristic) == identifier
    }?.instanceId
  }

  /// Restore the actual CoreBluetooth objects, keeping duplicate UUID identities.
  func restore(_ service: CBMutableService, identities: [[String: String]]) {
    if let previous = self.service(service.uuid.uuidString) {
      unregisterCharacteristics(of: previous)
    }
    unregisterCharacteristics(of: service)
    services.removeAll { $0.uuid.uuid128Str == service.uuid.uuid128Str }
    services.append(service)
    for (index, characteristic) in (service.characteristics ?? []).enumerated() {
      guard let mutable = characteristic as? CBMutableCharacteristic else { continue }
      let identity = index < identities.count ? identities[index] : [:]
      let matches =
        identity["uuid"].map { CBUUID(string: $0).uuid128Str == characteristic.uuid.uuid128Str }
        ?? false
      let id = matches ? identity["instanceId"] : nil
      characteristicsByIdentity.append((mutable, id?.isEmpty == false ? id : nil))
    }
  }

  var allServices: [CBMutableService] { services }

  var serviceIds: [String] { services.map { $0.uuid.uuidString } }
}
