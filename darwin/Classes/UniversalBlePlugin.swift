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

/// Host-app-facing configuration for the fork. Set values BEFORE
/// `GeneratedPluginRegistrant.register(with:)` is called in
/// `AppDelegate.application(_:didFinishLaunchingWithOptions:)` so that
/// the `CBCentralManager` instance created lazily on first plugin call
/// picks them up.
///
/// FIX-2B-A item A6: previously the iOS-only restore identifier was
/// hardcoded to `"com.wellbeinn.ble"` and `CBCentralManagerOptionRestoreIdentifierKey`
/// was always passed on iOS — that diverged from upstream behaviour
/// for any host app using this fork without wanting state restoration.
/// Expose the identifier as an opt-in instead: nil → upstream behaviour
/// (no restoration key, no `willRestoreState`); non-nil → opt in.
///
/// This is a temporary feature flag pending the upstream PR that will
/// expose the same option through the Pigeon-generated init API. When
/// that lands, this class can be removed in favour of the typed init
/// argument.
@objc public class UniversalBleSettings: NSObject {
  /// CoreBluetooth restore identifier. nil = upstream behaviour
  /// (no `CBCentralManagerOptionRestoreIdentifierKey`). Set to a
  /// stable reverse-DNS string (e.g. `"com.wellbeinn.ble"`) to opt
  /// the host app into state restoration so iOS can re-launch the
  /// terminated app on BLE peripheral events.
  @objc public static var restoreIdentifier: String?
}

private var discoveredPeripherals = [String: CBPeripheral]()

// Cache last advertised local name for peripherals
// since iOS and MacOS don't do that for system devices
private var advertisementNameCache = [String: String]()

private class BleCentralDarwin: NSObject, UniversalBlePlatformChannel, CBCentralManagerDelegate, CBPeripheralDelegate {
  var callbackChannel: UniversalBleCallbackChannel
  private var universalBleFilterUtil = UniversalBleFilterUtil()
  // iOS-only: pass `CBCentralManagerOptionRestoreIdentifierKey` ONLY when
  // the host app has opted in via `UniversalBleSettings.restoreIdentifier`
  // (FIX-2B-A item A6). nil identifier = upstream behaviour (no
  // restoration key, no `willRestoreState` callback). macOS does not
  // support state restoration — keep `nil` options there unconditionally.
  #if os(iOS)
    private lazy var manager: CBCentralManager = {
      if let restoreId = UniversalBleSettings.restoreIdentifier {
        return CBCentralManager(
          delegate: self,
          queue: nil,
          options: [CBCentralManagerOptionRestoreIdentifierKey: restoreId]
        )
      } else {
        return CBCentralManager(delegate: self, queue: nil)
      }
    }()
  #else
    private lazy var manager: CBCentralManager = .init(delegate: self, queue: nil)
  #endif
  private var availabilityStateUpdateHandlers: [(Result<Int64, Error>) -> Void] = []
  private var requestPermissionStateUpdateHandlers: [(Result<Void, Error>) -> Void] = []
  private var activeServiceDiscoveries: [String: UniversalBleAsyncServiceDiscovery] = [:]
  private var characteristicReadFutures = [CharacteristicReadFuture]()
  private var characteristicWriteFutures = [CharacteristicWriteFuture]()
  private var characteristicWriteWithoutResponseFutures = [CharacteristicWriteFuture]()
  private var characteristicNotifyFutures = [CharacteristicNotifyFuture]()
  private var discoverServicesFutures = [DiscoverServicesFuture]()
  private var rssiReadFutures = [RssiReadFuture]()
  private var isManageScanning = false
  private var autoConnectDevices = Set<String>()

  /// Peripherals delivered by `centralManager(_:willRestoreState:)`. We
  /// track them in a set so subsequent `didDiscoverServices` /
  /// `didDiscoverCharacteristicsFor` callbacks know to re-arm
  /// notifications on every notify-capable characteristic — restoration
  /// hands the app a peripheral but iOS does NOT preserve the per-app
  /// `setNotifyValue` subscriptions across termination, so a wake-up
  /// without re-subscription would never receive the band's
  /// notifications. Cleared per peripheral once re-subscription completes.
  /// FIX-2B-A item A7.
  private var restoredPeripherals = Set<String>()

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

  func setLogLevel(logLevel: UniversalBleLogLevel) throws {
    UniversalBleLogger.shared.setLogLevel(logLevel)
  }

  func connect(deviceId: String, autoConnect: Bool?) throws {
    let peripheral = try deviceId.getPeripheral(manager: manager)
    peripheral.delegate = self
    let shouldAutoConnect = autoConnect ?? false

    if shouldAutoConnect {
      autoConnectDevices.insert(deviceId)
      if #available(iOS 17.0, macOS 14.0, watchOS 10.0, tvOS 17.0, *) {
        let options: [String: Any] = [CBConnectPeripheralOptionEnableAutoReconnect: true]
        manager.connect(peripheral, options: options)
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
        manager.connect(peripheral)
      }
    } else {
      autoConnectDevices.remove(deviceId)
      manager.connect(peripheral)
    }
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
    rssiReadFutures.removeAll { future in
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

  func discoverServices(deviceId: String, withDescriptors: Bool, completion: @escaping (Result<[UniversalBleService], Error>) -> Void) {
    guard let peripheral = deviceId.findPeripheral(manager: manager) else {
      completion(
        Result.failure(createFlutterError(code: .deviceNotFound, message: "Unknown deviceId:\(deviceId)"))
      )
      return
    }

    // Check if discovery is already in progress
    if activeServiceDiscoveries[deviceId] != nil {
      UniversalBleLogger.shared.logWarning("Services discovery already in progress for :\(deviceId), waiting for completion.")
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
      withDescriptors: withDescriptors,
      completion: wrappedCompletion
    )

    activeServiceDiscoveries[deviceId] = discovery
    discovery.startDiscovery()
  }

  func setNotifiable(deviceId: String, service: String, characteristic: String, bleInputProperty: Int64, completion: @escaping (Result<Void, any Error>) -> Void) {
    UniversalBleLogger.shared.logDebug("SET_NOTIFY -> \(deviceId) \(service) \(characteristic) input=\(bleInputProperty)")
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

  func writeValue(deviceId: String, service: String, characteristic: String, value: FlutterStandardTypedData, bleOutputProperty: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
    UniversalBleLogger.shared.logDebug("WRITE -> \(deviceId) \(service) \(characteristic) len=\(value.data.count) property=\(bleOutputProperty)")
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

  // CoreBluetooth state restoration. iOS calls this on the central
  // manager's delegate (this object) when it re-launches a terminated
  // app to deliver pending peripheral events. We re-attach the peripheral
  // delegate so the existing callbacks (didDisconnect, didUpdateValue)
  // resume working, kick off discovery so we can re-subscribe to
  // notifications (FIX-2B-A item A7), and post a NotificationCenter
  // event so app-level code (e.g. the host's BLERestoreBridge) can
  // forward the event to a Flutter method channel without depending on
  // this plugin's internals.
  //
  // Note: this delegate callback only fires when the manager was
  // initialised with `CBCentralManagerOptionRestoreIdentifierKey` —
  // see `UniversalBleSettings.restoreIdentifier` above.
  func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
    let peripherals = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral]) ?? []
    var restoredIds: [String] = []
    for peripheral in peripherals {
      // Re-cache + re-attach delegate so subsequent callbacks land here.
      peripheral.delegate = self
      peripheral.saveCache()
      let id = peripheral.uuid.uuidString
      restoredIds.append(id)
      // FIX-2B-A item A7: track this peripheral as restored so the
      // didDiscoverServices / didDiscoverCharacteristicsFor callbacks
      // re-arm notify on every notify-capable characteristic.
      restoredPeripherals.insert(id)
      // If still connected, kick off service re-discovery so we can
      // re-subscribe to notifications. If disconnected, attempt to
      // reconnect — iOS will deliver the next event when the band
      // sends data.
      if peripheral.state == .connected {
        peripheral.discoverServices(nil)
      } else if peripheral.state != .connecting {
        central.connect(peripheral, options: nil)
      }
    }

    // FIX-2B-A item A5: defer the NotificationCenter post to the next
    // main-queue tick. CoreBluetooth invokes this delegate callback on
    // the queue passed to `CBCentralManager.init` (we use `nil` →
    // main queue), so the post would otherwise execute synchronously
    // inside the plugin's own init path on a cold-restoration launch.
    // If a host observer is being attached on the same main-thread
    // tick (typical for `BLERestoreBridge.attach` called right after
    // `GeneratedPluginRegistrant.register`), the synchronous post
    // would arrive BEFORE the observer is armed and be lost. Async
    // dispatch guarantees the observer registration runs first.
    let userInfo: [String: Any] = [
      "peripheralIds": restoredIds,
      "count": restoredIds.count,
    ]
    DispatchQueue.main.async {
      NotificationCenter.default.post(
        name: NSNotification.Name("UniversalBleRestoredState"),
        object: nil,
        userInfo: userInfo
      )
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
    let deviceId = peripheral.identifier.uuidString
    activeServiceDiscoveries[deviceId]?.handleDidDiscoverServices(peripheral, error: error)

    // FIX-2B-A item A7: post-restoration, the willRestoreState handler
    // calls `discoverServices(nil)` directly (no entry in
    // activeServiceDiscoveries), so we drive characteristic discovery
    // here too. didDiscoverCharacteristicsFor is where we re-arm the
    // notify subscriptions iOS dropped during termination.
    if restoredPeripherals.contains(deviceId), error == nil {
      for service in peripheral.services ?? [] {
        peripheral.discoverCharacteristics(nil, for: service)
      }
    }
  }

  public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    let deviceId = peripheral.identifier.uuidString
    activeServiceDiscoveries[deviceId]?.handleDidDiscoverCharacteristicsFor(peripheral, service: service, error: error)

    // FIX-2B-A item A7: re-arm notifications on every notify-capable
    // characteristic for restored peripherals. setNotifyValue(true)
    // is idempotent on already-notifying characteristics, but in the
    // restoration path none of them are armed (per-app subscriptions
    // are not preserved across termination). We can't be selective
    // here — the fork is not domain-aware enough to know which
    // characteristics the host app cares about — so we re-arm every
    // notify/indicate-capable one. Apps that explicitly disable a
    // characteristic later via UniversalBle.setNotify(false) re-take
    // control on the next write. The restored set is left populated
    // until the host re-issues an explicit subscription, so a
    // subsequent service rediscovery (e.g. after an OS-level
    // reconnect) re-applies the same recovery.
    if restoredPeripherals.contains(deviceId), error == nil {
      for char in service.characteristics ?? [] {
        let supportsNotify = char.properties.contains(.notify) || char.properties.contains(.indicate)
        if supportsNotify, !char.isNotifying {
          peripheral.setNotifyValue(true, for: char)
        }
      }
    }
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
