import Foundation

// UUID equality identifies a device; object identity identifies the native
// peripheral instance that submitted an outstanding write.
protocol OwnedWriteRequest {
  var deviceId: String { get }
  var writeOwner: AnyObject { get }
}

extension Array where Element: OwnedWriteRequest {
  mutating func takeFirstWrite(owner: AnyObject, matching predicate: (Element) -> Bool = { _ in true }) -> Element? {
    guard let index = firstIndex(where: { $0.writeOwner === owner && predicate($0) }) else { return nil }
    return remove(at: index)
  }

  // Remove before invoking completions: a completion may enqueue more work.
  mutating func removeWrites(deviceId: String, owner: AnyObject? = nil, excludingOwner: AnyObject? = nil) -> [Element] {
    func matches(_ request: Element) -> Bool {
      guard request.deviceId.caseInsensitiveCompare(deviceId) == .orderedSame else { return false }
      if let owner = owner, request.writeOwner !== owner { return false }
      if let excludingOwner = excludingOwner, request.writeOwner === excludingOwner { return false }
      return true
    }
    let removed = filter(matches)
    removeAll(where: matches)
    return removed
  }
}
