import Foundation

// UUID equality identifies a device; object identity identifies the native
// peripheral instance that submitted an outstanding write.
protocol OwnedWriteRequest {
  var deviceId: String { get }
  var writeOwner: AnyObject { get }
}

/// Whether the owner of a pending write can still complete it.
enum WriteOwnership {
  /// A write can only complete while its owner is the object the plugin routes
  /// the device's callbacks to, and while that object is connected.
  ///
  /// Identity, not `CBPeripheral.state`, decides. Once a replacement object
  /// supersedes an owner, CoreBluetooth stops delivering the predecessor's
  /// callbacks without necessarily updating its `state`, which can keep reading
  /// `.connected`; such a write has no completion left to wait for. `routedOwner`
  /// is nil when the plugin has no object for the device (after a disconnection),
  /// in which case every remaining write is abandoned.
  static func isAbandoned(
    owner: AnyObject,
    routedOwner: AnyObject?,
    isConnected: (AnyObject) -> Bool
  ) -> Bool {
    guard let routedOwner = routedOwner, owner === routedOwner else { return true }
    return !isConnected(owner)
  }
}

extension Array where Element: OwnedWriteRequest {
  mutating func takeFirstWrite(owner: AnyObject, matching predicate: (Element) -> Bool = { _ in true }) -> Element? {
    guard let index = firstIndex(where: { $0.writeOwner === owner && predicate($0) }) else { return nil }
    return remove(at: index)
  }

  /// Removes the writes for `deviceId` submitted by `owner`, whichever device
  /// casing the request recorded.
  mutating func removeWrites(deviceId: String, owner: AnyObject) -> [Element] {
    removeWrites(deviceId: deviceId) { $0.writeOwner === owner }
  }

  /// Removes the writes for `deviceId` submitted by any object but `owner`.
  mutating func removeWrites(deviceId: String, excludingOwner owner: AnyObject) -> [Element] {
    removeWrites(deviceId: deviceId) { $0.writeOwner !== owner }
  }

  /// Removes every write for `deviceId`, whichever object submitted it: the
  /// device-wide cleanup an explicit `disconnect()` performs.
  mutating func removeWrites(deviceId: String) -> [Element] {
    removeWrites(deviceId: deviceId) { _ in true }
  }

  /// Removes the writes for `deviceId` that satisfy `predicate` in addition to
  /// matching the device. Removes before its caller invokes completions, since
  /// a completion may enqueue more work.
  mutating func removeWrites(deviceId: String, matching predicate: (Element) -> Bool) -> [Element] {
    func matches(_ request: Element) -> Bool {
      request.deviceId.caseInsensitiveCompare(deviceId) == .orderedSame && predicate(request)
    }
    let removed = filter(matches)
    removeAll(where: matches)
    return removed
  }
}
