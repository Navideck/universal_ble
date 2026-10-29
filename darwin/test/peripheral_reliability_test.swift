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

    var reports = PeripheralNotificationQueue<(central: Int, characteristic: Int)>()
    reports.append((1, 1))
    reports.append((1, 2))
    reports.append((2, 1))
    reports.drain { _ in false }
    reports.removeAll { $0.central == 1 && $0.characteristic == 1 }
    reports.resume()
    var remaining = [Int]()
    reports.drain { remaining.append($0.central * 10 + $0.characteristic); return true }
    precondition(remaining == [12, 21], "Unsubscribe must preserve other reports and clients")

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
    testServiceRegistrationOrder(input: input, output: output)
    testWriteRequests()
    print("Peripheral native reliability checks passed")
  }

  static func testServiceRegistrationOrder(
    input: PeripheralCharacteristic, output: PeripheralCharacteristic
  ) {
    let information = PeripheralService(uuid: "180A", primary: true, characteristics: [])
    let battery = PeripheralService(uuid: "180F", primary: true, characteristics: [])
    let hid = PeripheralService(uuid: "1812", primary: true, characteristics: [input, output])
    var models = PeripheralServiceModels()
    for model in [information, battery, hid] { models.set(model) }
    let initialOrder = models.values.map { CBUUID(string: $0.uuid).uuid128Str }
    let registry = PeripheralServiceRegistry()
    for _ in 0..<3 {
      // Adapter loss clears native objects, but retains the model order used
      // by the next poweredOn registration pass.
      registry.clear()
      for model in models.values {
        let service = model.toCBService()
        registry.register(
          service, modelCharacteristics: model.characteristics,
          mutableCharacteristics: service.characteristics ?? [])
      }
      precondition(registry.allServices.map { $0.uuid.uuid128Str } == initialOrder)
    }
    let reboundBattery = PeripheralService(
      uuid: "0000180f-0000-1000-8000-00805f9b34fb", primary: true, characteristics: [])
    models.set(reboundBattery)
    precondition(models.values.map { CBUUID(string: $0.uuid).uuid128Str } == initialOrder)
    models.remove("0000180F-0000-1000-8000-00805F9B34FB")
    precondition(models.values.map { $0.uuid } == ["180A", "1812"])
    models.set(battery)
    precondition(models.values.map { $0.uuid } == ["180A", "1812", "180F"])
    models.removeAll()
    precondition(models.values.isEmpty)

    let restoredHid = hid.toCBService()
    let restoredBattery = battery.toCBService()
    registry.clear()
    for service in [restoredHid, restoredBattery] {
      models.reserve(service.uuid.uuidString)
      registry.restore(
        service, identities: service === restoredHid
          ? [["uuid": "2A4D", "instanceId": "consumerInput"],
            ["uuid": "2A4D", "instanceId": "keyboardOutput"]] : [])
    }
    // Dart can rebind in a different order from native restoration. Keep the
    // native publication order and characteristic identities in either case.
    for model in [battery, hid] {
      models.set(model)
      let service = registry.service(model.uuid)!
      registry.register(
        service, modelCharacteristics: model.characteristics,
        mutableCharacteristics: service.characteristics ?? [])
    }
    precondition(models.values.map { $0.uuid } == ["1812", "180F"])
    precondition(registry.service("1812") === restoredHid)
    precondition(
      registry.characteristic("2A4D", instanceId: "consumerInput")
        === restoredHid.characteristics![0])
    precondition(
      registry.characteristic("2A4D", instanceId: "keyboardOutput")
        === restoredHid.characteristics![1])
    models.reserve("180A")
    models.remove("180A")
    models.set(information)
    precondition(models.values.map { $0.uuid } == ["1812", "180F", "180A"])
  }

  static func testWriteRequests() {
    var generation = 0
    var events = [() -> Void]()
    var completions = [(Result<PeripheralWriteRequestResult?, PigeonError>) -> Void]()
    var mutations = [Int]()
    var responses = [(request: Int, status: CBATTError.Code)]()
    func receive(_ requests: [Int]) {
      let capturedGeneration = generation
      UniversalBlePeripheralPlugin.handleWriteRequests(
        requests,
        isCurrent: { capturedGeneration == generation },
        emit: { events.append($0) },
        dispatch: { request, completion in
          mutations.append(request)
          completions.append(completion)
        },
        respond: { responses.append(($0, $1)) })
    }
    receive([])
    precondition(events.isEmpty && mutations.isEmpty && responses.isEmpty)
    receive([1, 2])
    precondition(events.isEmpty && mutations.isEmpty && completions.isEmpty)
    precondition(responses.count == 1 && responses[0].request == 1)
    precondition(responses[0].status == .requestNotSupported)

    receive([3])
    events.removeFirst()()
    precondition(mutations == [3] && responses.count == 1)
    completions.removeFirst()(.success(nil))
    precondition(responses.count == 2 && responses[1].status == .success)

    receive([4])
    events.removeFirst()()
    completions.removeFirst()(.success(PeripheralWriteRequestResult(
      status: Int64(CBATTError.Code.writeNotPermitted.rawValue))))
    precondition(responses.count == 3 && responses[2].status == .writeNotPermitted)

    receive([5])
    events.removeFirst()()
    completions.removeFirst()(.failure(PigeonError(code: "test", message: nil, details: nil)))
    precondition(responses.count == 4 && responses[3].status == .requestNotSupported)

    receive([6])
    generation += 1  // Adapter/service loss while an event waits for Dart.
    events.removeFirst()()
    precondition(mutations == [3, 4, 5] && completions.isEmpty)
    precondition(responses.count == 5 && responses[4].status == .requestNotSupported)

    receive([7])
    events.removeFirst()()
    generation += 1  // Adapter/service loss during an asynchronous Dart handler.
    completions.removeFirst()(.success(nil))
    precondition(mutations == [3, 4, 5, 7])
    precondition(responses.count == 6 && responses[5].status == .requestNotSupported)
    precondition(responses.map { $0.request } == [1, 3, 4, 5, 6, 7])
    precondition(events.isEmpty && completions.isEmpty)
  }

}
