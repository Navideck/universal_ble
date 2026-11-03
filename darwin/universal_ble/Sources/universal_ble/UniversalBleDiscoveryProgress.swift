import Foundation

/// The bookkeeping of one service discovery, kept apart from CoreBluetooth so
/// it can be tested on its own (`Tests/run_discovery_progress_test.sh`, on a
/// Mac).
///
/// Every service and characteristic is identified by a key the caller picks.
/// The plugin passes the `ObjectIdentifier` of each `CBService` and
/// `CBCharacteristic`, so two services with one UUID are two entries. A GATT
/// database can hold two services with one UUID (an Android GATT server has
/// been seen carrying Google's FEF3 twice after it restarted). Keyed by UUID
/// string, the second copy's characteristics were written over the first
/// copy's entry, the second entry was never filled, and the discovery never
/// completed before its timeout.
struct UniversalBleDiscoveryProgress<Service: Hashable, Characteristic: Hashable> {
  /// Whether a service counts as done only once the descriptors of every one
  /// of its characteristics are known too.
  let withDescriptors: Bool

  /// The services this discovery was started with, in the peripheral's
  /// order. A key given twice is kept once.
  let services: [Service]

  private let members: Set<Service>
  private var characteristicsOf: [Service: [Characteristic]] = [:]
  private var descriptorsKnown: Set<Characteristic> = []

  init(services: [Service], withDescriptors: Bool) {
    var seen = Set<Service>()
    self.services = services.filter { seen.insert($0).inserted }
    self.members = seen
    self.withDescriptors = withDescriptors
  }

  /// Records `service`'s characteristics. False, and nothing recorded, for a
  /// service this discovery was not started with.
  @discardableResult
  mutating func characteristicsDiscovered(
    for service: Service, _ characteristics: [Characteristic]
  ) -> Bool {
    guard members.contains(service) else { return false }
    characteristicsOf[service] = characteristics
    return true
  }

  /// Records that `characteristic`'s descriptors are known.
  mutating func descriptorsDiscovered(for characteristic: Characteristic) {
    descriptorsKnown.insert(characteristic)
  }

  /// Whether `service` is done: its characteristics known and, with
  /// descriptors, the descriptors of each of them.
  func isComplete(_ service: Service) -> Bool {
    guard let characteristics = characteristicsOf[service] else { return false }
    return !withDescriptors || characteristics.allSatisfy { descriptorsKnown.contains($0) }
  }

  /// Whether every service is done. True at once when there are none.
  var isComplete: Bool { services.allSatisfy { isComplete($0) } }
}
