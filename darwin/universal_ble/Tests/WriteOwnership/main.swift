// UniversalBleWriteOwnership on its own — no Flutter, no CoreBluetooth, and no
// optimiser surprises: every check counts, so `-O` cannot elide it. Run
// Tests/run_write_ownership_test.sh on a Mac.
import Foundation

var failures = 0
var checks = 0
func check(_ ok: Bool, _ what: String, line: Int = #line) {
  checks += 1
  if ok { print("ok    \(what)") } else { failures += 1; print("FAIL  \(what)  (line \(line))") }
}

/// Stands in for a CBPeripheral. `connected` stands in for its `state`; two
/// owners may share a UUID, as a superseded object and its replacement do.
final class Owner: AnyObject {
  let uuid: String
  var connected: Bool

  init(uuid: String = "ABCDEF01-2345-6789-ABCD-EF0123456789", connected: Bool = true) {
    self.uuid = uuid
    self.connected = connected
  }
}

struct Request: OwnedWriteRequest {
  let deviceId: String
  let writeOwner: AnyObject
  let sequence: Int
  let fail: () -> Void
}

func request(_ owner: Owner, _ sequence: Int, deviceId: String? = nil, fail: @escaping () -> Void = {}) -> Request {
  Request(deviceId: deviceId ?? owner.uuid, writeOwner: owner, sequence: sequence, fail: fail)
}

// The production predicate needs no CoreBluetooth: only the owner and its
// connection state stand in.
func isConnected(_ owner: AnyObject) -> Bool { (owner as? Owner)?.connected ?? false }

func abandoned(_ request: Request, routedOwner: Owner?) -> Bool {
  WriteOwnership.isAbandoned(owner: request.writeOwner, routedOwner: routedOwner, isConnected: isConnected)
}

/// The production sweep, minus the future arrays: the plugin calls
/// `removeWrites(deviceId:)` with exactly this predicate.
func removeAbandoned(_ writes: inout [Request], deviceId: String, routedOwner: Owner?) -> [Request] {
  writes.removeWrites(deviceId: deviceId) { abandoned($0, routedOwner: routedOwner) }
}

let old = Owner()
let current = Owner()
let another = Owner(uuid: "11111111-2222-3333-4444-555555555555")

// 1. Identity against the routed object, plus its connection state, decides.
check(!abandoned(request(current, 1), routedOwner: current),
      "owner: the routed owner completes its write while connected")
current.connected = false
check(abandoned(request(current, 1), routedOwner: current),
      "owner: the routed owner stops completing writes once disconnected")
current.connected = true
// The M1 case: CoreBluetooth stopped delivering this object's callbacks, but its
// state still reads `.connected` because nothing updated it.
check(abandoned(request(old, 1), routedOwner: current),
      "owner: a superseded owner is abandoned even though its state still reads connected")
check(!abandoned(request(current, 1), routedOwner: current),
      "owner: the replacement is still usable")
check(abandoned(request(current, 1), routedOwner: nil),
      "owner: with no object routed to the device every remaining write is abandoned")

// 2. Removal is per owner in FIFO order; a ready callback drains only its own queue.
var writes = [request(current, 1), request(current, 2)]
check(writes.takeFirstWrite(owner: old) == nil, "take: another owner takes nothing")
check(writes.takeFirstWrite(owner: current)?.sequence == 1, "take: FIFO first")
check(writes.takeFirstWrite(owner: current)?.sequence == 2, "take: FIFO second")
check(writes.takeFirstWrite(owner: current) == nil, "take: an empty queue takes nothing")

// 3. Characteristic predicates remain independent from owner identity.
writes = [request(current, 1), request(current, 2)]
check(writes.takeFirstWrite(owner: old, matching: { $0.sequence == 2 }) == nil,
      "take matching: another owner takes nothing")
check(writes.takeFirstWrite(owner: current, matching: { $0.sequence == 2 })?.sequence == 2,
      "take matching: the named write, even though the first is older")
check(writes.map { $0.sequence } == [1], "take matching: only the named write left")

// 4. A ready callback can only drain its own WNR queue, in FIFO order.
writes = [request(old, 1), request(current, 2), request(old, 3), request(current, 4)]
check(writes.takeFirstWrite(owner: old)?.sequence == 1, "take mixed: first of its owner")
check(writes.takeFirstWrite(owner: old)?.sequence == 3, "take mixed: second of its owner")
check(writes.takeFirstWrite(owner: old) == nil, "take mixed: none of the other owner's")
check(writes.map { $0.sequence } == [2, 4], "take mixed: the other owner's writes are intact")

// 5. Owner-scoped removal cannot take current requests; case differences
//    represent the same native UUID.
writes = [request(old, 1), request(current, 2), request(another, 3, deviceId: "other")]
check(writes.removeWrites(deviceId: old.uuid.lowercased(), owner: old).map { $0.sequence } == [1],
      "remove owner: case-insensitive device match")
check(writes.removeWrites(deviceId: old.uuid, owner: old).isEmpty,
      "remove owner: nothing left to remove")
check(writes.map { $0.sequence } == [2, 3], "remove owner: other owners and devices intact")

// 6. Explicit device-wide cleanup clears all owners: two requests for the same
//    device and different owners both go, the path `disconnect()` relies on.
writes = [request(old, 1), request(current, 2), request(another, 3, deviceId: "other")]
check(writes.removeWrites(deviceId: old.uuid).map { $0.sequence } == [1, 2],
      "remove device-wide: every owner of that device")
check(writes.map { $0.sequence } == [3], "remove device-wide: other devices intact")
check(writes.removeWrites(deviceId: old.uuid).isEmpty, "remove device-wide: idempotent")

// 7. A disconnection settles abandoned writes even when another object with the
//    same UUID reported it, and leaves the routed owner's writes alone.
writes = [request(old, 1), request(current, 2), request(another, 3, deviceId: "other")]
let swept = removeAbandoned(&writes, deviceId: old.uuid, routedOwner: current)
check(swept.map { $0.sequence } == [1], "sweep: the predecessor's write")
check(writes.map { $0.sequence } == [2, 3], "sweep: the live owner's write and other devices intact")
check(removeAbandoned(&writes, deviceId: old.uuid, routedOwner: nil).map { $0.sequence } == [2],
      "sweep: after the disconnection the remaining write is abandoned too")
check(writes.map { $0.sequence } == [3], "sweep: other devices still intact")

// 8. A new owner retires abandoned writes before its own writes are submitted.
writes = [request(old, 1), request(current, 2), request(another, 3, deviceId: "other")]
let retired = writes.removeWrites(deviceId: current.uuid, excludingOwner: current)
check(retired.map { $0.sequence } == [1], "retire: the predecessor's write")
check(writes.takeFirstWrite(owner: old) == nil, "retire: nothing left for the predecessor")
check(writes.map { $0.sequence } == [2, 3], "retire: the replacement's write and other devices intact")

// 9. A failure completion that appends new work runs after removal, so the work
//    it appends is not swept by the cleanup that produced its own failure.
writes = [request(current, 4)]
writes.append(request(current, 5, fail: { writes.append(request(current, 6)) }))
let removed = writes.removeWrites(deviceId: current.uuid, owner: current)
check(writes.isEmpty, "completion: everything removed before any completion runs")
removed.forEach { $0.fail() }
check(writes.map { $0.sequence } == [6], "completion: work appended by a failure survives")

print("\(checks - failures)/\(checks) passed")
exit(failures == 0 ? 0 : 1)
