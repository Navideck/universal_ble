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
/// Owners are held weakly and never retained: an identifier becomes available
/// again as soon as its owner is deallocated, however and whenever that
/// happens, so a torn-down engine cannot keep restoration from a later one.
final class UniversalBleCentralRestorationOwner {
  private final class WeakOwner {
    weak var value: AnyObject?

    init(_ value: AnyObject) {
      self.value = value
    }
  }

  private var owners: [String: WeakOwner] = [:]

  /// The live owner of `identifier`, or nil when the identifier is available.
  func owner(of identifier: String) -> AnyObject? {
    return owners[identifier]?.value
  }

  /// Takes `identifier` for `owner`, and returns whether `owner` holds it
  /// afterwards.
  ///
  /// The first live owner wins: a claim succeeds when the identifier is
  /// available or when `owner` already holds it (a claim is idempotent for the
  /// current owner), and fails without changing anything when a different live
  /// owner holds it.
  @discardableResult
  func claim(_ identifier: String, for owner: AnyObject) -> Bool {
    if let current = owners[identifier]?.value, current !== owner {
      return false
    }
    owners[identifier] = WeakOwner(owner)
    return true
  }

  /// Gives `identifier` up if `owner` holds it, and does nothing otherwise.
  ///
  /// Deallocation releases an identifier on its own; this is for an owner that
  /// wants to put the identifier back before it is torn down.
  func release(_ identifier: String, heldBy owner: AnyObject) {
    if let current = owners[identifier]?.value, current === owner {
      owners.removeValue(forKey: identifier)
    }
  }
}
