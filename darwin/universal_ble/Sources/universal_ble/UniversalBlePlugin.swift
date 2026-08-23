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
    let peripheralCallbackChannel = UniversalBlePeripheralCallback(binaryMessenger: messenger)
    let peripheralApi = UniversalBlePeripheralPlugin(callbackChannel: peripheralCallbackChannel)
    UniversalBlePlatformChannelSetup.setUp(binaryMessenger: messenger, api: api)
    #if os(iOS)
      // When the host app declares `bluetooth-central`, build the manager during
      // launch so CoreBluetooth can deliver `willRestoreState:` after a background
      // relaunch (see activateStateRestoration).
      api.activateStateRestoration()
    #endif
    UniversalBlePeripheralChannelSetup.setUp(
      binaryMessenger: messenger,
      api: peripheralApi
    )
  }
}

private var discoveredPeripherals = [String: CBPeripheral]()

// Cache last advertised local name for peripherals
// since iOS and MacOS don't do that for system devices
private var advertisementNameCache = [String: String]()

private class BleCentralDarwin: NSObject, UniversalBlePlatformChannel, CBCentralManagerDelegate, CBPeripheralDelegate {
  // Identifier CoreBluetooth uses to restore this central across relaunches.
  static let stateRestorationIdentifier = "com.universalble.central.restoration"

  #if os(iOS)
    /// True when the host app declares the `bluetooth-central` background mode.
    /// State restoration and eager manager creation are only enabled in that case.
    private static let hasBluetoothCentralBackgroundMode: Bool = {
      guard let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] else {
        return false
      }
      return modes.contains("bluetooth-central")
    }()

    private static var hasBluetoothPermission: Bool {
      CBCentralManager.authorization == .allowedAlways
    }

    /// Availability derived from `CBCentralManager.authorization` without creating a manager.
    private static var availabilityStateFromAuthorization: AvailabilityState {
      switch CBCentralManager.authorization {
      case .restricted, .denied:
        return .unauthorized
      case .notDetermined:
        return .unknown
      default:
        return .unknown
      }
    }
  #endif

  var callbackChannel: UniversalBleCallbackChannel
  private var universalBleFilterUtil = UniversalBleFilterUtil()
  #if os(iOS)
    private lazy var manager: CBCentralManager = {
      if Self.hasBluetoothCentralBackgroundMode {
        return CBCentralManager(
          delegate: self,
          queue: nil,
          options: [
            CBCentralManagerOptionRestoreIdentifierKey: BleCentralDarwin.stateRestorationIdentifier,
          ]
        )
      }
      return CBCentralManager(delegate: self, queue: nil)
    }()
  #else
    // macOS does not support CoreBluetooth state restoration.
    private lazy var manager: CBCentralManager = .init(delegate: self, queue: nil)
  #endif
  private var availabilityStateUpdateHandlers: [(Result<AvailabilityState, Error>) -> Void] = []
  private var requestPermissionStateUpdateHandlers: [(Result<Void, Error>) -> Void] = []
  private var activeServiceDiscoveries: [String: UniversalBleAsyncServiceDiscovery] = [:]
  private var characteristicReadFutures = [CharacteristicReadFuture]()
  private var characteristicWriteFutures = [CharacteristicWriteFuture]()
  private var characteristicWriteWithoutResponseFutures = [CharacteristicWriteFuture]()
  private var characteristicNotifyFutures = [CharacteristicNotifyFuture]()
  private var descriptorReadFutures = [DescriptorReadFuture]()
  private var descriptorWriteFutures = [DescriptorWriteFuture]()
  private var discoverServicesFutures = [DiscoverServicesFuture]()
  private var rssiReadFutures = [RssiReadFuture]()
  private var isManageScanning = false
  private var autoConnectDevices = Set<String>()

  init(callbackChannel: UniversalBleCallbackChannel) {
    self.callbackChannel = callbackChannel
    super.init()
  }

  #if os(iOS)
    /// Eagerly creates the central manager at launch when the app declares the
    /// `bluetooth-central` background mode and Bluetooth permission is already
    /// granted, so CoreBluetooth can deliver `willRestoreState:` when a managed
    /// peripheral relaunches the app. Otherwise creation stays deferred until
    /// a central BLE API (e.g. `startScan`, `connect`) is called.
    func activateStateRestoration() {
      guard Self.hasBluetoothCentralBackgroundMode, Self.hasBluetoothPermission else { return }
      _ = manager
    }
  #endif

  func getBluetoothAvailabilityState(completion: @escaping (Result<AvailabilityState, Error>) -> Void) {
    #if os(iOS)
      if Self.hasBluetoothCentralBackgroundMode, !Self.hasBluetoothPermission {
        completion(.success(Self.availabilityStateFromAuthorization))
        return
      }
    #endif
    if manager.state != .unknown {
      completion(.success(manager.state.toAvailabilityState()))
    } else {
      availabilityStateUpdateHandlers.append(completion)
      _ = manager
    }
  }

  func hasPermissions(withAndroidFineLocation _: Bool) throws -> Bool {
    return CBCentralManager.authorization == .allowedAlways
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

  func startScan(filter: UniversalScanFilter?, config _: UniversalScanConfig?) throws {
    // If filter has any other filter other than official one
    let usesCustomFilters = filter?.usesCustomFilters ?? false

    // Apply services filter
    var withServices: [CBUUID] = try filter?.withServices.compactMap { $0 }.toCBUUID() ?? []

    if usesCustomFilters {
      UniversalBleLogger.shared.logInfo("Using Custom Filters")
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
    if CBCentralManager.authorization == .allowedAlways {
      return manager.isScanning
    }
    return isManageScanning
  }

  func setLogLevel(logLevel: BleLogLevel) throws {
    UniversalBleLogger.shared.setLogLevel(logLevel)
  }

  func connect(deviceId: String, autoConnect: Bool?, platformConfig: ConnectionPlatformConfig?) throws {
    let peripheral = try deviceId.getPeripheral(manager: manager)
    peripheral.delegate = self
    let shouldAutoConnect = autoConnect ?? false

    var options: [String: Any] = [:]

    // Opt-in: ask the system to surface connection-related events while the
    // app is suspended (relaunching it into the background when one occurs),
    // so a backgrounded central stays responsive — e.g. while reconnecting to
    // a previously paired peripheral — without the user having to foreground
    // the app. The system may show the user an alert for these events, which
    // is why they are off unless requested via `AppleConnectionOptions`.
    if let appleOptions = platformConfig?.apple {
      if appleOptions.notifyOnConnection == true {
        options[CBConnectPeripheralOptionNotifyOnConnectionKey] = true
      }
      if appleOptions.notifyOnDisconnection == true {
        options[CBConnectPeripheralOptionNotifyOnDisconnectionKey] = true
      }
      if appleOptions.notifyOnNotification == true {
        options[CBConnectPeripheralOptionNotifyOnNotificationKey] = true
      }
    }

    if shouldAutoConnect {
      autoConnectDevices.insert(deviceId)
      if #available(iOS 17.0, macOS 14.0, watchOS 10.0, tvOS 17.0, *) {
        options[CBConnectPeripheralOptionEnableAutoReconnect] = true
      } else {
        // Auto-reconnect via CBConnectPeripheralOptionEnableAutoReconnect is only
        // available on iOS 17.0 / macOS 14.0 / watchOS 10.0 / tvOS 17.0 and later.
        // On earlier OS versions, enabling `autoConnect` will NOT provide automatic
        // reconnection behavior. Any desired reconnection must be handled manually
        // (e.g., in central manager delegate callbacks).
        UniversalBleLogger.shared.logInfo(
          "autoConnect requested for device \(deviceId), " +
            "but automatic reconnection via CBConnectPeripheralOptionEnableAutoReconnect " +
            "is only available on iOS 17+/macOS 14+/watchOS 10+/tvOS 17+. " +
            "On this OS version, reconnections must be handled manually."
        )
      }
    } else {
      autoConnectDevices.remove(deviceId)
    }

    manager.connect(peripheral, options: options.isEmpty ? nil : options)
  }

  func disconnect(deviceId: String) throws {
    autoConnectDevices.remove(deviceId)
    guard let peripheral = deviceId.findPeripheral(manager: manager) else {
      callbackChannel.onConnectionChanged(deviceId: deviceId, connected: false, error: nil) { _ in }
      cleanUpConnection(deviceId: deviceId)
      return
    }
    if peripheral.state != CBPeripheralState.disconnected {
      manager.cancelPeripheralConnection(peripheral)
    }
    cleanUpConnection(deviceId: deviceId)
  }

  func getConnectionState(deviceId: String) throws -> BleConnectionState {
    guard let peripheral = deviceId.findPeripheral(manager: manager) else {
      return .disconnected
    }
    switch peripheral.state {
    case .connecting:
      return .connecting
    case .connected:
      return .connected
    case .disconnecting:
      return .disconnecting
    case .disconnected:
      return .disconnected
    @unknown default:
      return .disconnected
    }
  }

  func cleanUpConnection(deviceId: String) {
    let matchesDeviceId: (String) -> Bool = { targetId in
      targetId.caseInsensitiveCompare(deviceId) == .orderedSame
    }

    characteristicReadFutures.removeAll { future in
      if matchesDeviceId(future.deviceId) {
        future.result(
          Result.failure(createFlutterError(code: .deviceDisconnected, message: "Device Disconnected"))
        )
        return true
      }
      return false
    }
    characteristicWriteFutures.removeAll { future in
      if matchesDeviceId(future.deviceId) {
        future.result(
          Result.failure(createFlutterError(code: .deviceDisconnected, message: "Device Disconnected"))
        )
        return true
      }
      return false
    }
    characteristicNotifyFutures.removeAll { future in
      if matchesDeviceId(future.deviceId) {
        future.result(
          Result.failure(createFlutterError(code: .deviceDisconnected, message: "Device Disconnected"))
        )
        return true
      }
      return false
    }
    descriptorReadFutures.removeAll { future in
      if matchesDeviceId(future.deviceId) {
        future.result(
          Result.failure(createFlutterError(code: .deviceDisconnected, message: "Device Disconnected"))
        )
        return true
      }
      return false
    }
    descriptorWriteFutures.removeAll { future in
      if matchesDeviceId(future.deviceId) {
        future.result(
          Result.failure(createFlutterError(code: .deviceDisconnected, message: "Device Disconnected"))
        )
        return true
      }
      return false
    }
    rssiReadFutures.removeAll { future in
      if matchesDeviceId(future.deviceId) {
        future.result(
          Result.failure(createFlutterError(code: .deviceDisconnected, message: "Device Disconnected"))
        )
        return true
      }
      return false
    }

    // Cancel and fail any active service discovery for this device
    for (key, discovery) in activeServiceDiscoveries where matchesDeviceId(key) {
      discovery.cancel(error: createFlutterError(code: .deviceDisconnected, message: "Device Disconnected"))
    }
    activeServiceDiscoveries = activeServiceDiscoveries.filter { !matchesDeviceId($0.key) }

    discoverServicesFutures.removeAll { future in
      if matchesDeviceId(future.deviceId) {
        future.result(
          Result.failure(createFlutterError(code: .deviceDisconnected, message: "Device Disconnected"))
        )
        return true
      }
      return false
    }
  }

  func discoverServices(deviceId: String, withDescriptors: Bool, completion: @escaping (Result<[UniversalBleService], Error>) -> Void) {
    guard let peripheral = deviceId.findPeripheral(manager: manager) else {
      completion(
        Result.failure(createFlutterError(code: .deviceNotFound, message: "Unknown deviceId:\(deviceId)"))
      )
      return
    }

    guard peripheral.state == .connected else {
      completion(
        Result.failure(createFlutterError(code: .deviceDisconnected, message: "Device is not connected"))
      )
      return
    }

    let normalizedDeviceId = peripheral.uuid.uuidString

    // Check if discovery is already in progress
    if activeServiceDiscoveries[normalizedDeviceId] != nil {
      UniversalBleLogger.shared.logWarning("Services discovery already in progress for :\(normalizedDeviceId), waiting for completion.")
      discoverServicesFutures.append(DiscoverServicesFuture(deviceId: normalizedDeviceId, result: completion))
      return
    }

    let wrappedCompletion: (Result<[UniversalBleService], Error>) -> Void = { [weak self] result in
      guard let self = self else { return }
      completion(result)
      self.discoverServicesFutures.removeAll { future in
        if future.deviceId.caseInsensitiveCompare(normalizedDeviceId) == .orderedSame {
          future.result(result)
          return true
        }
        return false
      }
      self.activeServiceDiscoveries.removeValue(forKey: normalizedDeviceId)
    }

    let discovery = UniversalBleAsyncServiceDiscovery(
      peripheral: peripheral,
      deviceId: normalizedDeviceId,
      withDescriptors: withDescriptors,
      completion: wrappedCompletion
    )

    activeServiceDiscoveries[normalizedDeviceId] = discovery
    discovery.startDiscovery()
  }

  func setNotifiable(deviceId: String, service: String, characteristic: String, bleInputProperty: BleInputProperty, completion: @escaping (Result<Void, any Error>) -> Void) {
    UniversalBleLogger.shared.logDebug("SET_NOTIFY -> \(deviceId) \(service) \(characteristic) input=\(bleInputProperty)")
    guard let peripheral = deviceId.findPeripheral(manager: manager) else {
      completion(Result.failure(createFlutterError(code: .deviceNotFound, message: "Unknown deviceId:\(deviceId)")))
      return
    }

    guard let gattCharacteristic = peripheral.getCharacteristic(characteristic, of: service) else {
      completion(Result.failure(createFlutterError(code: .characteristicNotFound, message: "Unknown characteristic:\(characteristic)")))
      return
    }

    if bleInputProperty == .notification && !gattCharacteristic.properties.contains(.notify) {
      completion(Result.failure(createFlutterError(code: .characteristicDoesNotSupportNotify, message: "Characteristic does not support notify")))
      return
    }

    if bleInputProperty == .indication && !gattCharacteristic.properties.contains(.indicate) {
      completion(Result.failure(createFlutterError(code: .characteristicDoesNotSupportIndicate, message: "Characteristic does not support indicate")))
      return
    }

    let shouldNotify = bleInputProperty != .disabled
    peripheral.setNotifyValue(shouldNotify, for: gattCharacteristic)
    characteristicNotifyFutures.append(CharacteristicNotifyFuture(deviceId: deviceId, characteristicId: gattCharacteristic.uuid.uuidStr, serviceId: gattCharacteristic.service?.uuid.uuidStr, result: completion))
  }

  func readValue(deviceId: String, service: String, characteristic: String, completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) {
    UniversalBleLogger.shared.logDebug("READ -> \(deviceId) \(service) \(characteristic)")
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

  func writeValue(deviceId: String, service: String, characteristic: String, value: FlutterStandardTypedData, bleOutputProperty: BleOutputProperty, completion: @escaping (Result<Void, Error>) -> Void) {
    UniversalBleLogger.shared.logDebug("WRITE -> \(deviceId) \(service) \(characteristic) len=\(value.data.count) property=\(bleOutputProperty)")
    guard let peripheral = deviceId.findPeripheral(manager: manager) else {
      completion(Result.failure(createFlutterError(code: .deviceNotFound, message: "Unknown deviceId:\(self)")))
      return
    }
    guard let gattCharacteristic = peripheral.getCharacteristic(characteristic, of: service) else {
      completion(Result.failure(createFlutterError(code: .characteristicNotFound, message: "Unknown characteristic:\(characteristic)")))
      return
    }

    let type = bleOutputProperty == .withoutResponse ? CBCharacteristicWriteType.withoutResponse : CBCharacteristicWriteType.withResponse

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

  func readDescriptorValue(deviceId: String, service: String, characteristic: String, descriptor: String, completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) {
    UniversalBleLogger.shared.logDebug("READ_DESCRIPTOR -> \(deviceId) \(service) \(characteristic) \(descriptor)")
    guard let peripheral = deviceId.findPeripheral(manager: manager) else {
      completion(Result.failure(createFlutterError(code: .deviceNotFound, message: "Unknown deviceId:\(deviceId)")))
      return
    }
    guard let gattDescriptor = peripheral.getDescriptor(descriptor, for: characteristic, of: service) else {
      completion(Result.failure(createFlutterError(code: .characteristicNotFound, message: "Descriptor not found:\(descriptor)")))
      return
    }
    peripheral.readValue(for: gattDescriptor)
    descriptorReadFutures.append(DescriptorReadFuture(
      deviceId: deviceId,
      descriptorId: gattDescriptor.uuid.uuidStr,
      characteristicId: gattDescriptor.characteristic?.uuid.uuidStr ?? characteristic,
      serviceId: gattDescriptor.characteristic?.service?.uuid.uuidStr ?? service,
      result: completion
    ))
  }

  func writeDescriptorValue(deviceId: String, service: String, characteristic: String, descriptor: String, value: FlutterStandardTypedData, completion: @escaping (Result<Void, Error>) -> Void) {
    UniversalBleLogger.shared.logDebug("WRITE_DESCRIPTOR -> \(deviceId) \(service) \(characteristic) \(descriptor) len=\(value.data.count)")
    guard let peripheral = deviceId.findPeripheral(manager: manager) else {
      completion(Result.failure(createFlutterError(code: .deviceNotFound, message: "Unknown deviceId:\(deviceId)")))
      return
    }
    guard let gattDescriptor = peripheral.getDescriptor(descriptor, for: characteristic, of: service) else {
      completion(Result.failure(createFlutterError(code: .characteristicNotFound, message: "Descriptor not found:\(descriptor)")))
      return
    }

    // CoreBluetooth throws NSInternalInconsistencyException if writeValue:forDescriptor: is called on CCCD (0x2902).
    // CoreBluetooth requires using setNotifyValue:forCharacteristic: for CCCD.
    let cccdUUID = CBUUID(string: CBUUIDClientCharacteristicConfigurationString)
    let fullCccdUUID = CBUUID(string: "00002902-0000-1000-8000-00805f9b34fb")
    if gattDescriptor.uuid == cccdUUID || gattDescriptor.uuid == fullCccdUUID {
      guard let gattCharacteristic = gattDescriptor.characteristic else {
        completion(Result.failure(createFlutterError(code: .characteristicNotFound, message: "Characteristic not found for descriptor")))
        return
      }
      let enable = value.data.contains { $0 != 0 }
      peripheral.setNotifyValue(enable, for: gattCharacteristic)
      characteristicNotifyFutures.append(CharacteristicNotifyFuture(
        deviceId: deviceId,
        characteristicId: gattCharacteristic.uuid.uuidStr,
        serviceId: gattCharacteristic.service?.uuid.uuidStr,
        result: completion
      ))
      return
    }

    peripheral.writeValue(value.data, for: gattDescriptor)
    descriptorWriteFutures.append(DescriptorWriteFuture(
      deviceId: deviceId,
      descriptorId: gattDescriptor.uuid.uuidStr,
      characteristicId: gattDescriptor.characteristic?.uuid.uuidStr ?? characteristic,
      serviceId: gattDescriptor.characteristic?.service?.uuid.uuidStr ?? service,
      result: completion
    ))
  }

  func requestMtu(deviceId: String, expectedMtu _: Int64, completion: @escaping (Result<Int64, Error>) -> Void) {
    UniversalBleLogger.shared.logDebug("REQUEST_MTU -> \(deviceId)")
    guard let peripheral = deviceId.findPeripheral(manager: manager) else {
      completion(Result.failure(createFlutterError(code: .deviceNotFound, message: "Unknown deviceId:\(self)")))
      return
    }
    let mtu = peripheral.maximumWriteValueLength(for: CBCharacteristicWriteType.withoutResponse)
    let GATT_HEADER_LENGTH = 3
    let mtuResult = Int64(mtu + GATT_HEADER_LENGTH)
    completion(Result.success(mtuResult))
  }

  func requestConnectionPriority(
    deviceId _: String,
    priority _: BleConnectionPriority,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    completion(.failure(createFlutterError(code: .notSupported, message: "requestConnectionPriority is not supported on Apple platforms")))
  }

  func readRssi(deviceId: String, completion: @escaping (Result<Int64, Error>) -> Void) {
    UniversalBleLogger.shared.logDebug("READ_RSSI -> \(deviceId)")
    guard let peripheral = deviceId.findPeripheral(manager: manager) else {
      completion(Result.failure(createFlutterError(code: .deviceNotFound, message: "Unknown deviceId:\(deviceId)")))
      return
    }
    peripheral.readRSSI()
    rssiReadFutures.append(RssiReadFuture(deviceId: deviceId, result: completion))
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
      UniversalBleLogger.shared.logInfo("No services filter was set for getting system connected devices. Using default services...")

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
        name: name,
        serviceData: nil,
        timestamp: Int64(Date().timeIntervalSince1970 * 1000)
      )
    }))
  }

  #if os(iOS)
    public func centralManager(_: CBCentralManager, willRestoreState dict: [String: Any]) {
      guard let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] else {
        return
      }
      // Re-adopt restored peripherals: restore the delegate and repopulate the
      // lookup cache so the existing connection stays usable.
      for peripheral in peripherals {
        peripheral.delegate = self
        peripheral.saveCache()
        let deviceId = peripheral.uuid.uuidString
        // Notify Dart if already connected; on a cold relaunch the Dart layer
        // re-subscribes on resume using the cached peripheral.
        if peripheral.state == .connected {
          callbackChannel.onConnectionChanged(deviceId: deviceId, connected: true, error: nil) { _ in }
        }
      }
    }
  #endif

  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    let state = central.state.toAvailabilityState()
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
    let serviceDataDict = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data]

    var manufacturerDataList: [UniversalManufacturerData] = []
    var universalManufacturerData: UniversalManufacturerData? = nil

    if let msd = manufacturerData, msd.count > 2 {
      let companyIdentifier = msd.prefix(2).withUnsafeBytes { $0.load(as: UInt16.self) }
      let data = FlutterStandardTypedData(bytes: msd.suffix(from: 2))
      universalManufacturerData = UniversalManufacturerData(companyIdentifier: Int64(companyIdentifier), data: data)
      manufacturerDataList.append(universalManufacturerData!)
    }

    var serviceData: [String: FlutterStandardTypedData]? = nil
    if let serviceDataDict = serviceDataDict {
      serviceData = Dictionary(uniqueKeysWithValues: serviceDataDict.map { uuid, data in
        (uuid.uuidStr, FlutterStandardTypedData(bytes: data))
      })
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
      serviceData: serviceData,
      services: services?.map { $0.uuidStr },
      timestamp: Int64(Date().timeIntervalSince1970 * 1000)
    )) { _ in }
  }

  public func centralManager(_: CBCentralManager, didConnect peripheral: CBPeripheral) {
    callbackChannel.onConnectionChanged(deviceId: peripheral.uuid.uuidString, connected: true, error: nil) { _ in }
  }

  private func handlePeripheralDisconnection(deviceId: String, error: Error?) {
    autoConnectDevices.remove(deviceId)
    callbackChannel.onConnectionChanged(deviceId: deviceId, connected: false, error: error?.localizedDescription) { _ in }
    cleanUpConnection(deviceId: deviceId)
  }

  public func centralManager(
    _: CBCentralManager,
    didDisconnectPeripheral peripheral: CBPeripheral,
    timestamp _: CFAbsoluteTime,
    isReconnecting: Bool,
    error: Error?
  ) {
    let deviceId = peripheral.uuid.uuidString

    if #available(iOS 17.0, macOS 14.0, watchOS 10.0, tvOS 17.0, *) {
      if isReconnecting {
        cleanUpConnection(deviceId: deviceId)
        return
      }
    }

    handlePeripheralDisconnection(deviceId: deviceId, error: error)
  }

  public func centralManager(_: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
    let deviceId = peripheral.uuid.uuidString
    handlePeripheralDisconnection(deviceId: deviceId, error: error)
  }

  public func centralManager(_: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
    callbackChannel.onConnectionChanged(deviceId: peripheral.uuid.uuidString, connected: false, error: error?.localizedDescription) { _ in }
    cleanUpConnection(deviceId: peripheral.uuid.uuidString)
  }

  public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    let deviceId = peripheral.uuid.uuidString
    activeServiceDiscoveries[deviceId]?.handleDidDiscoverServices(peripheral, error: error)
  }

  public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    let deviceId = peripheral.uuid.uuidString
    activeServiceDiscoveries[deviceId]?.handleDidDiscoverCharacteristicsFor(peripheral, service: service, error: error)
  }

  public func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
    let deviceId = peripheral.uuid.uuidString
    activeServiceDiscoveries[deviceId]?.handleDidDiscoverDescriptorsFor(peripheral, characteristic: characteristic, error: error)
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
          UniversalBleLogger.shared.logError("WRITE_FAILED <- \(peripheral.uuid.uuidString) \(characteristic.uuid.uuidStr): \(flutterError.message ?? "")")
          future.result(Result.failure(flutterError))
        } else {
          future.result(Result.success({}()))
        }
        return true
      }
      return false
    }
  }

  public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
    descriptorReadFutures.removeAll { future in
      if future.deviceId == peripheral.uuid.uuidString &&
        future.descriptorId == descriptor.uuid.uuidStr &&
        future.characteristicId == descriptor.characteristic?.uuid.uuidStr &&
        future.serviceId == descriptor.characteristic?.service?.uuid.uuidStr {
        if let flutterError = error?.toFlutterError() {
          UniversalBleLogger.shared.logError("READ_DESCRIPTOR_FAILED <- \(peripheral.uuid.uuidString) \(descriptor.uuid.uuidStr): \(flutterError.message ?? "")")
          future.result(Result.failure(flutterError))
        } else {
          if let valueData = descriptor.value as? Data {
            future.result(Result.success(FlutterStandardTypedData(bytes: valueData)))
          } else if let numberVal = descriptor.value as? NSNumber {
            var val = numberVal.uint16Value
            let data = Data(bytes: &val, count: MemoryLayout<UInt16>.size)
            future.result(Result.success(FlutterStandardTypedData(bytes: data)))
          } else if let stringVal = descriptor.value as? String {
            let data = Data(stringVal.utf8)
            future.result(Result.success(FlutterStandardTypedData(bytes: data)))
          } else if let cbuuid = descriptor.value as? CBUUID {
            future.result(Result.success(FlutterStandardTypedData(bytes: cbuuid.data)))
          } else {
            future.result(Result.success(FlutterStandardTypedData(bytes: Data())))
          }
        }
        return true
      }
      return false
    }
  }

  public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor descriptor: CBDescriptor, error: Error?) {
    descriptorWriteFutures.removeAll { future in
      if future.deviceId == peripheral.uuid.uuidString &&
        future.descriptorId == descriptor.uuid.uuidStr &&
        future.characteristicId == descriptor.characteristic?.uuid.uuidStr &&
        future.serviceId == descriptor.characteristic?.service?.uuid.uuidStr {
        if let flutterError = error?.toFlutterError() {
          UniversalBleLogger.shared.logError("WRITE_DESCRIPTOR_FAILED <- \(peripheral.uuid.uuidString) \(descriptor.uuid.uuidStr): \(flutterError.message ?? "")")
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
          UniversalBleLogger.shared.logError("SET_NOTIFY_FAILED <- \(peripheral.uuid.uuidString) \(characteristic.uuid.uuidStr): \(flutterError.message ?? "")")
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
    // Check if this is a read operation first
    let isReadOperation = characteristicReadFutures.contains { future in
      future.deviceId == peripheral.uuid.uuidString && future.characteristicId == characteristic.uuid.uuidStr && future.serviceId == characteristic.service?.uuid.uuidStr
    }

    // Log error appropriately based on operation type
    if let error {
      if isReadOperation {
        // This is a read error, but we'll log it in the read future handler below
        // to avoid duplicate logging
      } else {
        // This is a notify/indicate error
        UniversalBleLogger.shared.logError("NOTIFY_ERROR <- \(peripheral.uuid.uuidString) \(characteristic.uuid.uuidStr): \(error.localizedDescription)")
      }
    }

    if characteristic.isNotifying, let characteristicValue = characteristic.value {
      let preview = characteristicValue.prefix(8).map { String(format: "%02X", $0) }.joined()
      UniversalBleLogger.shared.logVerbose("NOTIFY <- \(peripheral.uuid.uuidString) \(characteristic.uuid.uuidStr) len=\(characteristicValue.count) data=\(preview)")
    }

    // Update callbackChannel if notifying
    if characteristic.isNotifying {
      if let characteristicValue = characteristic.value {
        callbackChannel.onValueChanged(
          deviceId: peripheral.uuid.uuidString,
          characteristicId: characteristic.uuid.uuidStr,
          value: FlutterStandardTypedData(bytes: characteristicValue),
          timestamp: Int64(Date().timeIntervalSince1970 * 1000)
        ) { _ in }
      }
    }

    if characteristicReadFutures.count == 0 {
      return
    }

    // Update futures for readValue
    characteristicReadFutures.removeAll { future in
      if future.deviceId == peripheral.uuid.uuidString && future.characteristicId == characteristic.uuid.uuidStr && future.serviceId == characteristic.service?.uuid.uuidStr {
        if let flutterError = error?.toFlutterError() {
          UniversalBleLogger.shared.logError("READ_FAILED <- \(peripheral.uuid.uuidString) \(characteristic.uuid.uuidStr): \(flutterError.message ?? "")")
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

  public func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
    rssiReadFutures.removeAll { future in
      if future.deviceId == peripheral.uuid.uuidString {
        if let flutterError = error?.toFlutterError() {
          UniversalBleLogger.shared.logError("READ_RSSI_FAILED <- \(peripheral.uuid.uuidString): \(flutterError.message ?? "")")
          future.result(Result.failure(flutterError))
        } else {
          future.result(Result.success(RSSI.int64Value))
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
        discoveredPeripherals[self] = peripheral
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
