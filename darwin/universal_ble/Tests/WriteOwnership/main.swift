import Foundation

final class Owner { let uuid = "ABCDEF01-2345-6789-ABCD-EF0123456789" }
struct Request: OwnedWriteRequest {
  let deviceId: String
  let writeOwner: AnyObject
  let sequence: Int
  let fail: () -> Void
}
let old = Owner()
let current = Owner()
let another = Owner()
func request(_ owner: Owner, _ sequence: Int, deviceId: String? = nil, fail: @escaping () -> Void = {}) -> Request {
  Request(deviceId: deviceId ?? owner.uuid, writeOwner: owner, sequence: sequence, fail: fail)
}

var writes = [request(current, 1), request(current, 2)]
assert(writes.takeFirstWrite(owner: old) == nil)
assert(writes.takeFirstWrite(owner: current)?.sequence == 1)
assert(writes.takeFirstWrite(owner: current)?.sequence == 2)
assert(writes.takeFirstWrite(owner: current) == nil)

// Characteristic predicates remain independent from owner identity.
writes = [request(current, 1), request(current, 2)]
assert(writes.takeFirstWrite(owner: old, matching: { $0.sequence == 2 }) == nil)
assert(writes.takeFirstWrite(owner: current, matching: { $0.sequence == 2 })?.sequence == 2)
assert(writes.map { $0.sequence } == [1])

// A ready callback can only drain its own WNR queue, in FIFO order.
writes = [request(old, 1), request(current, 2), request(old, 3), request(current, 4)]
assert(writes.takeFirstWrite(owner: old)?.sequence == 1)
assert(writes.takeFirstWrite(owner: old)?.sequence == 3)
assert(writes.takeFirstWrite(owner: old) == nil)
assert(writes.map { $0.sequence } == [2, 4])

// Old disconnect cleanup cannot remove current requests; case differences
// represent the same native UUID.
writes = [request(old, 1), request(current, 2), request(another, 3, deviceId: "other")]
assert(writes.removeWrites(deviceId: old.uuid.lowercased(), owner: old).map { $0.sequence } == [1])
assert(writes.removeWrites(deviceId: old.uuid, owner: old).isEmpty)
assert(writes.map { $0.sequence } == [2, 3])

// Explicit device-wide cleanup clears all owners: two requests for the same
// device and different owners both go, the path `disconnect()` relies on.
writes = [request(old, 1), request(current, 2), request(another, 3, deviceId: "other")]
assert(writes.removeWrites(deviceId: old.uuid).map { $0.sequence } == [1, 2])
assert(writes.map { $0.sequence } == [3])
assert(writes.removeWrites(deviceId: old.uuid).isEmpty)

// A disconnection settles writes whose owner is no longer connected, even when
// another object with the same UUID reported it.
writes = [request(old, 1), request(current, 2), request(another, 3, deviceId: "other")]
assert(writes.removeWrites(deviceId: old.uuid, matching: { $0.writeOwner === old }).map { $0.sequence } == [1])
assert(writes.map { $0.sequence } == [2, 3])

// A new owner retires abandoned writes before its own writes are submitted.
writes = [request(old, 1), request(current, 2), request(another, 3, deviceId: "other")]
let retired = writes.removeWrites(deviceId: current.uuid, excludingOwner: current)
assert(retired.map { $0.sequence } == [1])
assert(writes.takeFirstWrite(owner: old) == nil)
assert(writes.map { $0.sequence } == [2, 3])

// A failure completion that appends new work runs after removal, so the work it
// appends is not swept by the cleanup that produced its own failure.
writes = [request(current, 4)]
writes.append(request(current, 5, fail: { writes.append(request(current, 6)) }))
let removed = writes.removeWrites(deviceId: current.uuid, owner: current)
assert(writes.isEmpty)
removed.forEach { $0.fail() }
assert(writes.map { $0.sequence } == [6])
print("Write ownership tests passed")
