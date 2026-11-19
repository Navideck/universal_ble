import Foundation

/// Which engine of a process owns the CoreBluetooth central state restoration
/// identifier.
///
/// CoreBluetooth binds a restoration identifier to one central manager per
/// process: a second `CBCentralManager` created with an identifier that is
/// already in use is reported as `.unsupported`. An app that runs several
/// `FlutterEngine`s in one process therefore has to pick one engine to restore
/// and let the others create managers without an identifier.
///
/// This type holds only that bookkeeping, without CoreBluetooth, so it can be
/// tested on its own (`Tests/run_central_restoration_owner_test.sh`, on a Mac).
///
/// One `WeakOwner` box is kept per identifier that has ever been claimed, and
/// it holds its owner weakly, so an identifier becomes available again as soon
/// as its owner is deallocated, however and whenever that happens. A box is
/// only removed by an explicit `release` from its owner; otherwise it stays
/// with a nil value, which bounds the map by the number of distinct identifiers
/// rather than by the number of engines.
///
/// The instance is usually shared by every engine of a process, and nothing
/// above it constrains which thread an engine registers or is deallocated on,
/// so every access to the map is serialised by `lock` instead of assuming
/// main-thread affinity.
final class UniversalBleCentralRestorationOwner {
  private final class WeakOwner {
    weak var value: AnyObject?

    init(_ value: AnyObject) {
      self.value = value
    }
  }

  /// Serialises access to `owners`.
  ///
  /// Without it, two concurrent claims can both see an identifier as free and
  /// both report success (nothing is wrong with the map itself, which is an
  /// ordinary value type, so each of them writes its own copy and one claim is
  /// silently lost), and a read can race a reallocating write. Deliberately not
  /// a `precondition(Thread.isMainThread)`: a claim runs on whichever thread
  /// registers an engine, and a precondition would trap in release builds on a
  /// path the plugin does not control.
  private let lock = NSLock()

  private var owners: [String: WeakOwner] = [:]

  /// The live owner of `identifier`, or nil when the identifier is available.
  ///
  /// Test-facing: only the ownership harness reads this, to assert which engine
  /// holds an identifier. The plugin takes its decisions from `claim`'s result.
  func owner(of identifier: String) -> AnyObject? {
    lock.lock()
    defer { lock.unlock() }
    return owners[identifier]?.value
  }

  /// Takes `identifier` for `owner`, and returns whether `owner` holds it
  /// afterwards.
  ///
  /// The first live owner wins: a claim succeeds when the identifier is
  /// available or when `owner` already holds it (a claim is idempotent for the
  /// current owner), and fails without changing anything when a different live
  /// owner holds it. Of several claims that race, exactly one succeeds.
  @discardableResult
  func claim(_ identifier: String, for owner: AnyObject) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    if let current = owners[identifier]?.value, current !== owner {
      return false
    }
    owners[identifier] = WeakOwner(owner)
    return true
  }

  /// Gives `identifier` up if `owner` holds it, and does nothing otherwise.
  ///
  /// Deallocation releases an identifier on its own; this is for an owner that
  /// wants to put the identifier back before it is torn down. The plugin does
  /// not call it — a deallocated plugin leaves a nil-valued box behind — so
  /// today only the ownership harness exercises this path.
  func release(_ identifier: String, heldBy owner: AnyObject) {
    lock.lock()
    defer { lock.unlock() }
    if let current = owners[identifier]?.value, current === owner {
      owners.removeValue(forKey: identifier)
    }
  }
}
