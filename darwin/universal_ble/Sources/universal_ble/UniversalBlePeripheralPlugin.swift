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
  private lazy var peripheralManager: CBPeripheralManager =
    .init(delegate: self, queue: nil, options: nil)
  private var centrals = [CBCentral]()

  init(callbackChannel: UniversalBlePeripheralCallback) {
    self.callbackChannel = callbackChannel
    super.init()
  }

  func initialize() throws {
    _ = peripheralManager.isAdvertising
  }

  func isSupported() throws -> Bool {
    true
  }

  func isAdvertising() throws -> Bool? {
    peripheralManager.isAdvertising
  }

  func stopAdvertising() throws {
    peripheralManager.stopAdvertising()
    callbackChannel.onAdvertisingStatusUpdate(advertising: false, error: nil) { _ in }
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
    timeout _: Int64?,
    manufacturerData _: PeripheralManufacturerData?,
    addManufacturerDataInScanResponse _: Bool
  ) throws {
    let cbServices = services.map { CBUUID(string: $0) }
    var advertisementData: [String: Any] = [CBAdvertisementDataServiceUUIDsKey: cbServices]
    if let localName {
      advertisementData[CBAdvertisementDataLocalNameKey] = localName
    }
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
      guard let central = centrals.first(where: { $0.identifier.uuidString == deviceId }) else {
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
    callbackChannel.onAdvertisingStatusUpdate(
      advertising: error == nil,
      error: error?.localizedDescription
    ) { _ in }
  }

  nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    callbackChannel.onBleStateChange(state: peripheral.state == .poweredOn) { _ in }
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
    if !centrals.contains(where: { $0.identifier == central.identifier }) {
      centrals.append(central)
    }
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
    centrals.removeAll { $0.identifier == central.identifier }
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
        guard let data = result?.value.toData() as Data? else {
          self.peripheralManager.respond(to: request, withResult: .requestNotSupported)
          return
        }
        request.value = data
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
}
