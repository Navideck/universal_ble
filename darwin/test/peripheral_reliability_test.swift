import CoreBluetooth
import Foundation

#if os(macOS)
  import FlutterMacOS
#else
  import Flutter
#endif

// Run with ./darwin/test/run_peripheral_reliability_tests.sh; no radio required.
@main
struct PeripheralReliabilityTests {
  static func main() {
    // Optional ObjC delegates can silently stop dispatching if argument labels
    // change. Keep every restoration/registration selector compiler checked.
    _ = #selector(UniversalBlePeripheralPlugin.peripheralManager(_:didAdd:error:))
    _ = #selector(UniversalBlePeripheralPlugin.peripheralManager(_:willRestoreState:))
    _ = #selector(UniversalBlePeripheralPlugin.peripheralManager(_:central:didSubscribeTo:))
    _ = #selector(UniversalBlePeripheralPlugin.peripheralManager(_:central:didUnsubscribeFrom:))
    _ = #selector(UniversalBlePeripheralPlugin.peripheralManager(_:didReceiveRead:))
    _ = #selector(UniversalBlePeripheralPlugin.peripheralManager(_:didReceiveWrite:))
    precondition(Int64(19).toCBATTErrorCode() == .unlikelyError)
    for value in ["1812", "00001812-0000-1000-8000-00805F9B34FB",
      "00001812-0000-1000-8000-00805f9b34fb", "180F"]
    {
      let uuid = UniversalBlePeripheralPlugin.advertisingServiceUuid(value)
      precondition(uuid.data.count == 2, "SIG services must use 16-bit advertising fields")
      precondition(uuid.uuid128Str == CBUUID(string: value).uuid128Str)
    }
    for value in ["12345678-1234-5678-9ABC-DEF012345678",
      "12345678-0000-1000-8000-00805F9B34FB"]
    {
      let uuid = UniversalBlePeripheralPlugin.advertisingServiceUuid(value)
      precondition(uuid.data.count == 16, "Do not truncate custom or 32-bit service UUIDs")
      precondition(uuid.uuid128Str == CBUUID(string: value).uuid128Str)
    }
    for value in ["2908", "00002908-0000-1000-8000-00805F9B34FB"] {
      let reference = PeripheralDescriptor(
        uuid: value, value: FlutterStandardTypedData(bytes: Data([3, 1])),
        permissions: [.readable]).toCBMutableDescriptor()
      precondition(reference.uuid.data.count == 2)
      precondition(reference.value as? Data == Data([3, 1]))
      // Native restoration reconstructs this descriptor before calling Dart.
      let restored = CBMutableDescriptor(type: reference.uuid, value: nil)
      precondition(restored.uuid.uuidString == "2908")
    }
    var queue = PeripheralNotificationQueue<Int>()
    var delivered = [Int]()
    queue.append(1)
    queue.drain { _ in false }
    queue.append(2)
    queue.drain {
      delivered.append($0)
      return true
    }
    precondition(delivered.isEmpty, "New release must not bypass blocked press")
    queue.resume()
    queue.drain {
      delivered.append($0)
      return true
    }
    precondition(delivered == [1, 2])
    queue.append(3)
    queue.drain { _ in false }
    queue.removeAll { $0 == 3 }
    queue.append(4)
    queue.drain {
      delivered.append($0)
      return true
    }
    precondition(delivered == [1, 2, 4], "Old session input must be discarded")

    let input = PeripheralCharacteristic(
      uuid: "2A4D", properties: [.read, .notify],
      permissions: [.readEncryptionRequired], value: FlutterStandardTypedData(bytes: Data([0, 0])),
      instanceId: "consumerInput", requireEncryptedNotifications: true)
    let cbInput = input.toCBCharacteristic()
    precondition(cbInput.value == nil)
    precondition(cbInput.properties.contains(.notifyEncryptionRequired))
    precondition(!cbInput.properties.contains(.notify))
    let output = PeripheralCharacteristic(
      uuid: "2A4D", properties: [.read, .write],
      permissions: [.readable, .writeable], value: FlutterStandardTypedData(bytes: Data([0])),
      instanceId: "keyboardOutput")
    precondition(output.toCBCharacteristic().value == nil)
    let staticRead = PeripheralCharacteristic(
      uuid: "2A4B", properties: [.read],
      permissions: [.readable], value: FlutterStandardTypedData(bytes: Data([1, 2])))
    precondition(staticRead.toCBCharacteristic().value == Data([1, 2]))

    let service = PeripheralService(uuid: "1812", primary: true, characteristics: [input, output])
      .toCBService()
    let registry = PeripheralServiceRegistry()
    registry.restore(
      service,
      identities: [
        ["uuid": "2A4D", "instanceId": "consumerInput"],
        ["uuid": "2A4D", "instanceId": "keyboardOutput"],
      ])
    precondition(
      registry.characteristic("2A4D", instanceId: "consumerInput") === service.characteristics![0])
    precondition(
      registry.characteristic("2A4D", instanceId: "keyboardOutput") === service.characteristics![1])
    registry.register(
      service, modelCharacteristics: [input, output],
      mutableCharacteristics: service.characteristics!)
    precondition(registry.allServices.count == 1, "Rebinding must reuse restored service")
    precondition(registry.service("00001812-0000-1000-8000-00805F9B34FB") === service)
    precondition(
      registry.characteristic("00002a4d-0000-1000-8000-00805f9b34fb", instanceId: "consumerInput")
        === service.characteristics![0])
    registry.remove(service)
    precondition(registry.characteristic("2A4D", instanceId: "consumerInput") == nil)
    print("Peripheral native reliability checks passed")
  }
}
