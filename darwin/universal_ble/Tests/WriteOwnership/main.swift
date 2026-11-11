import Foundation

final class Owner { let uuid = "ABCDEF01-2345-6789-ABCD-EF0123456789" }
struct Request: OwnedWriteRequest {
  let deviceId: String
  let writeOwner: AnyObject
  let sequence: Int
}
let old = Owner()
let current = Owner()
let another = Owner()
func request(_ owner: Owner, _ sequence: Int, deviceId: String? = nil) -> Request {
  Request(deviceId: deviceId ?? owner.uuid, writeOwner: owner, sequence: sequence)
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
// represent the same native UUID. Explicit cleanup still clears all owners.
writes = [request(old, 1), request(current, 2), request(another, 3, deviceId: "other")]
assert(writes.removeWrites(deviceId: old.uuid.lowercased(), owner: old).map { $0.sequence } == [1])
assert(writes.removeWrites(deviceId: old.uuid, owner: old).isEmpty)
assert(writes.removeWrites(deviceId: current.uuid).map { $0.sequence } == [2])
assert(writes.map { $0.sequence } == [3])

// A new owner retires abandoned writes before its own writes are submitted.
writes = [request(old, 1), request(current, 2), request(another, 3, deviceId: "other")]
let retired = writes.removeWrites(deviceId: current.uuid, excludingOwner: current)
assert(retired.map { $0.sequence } == [1])
assert(writes.takeFirstWrite(owner: old) == nil)
assert(writes.map { $0.sequence } == [2, 3])
// A failure completion that appends new work runs after removal.
writes.append(request(current, 4))
assert(writes.map { $0.sequence } == [2, 3, 4])
print("Write ownership tests passed")
