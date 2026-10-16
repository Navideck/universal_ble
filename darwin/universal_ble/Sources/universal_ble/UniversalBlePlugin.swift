import CoreBluetooth

#if os(iOS)
  import AccessorySetupKit
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

private class BleCentralDarwin: NSObject, UniversalBlePlatformChannel, CBCentralManagerDelegate, CBPeripheralDelegate, DartCallbackSender {
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
  private var availabilityStateUpdateHandlers: [CheckedContinuation<AvailabilityState, Error>] = []
  private var requestPermissionStateUpdateHandlers: [CheckedContinuation<Void, Error>] = []
  private var activeServiceDiscoveries: [String: UniversalBleAsyncServiceDiscovery] = [:]
  private var characteristicReadFutures = [CharacteristicReadFuture]()
  private var characteristicWriteFutures = [CharacteristicWriteFuture]()
  private var pendingWriteWithoutResponse = [PendingWriteWithoutResponse]()
  private var characteristicNotifyFutures = [CharacteristicNotifyFuture]()
  private var descriptorReadFutures = [DescriptorReadFuture]()
  private var descriptorWriteFutures = [DescriptorWriteFuture]()
  private var discoverServicesFutures = [DiscoverServicesFuture]()
  private var rssiReadFutures = [RssiReadFuture]()
  private var isManageScanning = false
  private var autoConnectDevices = Set<String>()
  #if os(iOS)
    private var accessorySetupManager: AnyObject?
  #endif

  // Per plugin instance (one per FlutterEngine): the peripheral lookup and the
  // last advertised names seen by this central. Keeping them here rather than at
  // file scope means a `connect()` never adopts a `CBPeripheral` created by
  // another engine, whose delegate is wired to an engine that may already be gone.
  private let peripheralCache = PeripheralCache()

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

  func getBluetoothAvailabilityState(continuation: CheckedContinuation<AvailabilityState, Error>) {
    #if os(iOS)
      if Self.hasBluetoothCentralBackgroundMode, !Self.hasBluetoothPermission {
        continuation.finish(.success(Self.availabilityStateFromAuthorization))
        return
      }
    #endif
    if manager.state != .unknown {
      continuation.finish(.success(manager.state.toAvailabilityState()))
    } else {
      availabilityStateUpdateHandlers.append(continuation)
      _ = manager
    }
  }

  func hasPermissions(withAndroidFineLocation _: Bool) throws -> Bool {
    return CBCentralManager.authorization == .allowedAlways
  }

  func requestPermissions(withAndroidFineLocation _: Bool, continuation: CheckedContinuation<Void, Error>) {
    if manager.state != .unknown {
      completePermissionRequest(continuation: continuation)
    } else {
      requestPermissionStateUpdateHandlers.append(continuation)
      _ = manager
    }
  }

  func completePermissionRequest(continuation: CheckedContinuation<Void, Error>) {
    let state = manager.state
    switch state {
    case .unauthorized:
      continuation.finish(.failure(createFlutterError(code: .bluetoothUnauthorized, message: "Not authorized to access Bluetooth")))
    case .unsupported:
      continuation.finish(.failure(createFlutterError(code: .notSupported, message: "Bluetooth is not supported")))
    default:
      continuation.finish(.success(()))
    }
  }

  func enableBluetooth(continuation: CheckedContinuation<Bool, Error>) {
    continuation.finish(Result.failure(createFlutterError(code: .notSupported)))
  }

  func disableBluetooth(continuation: CheckedContinuation<Bool, Error>) {
    continuation.finish(Result.failure(createFlutterError(code: .notSupported)))
  }

  func startScan(filter: UniversalScanFilter?, config: UniversalScanConfig?) throws {
    // If filter has any other filter other than official one
    let usesCustomFilters = filter?.usesCustomFilters ?? false

    // Apply services filter
    var withServices: [CBUUID] = try filter?.withServices.compactMap { $0 }.toCBUUID() ?? []

    if usesCustomFilters {
      UniversalBleLogger.shared.logInfo("Using Custom Filters")
      universalBleFilterUtil.configure(scanFilter: filter)
      withServices = []
    } else {
      universalBleFilterUtil.configure(scanFilter: nil)
    }

    // When the caller opts into de-duplication, omit the allow-duplicates key so
    // CoreBluetooth coalesces repeated discoveries of a peripheral instead of
    // reporting every advertisement packet (battery friendly). The Dart layer
    // enforces the once-per-scan-session guarantee. Defaults to `true` otherwise.
    let options: [String: Any]? = (config?.skipDuplicates == true)
      ? nil
      : [CBCentralManagerScanOptionAllowDuplicatesKey: true]

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

  func requestDevice(options: AppleAccessorySetupOptions, continuation: CheckedContinuation<UniversalDevicePickerResult, Error>) {
    #if os(iOS)
      guard #available(iOS 18.0, *) else {
        continuation.finish(.failure(createFlutterError(code: .notSupported, message: "AccessorySetupKit requires iOS 18 or later")))
        return
      }
      getAccessorySetupManager().showPicker(options: options, continuation: continuation)
    #else
      continuation.finish(.failure(createFlutterError(code: .notSupported, message: "AccessorySetupKit is only supported on iOS 18+")))
    #endif
  }

  func setLogLevel(logLevel: BleLogLevel) throws {
    UniversalBleLogger.shared.setLogLevel(logLevel)
  }

  func connect(deviceId: String, autoConnect: Bool?, platformConfig: ConnectionPlatformConfig?) throws {
    let peripheral = try peripheralCache.get(deviceId, manager: manager)
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
    guard let peripheral = peripheralCache.find(deviceId, manager: manager) else {
      sendToDart { try await $0.onConnectionChanged(deviceId: deviceId, connected: false, error: nil, errorCode: nil, nativeErrorCode: nil) }
      cleanUpConnection(deviceId: deviceId)
      return
    }
    if peripheral.state != CBPeripheralState.disconnected {
      manager.cancelPeripheralConnection(peripheral)
    }
    cleanUpConnection(deviceId: deviceId)
  }

  func getConnectionState(deviceId: String) throws -> BleConnectionState {
    guard let peripheral = peripheralCache.find(deviceId, manager: manager) else {
      return .disconnected
    }
    return peripheral.state.toBleConnectionState
  }

  func cleanUpConnection(deviceId: String) {
    let error = createFlutterError(code: .deviceDisconnected, message: "Device Disconnected")

    characteristicReadFutures.failAndRemoveAll(matching: deviceId, with: error)
    characteristicWriteFutures.failAndRemoveAll(matching: deviceId, with: error)
    pendingWriteWithoutResponse.failAndRemoveAll(matching: deviceId, with: error)
    characteristicNotifyFutures.failAndRemoveAll(matching: deviceId, with: error)
    descriptorReadFutures.failAndRemoveAll(matching: deviceId, with: error)
    descriptorWriteFutures.failAndRemoveAll(matching: deviceId, with: error)
    rssiReadFutures.failAndRemoveAll(matching: deviceId, with: error)

    // Cancel and fail any active service discovery for this device
    let matchingKeys = activeServiceDiscoveries.keys.filter { $0.caseInsensitiveCompare(deviceId) == .orderedSame }
    let discoveriesToCancel = matchingKeys.compactMap { activeServiceDiscoveries.removeValue(forKey: $0) }
    for discovery in discoveriesToCancel {
      discovery.cancel(error: error)
    }

    discoverServicesFutures.failAndRemoveAll(matching: deviceId, with: error)
  }

  func discoverServices(deviceId: String, withDescriptors: Bool, platformConfig _: DiscoverServicesPlatformConfig?, continuation: CheckedContinuation<[UniversalBleService], Error>) {
    guard let peripheral = peripheralCache.find(deviceId, manager: manager) else {
      continuation.finish(
        Result.failure(createFlutterError(code: .deviceNotFound, message: "Unknown deviceId:\(deviceId)"))
      )
      return
    }

    guard peripheral.state == .connected else {
      continuation.finish(
        Result.failure(createFlutterError(code: .deviceDisconnected, message: "Device is not connected"))
      )
      return
    }

    let normalizedDeviceId = peripheral.uuid.uuidString

    // Check if discovery is already in progress
    if activeServiceDiscoveries[normalizedDeviceId] != nil {
      UniversalBleLogger.shared.logWarning("Services discovery already in progress for :\(normalizedDeviceId), waiting for completion.")
      discoverServicesFutures.append(DiscoverServicesFuture(deviceId: normalizedDeviceId, continuation: continuation))
      return
    }

    let wrappedCompletion: (Result<[UniversalBleService], Error>) -> Void = { [weak self] result in
      guard let self = self else { return }
      continuation.finish(result)
      self.discoverServicesFutures.removeAll { future in
        if future.deviceId.caseInsensitiveCompare(normalizedDeviceId) == .orderedSame {
          future.complete(result)
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

  func setNotifiable(deviceId: String, service: String, characteristic: String, bleInputProperty: BleInputProperty, continuation: CheckedContinuation<Void, Error>) {
    UniversalBleLogger.shared.logDebug("SET_NOTIFY -> \(deviceId) \(service) \(characteristic) input=\(bleInputProperty)")
    guard let peripheral = peripheralCache.find(deviceId, manager: manager) else {
      continuation.finish(Result.failure(createFlutterError(code: .deviceNotFound, message: "Unknown deviceId:\(deviceId)")))
      return
    }

    guard let gattCharacteristic = peripheral.getCharacteristic(characteristic, of: service) else {
      continuation.finish(Result.failure(createFlutterError(code: .characteristicNotFound, message: "Unknown characteristic:\(characteristic)")))
      return
    }

    if bleInputProperty == .notification && !gattCharacteristic.properties.contains(.notify) {
      continuation.finish(Result.failure(createFlutterError(code: .characteristicDoesNotSupportNotify, message: "Characteristic does not support notify")))
      return
    }

    if bleInputProperty == .indication && !gattCharacteristic.properties.contains(.indicate) {
      continuation.finish(Result.failure(createFlutterError(code: .characteristicDoesNotSupportIndicate, message: "Characteristic does not support indicate")))
      return
    }

    let shouldNotify = bleInputProperty != .disabled
    peripheral.setNotifyValue(shouldNotify, for: gattCharacteristic)
    characteristicNotifyFutures.append(CharacteristicNotifyFuture(deviceId: deviceId, characteristicId: gattCharacteristic.uuid.uuidStr, serviceId: gattCharacteristic.service?.uuid.uuidStr, continuation: continuation))
  }

  func readValue(deviceId: String, service: String, characteristic: String, continuation: CheckedContinuation<FlutterStandardTypedData, Error>) {
    UniversalBleLogger.shared.logDebug("READ -> \(deviceId) \(service) \(characteristic)")
    guard let peripheral = peripheralCache.find(deviceId, manager: manager) else {
      continuation.finish(Result.failure(createFlutterError(code: .deviceNotFound, message: "Unknown deviceId:\(self)")))
      return
    }
    guard let gattCharacteristic = peripheral.getCharacteristic(characteristic, of: service) else {
      continuation.finish(Result.failure(createFlutterError(code: .characteristicNotFound, message: "Unknown characteristic:\(characteristic)")))
      return
    }
    if !gattCharacteristic.properties.contains(.read) {
      continuation.finish(Result.failure(createFlutterError(code: .characteristicDoesNotSupportRead, message: "Characteristic does not support read")))
      return
    }
    peripheral.readValue(for: gattCharacteristic)
    characteristicReadFutures.append(CharacteristicReadFuture(deviceId: deviceId, characteristicId: gattCharacteristic.uuid.uuidStr, serviceId: gattCharacteristic.service?.uuid.uuidStr, continuation: continuation))
  }

  func writeValue(deviceId: String, service: String, characteristic: String, value: FlutterStandardTypedData, bleOutputProperty: BleOutputProperty, continuation: CheckedContinuation<Void, Error>) {
    UniversalBleLogger.shared.logDebug("WRITE -> \(deviceId) \(service) \(characteristic) len=\(value.data.count) property=\(bleOutputProperty)")
    guard let peripheral = peripheralCache.find(deviceId, manager: manager) else {
      continuation.finish(Result.failure(createFlutterError(code: .deviceNotFound, message: "Unknown deviceId:\(self)")))
      return
    }
    guard let gattCharacteristic = peripheral.getCharacteristic(characteristic, of: service) else {
      continuation.finish(Result.failure(createFlutterError(code: .characteristicNotFound, message: "Unknown characteristic:\(characteristic)")))
      return
    }
    guard peripheral.state == .connected else {
      continuation.finish(Result.failure(createFlutterError(code: .deviceDisconnected, message: "Device Disconnected")))
      return
    }

    switch bleOutputProperty {
    case .withResponse:
      guard gattCharacteristic.properties.contains(.write) else {
        continuation.finish(Result.failure(createFlutterError(code: .characteristicDoesNotSupportWrite, message: "Characteristic does not support write withResponse")))
        return
      }
      characteristicWriteFutures.append(CharacteristicWriteFuture(deviceId: deviceId, characteristicId: gattCharacteristic.uuid.uuidStr, serviceId: gattCharacteristic.service?.uuid.uuidStr, continuation: continuation))
      peripheral.writeValue(value.data, for: gattCharacteristic, type: .withResponse)
    case .withoutResponse:
      guard gattCharacteristic.properties.contains(.writeWithoutResponse) else {
        continuation.finish(Result.failure(createFlutterError(code: .characteristicDoesNotSupportWriteWithoutResponse, message: "Characteristic does not support write withoutResponse")))
        return
      }

      if peripheral.canSendWriteWithoutResponse {
        peripheral.writeValue(value.data, for: gattCharacteristic, type: .withoutResponse)
        continuation.finish(Result.success(()))
      } else {
        pendingWriteWithoutResponse.append(
          PendingWriteWithoutResponse(
            deviceId: deviceId,
            characteristic: gattCharacteristic,
            data: value.data,
            continuation: continuation
          )
        )
      }
    }
  }

  func readDescriptorValue(deviceId: String, service: String, characteristic: String, descriptor: String, continuation: CheckedContinuation<FlutterStandardTypedData, Error>) {
    UniversalBleLogger.shared.logDebug("READ_DESCRIPTOR -> \(deviceId) \(service) \(characteristic) \(descriptor)")
    guard let peripheral = peripheralCache.find(deviceId, manager: manager) else {
      continuation.finish(Result.failure(createFlutterError(code: .deviceNotFound, message: "Unknown deviceId:\(deviceId)")))
      return
    }
    guard let gattDescriptor = peripheral.getDescriptor(descriptor, for: characteristic, of: service) else {
      continuation.finish(Result.failure(createFlutterError(code: .characteristicNotFound, message: "Descriptor not found:\(descriptor)")))
      return
    }
    peripheral.readValue(for: gattDescriptor)
    descriptorReadFutures.append(DescriptorReadFuture(
      deviceId: deviceId,
      descriptorId: gattDescriptor.uuid.uuidStr,
      characteristicId: gattDescriptor.characteristic?.uuid.uuidStr ?? characteristic,
      serviceId: gattDescriptor.characteristic?.service?.uuid.uuidStr ?? service,
      continuation: continuation
    ))
  }

  func writeDescriptorValue(deviceId: String, service: String, characteristic: String, descriptor: String, value: FlutterStandardTypedData, continuation: CheckedContinuation<Void, Error>) {
    UniversalBleLogger.shared.logDebug("WRITE_DESCRIPTOR -> \(deviceId) \(service) \(characteristic) \(descriptor) len=\(value.data.count)")
    guard let peripheral = peripheralCache.find(deviceId, manager: manager) else {
      continuation.finish(Result.failure(createFlutterError(code: .deviceNotFound, message: "Unknown deviceId:\(deviceId)")))
      return
    }
    guard let gattDescriptor = peripheral.getDescriptor(descriptor, for: characteristic, of: service) else {
      continuation.finish(Result.failure(createFlutterError(code: .characteristicNotFound, message: "Descriptor not found:\(descriptor)")))
      return
    }

    // CoreBluetooth throws NSInternalInconsistencyException if writeValue:forDescriptor: is called on CCCD (0x2902).
    // CoreBluetooth requires using setNotifyValue:forCharacteristic: for CCCD.
    let cccdUUID = CBUUID(string: CBUUIDClientCharacteristicConfigurationString)
    let fullCccdUUID = CBUUID(string: "00002902-0000-1000-8000-00805f9b34fb")
    if gattDescriptor.uuid == cccdUUID || gattDescriptor.uuid == fullCccdUUID {
      guard let gattCharacteristic = gattDescriptor.characteristic else {
        continuation.finish(Result.failure(createFlutterError(code: .characteristicNotFound, message: "Characteristic not found for descriptor")))
        return
      }
      let enable = value.data.contains { $0 != 0 }
      peripheral.setNotifyValue(enable, for: gattCharacteristic)
      characteristicNotifyFutures.append(CharacteristicNotifyFuture(
        deviceId: deviceId,
        characteristicId: gattCharacteristic.uuid.uuidStr,
        serviceId: gattCharacteristic.service?.uuid.uuidStr,
        continuation: continuation
      ))
      return
    }

    peripheral.writeValue(value.data, for: gattDescriptor)
    descriptorWriteFutures.append(DescriptorWriteFuture(
      deviceId: deviceId,
      descriptorId: gattDescriptor.uuid.uuidStr,
      characteristicId: gattDescriptor.characteristic?.uuid.uuidStr ?? characteristic,
      serviceId: gattDescriptor.characteristic?.service?.uuid.uuidStr ?? service,
      continuation: continuation
    ))
  }

  func requestMtu(deviceId: String, expectedMtu _: Int64, continuation: CheckedContinuation<Int64, Error>) {
    UniversalBleLogger.shared.logDebug("REQUEST_MTU -> \(deviceId)")
    guard let peripheral = peripheralCache.find(deviceId, manager: manager) else {
      continuation.finish(Result.failure(createFlutterError(code: .deviceNotFound, message: "Unknown deviceId:\(self)")))
      return
    }
    let mtu = peripheral.maximumWriteValueLength(for: CBCharacteristicWriteType.withoutResponse)
    let GATT_HEADER_LENGTH = 3
    let mtuResult = Int64(mtu + GATT_HEADER_LENGTH)
    continuation.finish(Result.success(mtuResult))
  }

  func requestConnectionPriority(
    deviceId _: String,
    priority _: BleConnectionPriority,
    continuation: CheckedContinuation<Void, Error>
  ) {
    continuation.finish(.failure(createFlutterError(code: .notSupported, message: "requestConnectionPriority is not supported on Apple platforms")))
  }

  func readRssi(deviceId: String, continuation: CheckedContinuation<Int64, Error>) {
    UniversalBleLogger.shared.logDebug("READ_RSSI -> \(deviceId)")
    guard let peripheral = peripheralCache.find(deviceId, manager: manager) else {
      continuation.finish(Result.failure(createFlutterError(code: .deviceNotFound, message: "Unknown deviceId:\(deviceId)")))
      return
    }
    peripheral.readRSSI()
    rssiReadFutures.append(RssiReadFuture(deviceId: deviceId, continuation: continuation))
  }

  func isPaired(deviceId _: String, continuation: CheckedContinuation<Bool, Error>) {
    continuation.finish(Result.failure(createFlutterError(code: .notSupported)))
  }

  func pair(deviceId _: String, continuation: CheckedContinuation<Bool, Error>) {
    continuation.finish(Result.failure(createFlutterError(code: .notImplemented)))
  }

  func unPair(deviceId: String, continuation: CheckedContinuation<Void, Error>) {
    #if os(iOS)
      guard #available(iOS 18.0, *) else {
        continuation.finish(.failure(createFlutterError(code: .notSupported, message: "AccessorySetupKit requires iOS 18 or later")))
        return
      }
      getAccessorySetupManager().removeAccessory(deviceId: deviceId, continuation: continuation)
    #else
      continuation.finish(.failure(createFlutterError(code: .notSupported, message: "AccessorySetupKit is only supported on iOS 18+")))
    #endif
  }

  #if os(iOS)
    @available(iOS 18.0, *)
    private func getAccessorySetupManager() -> AccessorySetupManager {
      if let manager = accessorySetupManager as? AccessorySetupManager, !manager.isInvalidated {
        return manager
      }
      let manager = AccessorySetupManager()
      accessorySetupManager = manager
      return manager
    }
  #endif

  func getSystemDevices(withServices: [String], continuation: CheckedContinuation<[UniversalBleScanResult], Error>) {
    var servicesFilter = withServices
    if servicesFilter.isEmpty {
      UniversalBleLogger.shared.logInfo("No services filter was set for getting system connected devices. Using default services...")

      // Add several generic services
      servicesFilter = ["1800", "1801", "180A", "180D", "1810", "181B", "1808", "181D", "1816", "1814", "181A", "1802", "1803", "1804", "1815", "1805", "1807", "1806", "1848", "185E", "180F", "1812", "180E", "1813"]
    }
    let filterCBUUID = servicesFilter.map { CBUUID(string: $0) }
    let bleDevices = manager.retrieveConnectedPeripherals(withServices: filterCBUUID)
    bleDevices.forEach { peripheralCache.remember($0) }
    continuation.finish(Result.success(bleDevices.map { peripheral in
      let id = peripheral.uuid.uuidString
      let name = peripheralCache.advertisedName(for: id)
        ?? peripheralCache.cached(id)?.name ?? peripheral.name ?? ""
      let timestampMicroseconds = Int64(Date().timeIntervalSince1970 * 1_000_000)
      return UniversalBleScanResult(
        deviceId: id,
        name: name,
        serviceData: nil,
        timestamp: timestampMicroseconds / 1000,
        timestampMicroseconds: timestampMicroseconds
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
        peripheralCache.remember(peripheral)
        let deviceId = peripheral.uuid.uuidString
        // Notify Dart if already connected; on a cold relaunch the Dart layer
        // re-subscribes on resume using the cached peripheral.
        if peripheral.state == .connected {
          sendToDart { try await $0.onConnectionChanged(deviceId: deviceId, connected: true, error: nil, errorCode: nil, nativeErrorCode: nil) }
        }
      }
    }
  #endif

  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    let state = central.state.toAvailabilityState()
    sendToDart { try await $0.onAvailabilityChanged(state: state) }
    // Complete Pending state handler
    availabilityStateUpdateHandlers.removeAll { handler in
      handler.resume(returning: state)
      return true
    }
    // Complete Pending permission request handler
    requestPermissionStateUpdateHandlers.removeAll { handler in
      completePermissionRequest(continuation: handler)
      return true
    }
  }

  public func centralManager(_: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
    // Store the discovered peripheral using its UUID as the key
    peripheralCache.remember(peripheral)

    // Extract manufacturer data and service UUIDs from the advertisement data
    let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
    let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])
    let serviceDataDict = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data]
    let connectable = advertisementData[CBAdvertisementDataIsConnectable] as? Bool

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
    peripheralCache.rememberAdvertisedName(displayName, for: peripheral.uuid.uuidString)

    // Apply custom filters and return early if the peripheral doesn't match
    if !universalBleFilterUtil.filterDevice(
      name: displayName,
      manufacturerData: universalManufacturerData,
      services: services,
      serviceData: serviceDataDict.map { Array($0.keys) }
    ) {
      return
    }

    let timestampMicroseconds = Int64(Date().timeIntervalSince1970 * 1_000_000)
    sendToDart { try await $0.onScanResult(result: UniversalBleScanResult(
        deviceId: peripheral.uuid.uuidString,
        name: displayName,
        isPaired: nil,
        rssi: RSSI as? Int64,
        manufacturerDataList: manufacturerDataList,
        serviceData: serviceData,
        services: services?.map { $0.uuidStr },
        timestamp: timestampMicroseconds / 1000,
        timestampMicroseconds: timestampMicroseconds,
        connectable: connectable
      ))
    }
  }

  public func centralManager(_: CBCentralManager, didConnect peripheral: CBPeripheral) {
    sendToDart { try await $0.onConnectionChanged(deviceId: peripheral.uuid.uuidString, connected: true, error: nil, errorCode: nil, nativeErrorCode: nil) }
  }

  private func handlePeripheralDisconnection(deviceId: String, error: Error?) {
    autoConnectDevices.remove(deviceId)
    sendToDart { try await $0.onConnectionChanged(
        deviceId: deviceId, connected: false, error: error?.localizedDescription, errorCode: error?.connectionErrorCode, nativeErrorCode: error?.nativeCode
      )
    }
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
    sendToDart { try await $0.onConnectionChanged(
        deviceId: peripheral.uuid.uuidString, connected: false, error: error?.localizedDescription, errorCode: error?.connectionErrorCode, nativeErrorCode: error?.nativeCode
      )
    }
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
    let deviceId = peripheral.uuid.uuidString
    while peripheral.state == .connected && peripheral.canSendWriteWithoutResponse {
      guard let index = pendingWriteWithoutResponse.firstIndex(where: { $0.deviceId == deviceId }) else {
        return
      }
      let pending = pendingWriteWithoutResponse.remove(at: index)
      peripheral.writeValue(pending.data, for: pending.characteristic, type: .withoutResponse)
      pending.complete(Result.success(()))
    }
  }

  public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
    guard let index = characteristicWriteFutures.firstIndex(where: {
      $0.deviceId == peripheral.uuid.uuidString &&
        $0.characteristicId == characteristic.uuid.uuidStr &&
        $0.serviceId == characteristic.service?.uuid.uuidStr
    }) else {
      return
    }

    let future = characteristicWriteFutures.remove(at: index)
    if let flutterError = error?.toFlutterError() {
      UniversalBleLogger.shared.logError("WRITE_FAILED <- \(peripheral.uuid.uuidString) \(characteristic.uuid.uuidStr): \(flutterError.message ?? "")")
      future.complete(Result.failure(flutterError))
    } else {
      future.complete(Result.success(()))
    }
  }

  public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
    guard let future = descriptorReadFutures.popFirst(where: {
      $0.deviceId == peripheral.uuid.uuidString &&
        $0.descriptorId == descriptor.uuid.uuidStr &&
        $0.characteristicId == descriptor.characteristic?.uuid.uuidStr &&
        $0.serviceId == descriptor.characteristic?.service?.uuid.uuidStr
    }) else {
      return
    }

    if let flutterError = error?.toFlutterError() {
      UniversalBleLogger.shared.logError("READ_DESCRIPTOR_FAILED <- \(peripheral.uuid.uuidString) \(descriptor.uuid.uuidStr): \(flutterError.message ?? "")")
      future.complete(Result.failure(flutterError))
    } else if let valueData = descriptor.value as? Data {
      future.complete(Result.success(FlutterStandardTypedData(bytes: valueData)))
    } else if let numberVal = descriptor.value as? NSNumber {
      var val = numberVal.uint16Value
      let data = Data(bytes: &val, count: MemoryLayout<UInt16>.size)
      future.complete(Result.success(FlutterStandardTypedData(bytes: data)))
    } else if let stringVal = descriptor.value as? String {
      let data = Data(stringVal.utf8)
      future.complete(Result.success(FlutterStandardTypedData(bytes: data)))
    } else if let cbuuid = descriptor.value as? CBUUID {
      future.complete(Result.success(FlutterStandardTypedData(bytes: cbuuid.data)))
    } else {
      future.complete(Result.success(FlutterStandardTypedData(bytes: Data())))
    }
  }

  public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor descriptor: CBDescriptor, error: Error?) {
    guard let future = descriptorWriteFutures.popFirst(where: {
      $0.deviceId == peripheral.uuid.uuidString &&
        $0.descriptorId == descriptor.uuid.uuidStr &&
        $0.characteristicId == descriptor.characteristic?.uuid.uuidStr &&
        $0.serviceId == descriptor.characteristic?.service?.uuid.uuidStr
    }) else {
      return
    }

    if let flutterError = error?.toFlutterError() {
      UniversalBleLogger.shared.logError("WRITE_DESCRIPTOR_FAILED <- \(peripheral.uuid.uuidString) \(descriptor.uuid.uuidStr): \(flutterError.message ?? "")")
      future.complete(Result.failure(flutterError))
    } else {
      future.complete(Result.success({}()))
    }
  }

  public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
    guard let future = characteristicNotifyFutures.popFirst(where: {
      $0.deviceId == peripheral.uuid.uuidString &&
        $0.characteristicId == characteristic.uuid.uuidStr &&
        $0.serviceId == characteristic.service?.uuid.uuidStr
    }) else {
      return
    }

    if let flutterError = error?.toFlutterError() {
      UniversalBleLogger.shared.logError("SET_NOTIFY_FAILED <- \(peripheral.uuid.uuidString) \(characteristic.uuid.uuidStr): \(flutterError.message ?? "")")
      future.complete(Result.failure(flutterError))
    } else {
      future.complete(Result.success({}()))
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
        sendToDart { try await $0.onValueChanged(
            deviceId: peripheral.uuid.uuidString,
            characteristicId: characteristic.uuid.uuidStr,
            value: FlutterStandardTypedData(bytes: characteristicValue),
            timestamp: Int64(Date().timeIntervalSince1970 * 1000)
          )
        }
      }
    }

    if characteristicReadFutures.count == 0 {
      return
    }

    guard let future = characteristicReadFutures.popFirst(where: {
      $0.deviceId == peripheral.uuid.uuidString &&
        $0.characteristicId == characteristic.uuid.uuidStr &&
        $0.serviceId == characteristic.service?.uuid.uuidStr
    }) else {
      return
    }

    if let flutterError = error?.toFlutterError() {
      UniversalBleLogger.shared.logError("READ_FAILED <- \(peripheral.uuid.uuidString) \(characteristic.uuid.uuidStr): \(flutterError.message ?? "")")
      future.complete(Result.failure(flutterError))
    } else if let characteristicValue = characteristic.value {
      future.complete(Result.success(FlutterStandardTypedData(bytes: characteristicValue)))
    } else {
      future.complete(Result.failure(createFlutterError(code: .readFailed, message: "No value")))
    }
  }

  public func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
    guard let future = rssiReadFutures.popFirst(where: {
      $0.deviceId == peripheral.uuid.uuidString
    }) else {
      return
    }

    if let flutterError = error?.toFlutterError() {
      UniversalBleLogger.shared.logError("READ_RSSI_FAILED <- \(peripheral.uuid.uuidString): \(flutterError.message ?? "")")
      future.complete(Result.failure(flutterError))
    } else {
      future.complete(Result.success(RSSI.int64Value))
    }
  }

  // MARK: - Pigeon 29 async adapters
  //
  // The generated protocol is `async` since Pigeon 29. Each operation below has
  // an `async` adapter that bridges the protocol to a continuation-based
  // implementation (the overload taking a `CheckedContinuation`), so the pending
  // request registries hold continuations rather than completion closures.
  //
  // TODO: Wire task cancellation (withTaskCancellationHandler) so a cancelled
  // Dart call removes its pending future instead of leaving the continuation
  // suspended until the CoreBluetooth callback arrives.

  func getBluetoothAvailabilityState() async throws -> AvailabilityState {
    try await withCheckedThrowingContinuation { continuation in
      getBluetoothAvailabilityState(continuation: continuation)
    }
  }

  func requestPermissions(withAndroidFineLocation fineLocation: Bool) async throws {
    try await withCheckedThrowingContinuation { continuation in
      requestPermissions(withAndroidFineLocation: fineLocation, continuation: continuation)
    }
  }

  func enableBluetooth() async throws -> Bool {
    try await withCheckedThrowingContinuation { continuation in
      enableBluetooth(continuation: continuation)
    }
  }

  func disableBluetooth() async throws -> Bool {
    try await withCheckedThrowingContinuation { continuation in
      disableBluetooth(continuation: continuation)
    }
  }

  func requestDevice(options: AppleAccessorySetupOptions) async throws -> UniversalDevicePickerResult {
    try await withCheckedThrowingContinuation { continuation in
      requestDevice(options: options, continuation: continuation)
    }
  }

  func discoverServices(deviceId: String, withDescriptors: Bool, platformConfig: DiscoverServicesPlatformConfig?) async throws -> [UniversalBleService] {
    try await withCheckedThrowingContinuation { continuation in
      discoverServices(deviceId: deviceId, withDescriptors: withDescriptors, platformConfig: platformConfig, continuation: continuation)
    }
  }

  func setNotifiable(deviceId: String, service: String, characteristic: String, bleInputProperty: BleInputProperty) async throws {
    try await withCheckedThrowingContinuation { continuation in
      setNotifiable(deviceId: deviceId, service: service, characteristic: characteristic, bleInputProperty: bleInputProperty, continuation: continuation)
    }
  }

  func readValue(deviceId: String, service: String, characteristic: String) async throws -> FlutterStandardTypedData {
    try await withCheckedThrowingContinuation { continuation in
      readValue(deviceId: deviceId, service: service, characteristic: characteristic, continuation: continuation)
    }
  }

  func writeValue(deviceId: String, service: String, characteristic: String, value: FlutterStandardTypedData, bleOutputProperty: BleOutputProperty) async throws {
    try await withCheckedThrowingContinuation { continuation in
      writeValue(deviceId: deviceId, service: service, characteristic: characteristic, value: value, bleOutputProperty: bleOutputProperty, continuation: continuation)
    }
  }

  func readDescriptorValue(deviceId: String, service: String, characteristic: String, descriptor: String) async throws -> FlutterStandardTypedData {
    try await withCheckedThrowingContinuation { continuation in
      readDescriptorValue(deviceId: deviceId, service: service, characteristic: characteristic, descriptor: descriptor, continuation: continuation)
    }
  }

  func writeDescriptorValue(deviceId: String, service: String, characteristic: String, descriptor: String, value: FlutterStandardTypedData) async throws {
    try await withCheckedThrowingContinuation { continuation in
      writeDescriptorValue(deviceId: deviceId, service: service, characteristic: characteristic, descriptor: descriptor, value: value, continuation: continuation)
    }
  }

  func requestMtu(deviceId: String, expectedMtu: Int64) async throws -> Int64 {
    try await withCheckedThrowingContinuation { continuation in
      requestMtu(deviceId: deviceId, expectedMtu: expectedMtu, continuation: continuation)
    }
  }

  func requestConnectionPriority(deviceId: String, priority: BleConnectionPriority) async throws {
    try await withCheckedThrowingContinuation { continuation in
      requestConnectionPriority(deviceId: deviceId, priority: priority, continuation: continuation)
    }
  }

  func readRssi(deviceId: String) async throws -> Int64 {
    try await withCheckedThrowingContinuation { continuation in
      readRssi(deviceId: deviceId, continuation: continuation)
    }
  }

  func isPaired(deviceId: String) async throws -> Bool {
    try await withCheckedThrowingContinuation { continuation in
      isPaired(deviceId: deviceId, continuation: continuation)
    }
  }

  func pair(deviceId: String) async throws -> Bool {
    try await withCheckedThrowingContinuation { continuation in
      pair(deviceId: deviceId, continuation: continuation)
    }
  }

  func unPair(deviceId: String) async throws {
    try await withCheckedThrowingContinuation { continuation in
      unPair(deviceId: deviceId, continuation: continuation)
    }
  }

  func getSystemDevices(withServices: [String]) async throws -> [UniversalBleScanResult] {
    try await withCheckedThrowingContinuation { continuation in
      getSystemDevices(withServices: withServices, continuation: continuation)
    }
  }

}

#if os(iOS)
  @available(iOS 18.0, *)
  private final class AccessorySetupManager {
    private let session = ASAccessorySession()
    private var isActivated = false
    /// `true` once the system invalidates the session. A session cannot be reused
    /// after that, so the owner drops this manager and builds a fresh one.
    private(set) var isInvalidated = false
    private var activationActions: [(run: () -> Void, cancel: () -> Void)] = []
    private var pickerCompletion: CheckedContinuation<UniversalDevicePickerResult, Error>?
    private var selectedIdentifier: UUID?
    private var selectedName: String?

    init() {
      session.activate(on: .main) { [weak self] event in
        self?.handle(event)
      }
    }

    func showPicker(options: AppleAccessorySetupOptions, continuation: CheckedContinuation<UniversalDevicePickerResult, Error>) {
      guard pickerCompletion == nil else {
        continuation.finish(.failure(createFlutterError(code: .invalidAction, message: "The accessory picker is already open")))
        return
      }
      var items: [ASPickerDisplayItem] = []
      for item in options.items {
        guard let image = UIImage(named: item.imageAsset, in: Bundle.main, compatibleWith: nil) else {
          continuation.finish(.failure(createFlutterError(code: .illegalArgument, message: "Image asset not found: \(item.imageAsset)")))
          return
        }
        let descriptor = ASDiscoveryDescriptor()
        descriptor.bluetoothServiceUUID = CBUUID(string: item.serviceUuid)
        descriptor.bluetoothNameSubstring = item.nameSubstring
        if item.requiresImmediateRange == true {
          descriptor.bluetoothRange = .immediate
        }
        if item.supportsBluetoothPairing == true {
          descriptor.supportedOptions = .bluetoothPairingLE
        }
        items.append(ASPickerDisplayItem(name: item.displayName, productImage: image, descriptor: descriptor))
      }
      guard !items.isEmpty else {
        continuation.finish(.failure(createFlutterError(code: .illegalArgument, message: "At least one picker item is required")))
        return
      }

      pickerCompletion = continuation
      selectedIdentifier = nil
      selectedName = nil
      whenActivated { [weak self] in
        guard let self else { return }
        session.showPicker(for: items) { [weak self] error in
          guard let self, let error else { return }
          self.completePicker(.failure(self.pickerError(error)))
        }
      }
    }

    func removeAccessory(deviceId: String, continuation: CheckedContinuation<Void, Error>) {
      guard let identifier = UUID(uuidString: deviceId) else {
        continuation.finish(.failure(createFlutterError(code: .illegalArgument, message: "Invalid deviceId: \(deviceId)")))
        return
      }
      whenActivated({
        [weak self] in
        guard let self else { return }
        guard let accessory = session.accessories.first(where: { $0.bluetoothIdentifier == identifier }) else {
          continuation.finish(.failure(createFlutterError(code: .deviceNotFound, message: "Accessory is not managed by AccessorySetupKit: \(deviceId)")))
          return
        }
        session.removeAccessory(accessory) { error in
          if let error {
            continuation.finish(.failure(error.toFlutterError()))
          } else {
            continuation.finish(.success(()))
          }
        }
      }, onCancel: {
        continuation.finish(.failure(createFlutterError(code: .failed, message: "Accessory setup session was invalidated")))
      })
    }

    private func whenActivated(_ action: @escaping () -> Void, onCancel: @escaping () -> Void = {}) {
      if isActivated {
        action()
      } else {
        activationActions.append((run: action, cancel: onCancel))
      }
    }

    private func handle(_ event: ASAccessoryEvent) {
      switch event.eventType {
      case .activated:
        isActivated = true
        let actions = activationActions
        activationActions.removeAll()
        actions.forEach { $0.run() }
      // `.accessoryAdded` is the documented event for a pick. It's the only
      // event that carries the accessory the person selected, so capture it
      // there. Events seen outside a picker are ignored: `showPicker` resets the
      // selection before each session.
      case .accessoryAdded:
        guard pickerCompletion != nil,
          let accessory = event.accessory,
          let identifier = accessory.bluetoothIdentifier
        else { break }
        selectedIdentifier = identifier
        selectedName = accessory.displayName
      // A fallback for iOS 18 builds that have been reported to deliver the pick
      // as `.accessoryChanged` instead. That event is also emitted for unrelated
      // state changes, so only use it while no selection has been captured, and
      // never let it clear an existing selection.
      case .accessoryChanged:
        guard pickerCompletion != nil, selectedIdentifier == nil,
          let accessory = event.accessory,
          let identifier = accessory.bluetoothIdentifier
        else { break }
        selectedIdentifier = identifier
        selectedName = accessory.displayName
      case .pickerDidDismiss:
        if let selectedIdentifier {
          completePicker(.success(UniversalDevicePickerResult(deviceId: selectedIdentifier.uuidString, name: selectedName)))
        } else {
          completePicker(.failure(createFlutterError(code: .operationCancelled, message: "Accessory setup was cancelled")))
        }
      case .pickerSetupFailed:
        completePicker(.failure(event.error?.toFlutterError() ?? createFlutterError(code: .failed, message: "Accessory setup failed")))
      case .invalidated:
        // The session can't be used again. Fail any action that was still waiting
        // for activation, then flag this manager so the owner discards it and
        // creates a new session on the next request.
        isInvalidated = true
        isActivated = false
        let pending = activationActions
        activationActions.removeAll()
        pending.forEach { $0.cancel() }
        completePicker(.failure(event.error?.toFlutterError() ?? createFlutterError(code: .failed, message: "Accessory setup session was invalidated")))
      default:
        break
      }
    }

    /// AccessorySetupKit reports the person dismissing the picker as `NSError`
    /// code 700, which has no mapping in `mapErrorCodeToEnum`. Translate it to a
    /// cancellation so callers don't see a generic `unknownError`.
    private func pickerError(_ error: Error) -> Error {
      if (error as NSError).code == 700 {
        return createFlutterError(code: .operationCancelled, message: "Accessory setup was cancelled")
      }
      return error.toFlutterError()
    }

    private func completePicker(_ result: Result<UniversalDevicePickerResult, Error>) {
      guard let continuation = pickerCompletion else { return }
      pickerCompletion = nil
      selectedIdentifier = nil
      selectedName = nil
      continuation.finish(result)
    }
  }
#endif

/// Lookup of the `CBPeripheral`s this central has seen, plus the last advertised
/// local name for each (iOS/macOS don't expose advertised names on system
/// devices). One instance per `BleCentralDarwin`, i.e. per FlutterEngine.
private final class PeripheralCache {
  private var discovered = [String: CBPeripheral]()
  private var advertisedNames = [String: String]()

  func remember(_ peripheral: CBPeripheral) {
    discovered[peripheral.uuid.uuidString] = peripheral
  }

  func rememberAdvertisedName(_ name: String?, for deviceId: String) {
    // A nil name removes any previous entry, like the dictionary assignment did.
    advertisedNames[deviceId] = name
  }

  func advertisedName(for deviceId: String) -> String? {
    advertisedNames[deviceId]
  }

  /// Only the peripherals this cache already holds, without asking the system.
  func cached(_ deviceId: String) -> CBPeripheral? {
    discovered[deviceId]
  }

  func find(_ deviceId: String, manager: CBCentralManager) -> CBPeripheral? {
    if let peripheral = discovered[deviceId] {
      return peripheral
    }
    if let uuid = UUID(uuidString: deviceId) {
      let peripherals = manager.retrievePeripherals(withIdentifiers: [uuid])
      if let peripheral = peripherals.first {
        discovered[deviceId] = peripheral
        return peripheral
      }
    }
    return nil
  }

  func get(_ deviceId: String, manager: CBCentralManager) throws -> CBPeripheral {
    guard let peripheral = find(deviceId, manager: manager) else {
      throw createFlutterError(code: .deviceNotFound, message: "Unknown deviceId:\(deviceId)")
    }
    return peripheral
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
