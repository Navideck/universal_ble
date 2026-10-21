// UniversalBleDiscoveryProgress on its own —
// no Flutter, no CoreBluetooth. Run Tests/run_discovery_progress_test.sh on a
// Mac. The keys are ObjectIdentifiers of plain objects, as the plugin's are
// of CBService and CBCharacteristic objects.
import Foundation

var failures = 0
var checks = 0
func check(_ ok: Bool, _ what: String, line: Int = #line) {
  checks += 1
  if ok { print("ok    \(what)") } else { failures += 1; print("FAIL  \(what)  (line \(line))") }
}

/// Stands in for a CBService or a CBCharacteristic: an object with a UUID.
final class Attr { let uuid: String; init(_ uuid: String) { self.uuid = uuid } }
func ids(_ xs: [Attr]) -> [ObjectIdentifier] { xs.map { ObjectIdentifier($0) } }
typealias Progress = UniversalBleDiscoveryProgress<ObjectIdentifier, ObjectIdentifier>

/// The bookkeeping upstream 2.3.0 did, reduced to its keys: one entry per
/// service, found again by UUID string (`firstIndex(where: uuid ==)`).
struct UpstreamProgress {
  var entries: [(uuid: String, done: Bool)]
  init(_ services: [Attr]) { entries = services.map { ($0.uuid, false) } }
  mutating func characteristicsDiscovered(for service: Attr) {
    if let i = entries.firstIndex(where: { $0.uuid == service.uuid }) { entries[i].done = true }
  }
  var isComplete: Bool { entries.allSatisfy { $0.done } }
}

// 1. A database with two services of one UUID, as an iPhone saw it from an
//    Android GATT server that had restarted: Google's FCF1, Google's FEF3
//    twice, then the app's own service.
do {
  let services = [Attr("FCF1"), Attr("FEF3"), Attr("FEF3"), Attr("E413E409-D641-4E9E-8162-FD24B16CEB23")]
  var upstream = UpstreamProgress(services)
  var progress = Progress(services: ids(services), withDescriptors: false)
  for (n, s) in services.enumerated() {
    upstream.characteristicsDiscovered(for: s)
    check(progress.characteristicsDiscovered(for: ObjectIdentifier(s), ids([Attr("c\(n)a"), Attr("c\(n)b")])),
          "two FEF3s: service \(n) (\(s.uuid)) recorded")
    check(progress.isComplete == (n == services.count - 1),
          "two FEF3s: complete only once all four are in (after \(n + 1))")
  }
  check(!upstream.isComplete, "two FEF3s: the UUID-keyed bookkeeping never completes (the bug)")
  check(progress.isComplete, "two FEF3s: the identity-keyed bookkeeping completes")
  check(progress.services.count == 4, "two FEF3s: four services, both FEF3s kept")
}

// 2. The callbacks in any order, the second copy first.
do {
  let a = Attr("FEF3"), b = Attr("FEF3"), c = Attr("FCF1")
  var progress = Progress(services: ids([a, b, c]), withDescriptors: false)
  progress.characteristicsDiscovered(for: ObjectIdentifier(b), [])
  check(!progress.isComplete && progress.isComplete(ObjectIdentifier(b)) && !progress.isComplete(ObjectIdentifier(a)),
        "order: the second copy done, the first still open")
  progress.characteristicsDiscovered(for: ObjectIdentifier(c), ids([Attr("x")]))
  check(!progress.isComplete, "order: two of three")
  progress.characteristicsDiscovered(for: ObjectIdentifier(a), ids([Attr("y")]))
  check(progress.isComplete, "order: the first copy last completes it")
}

// 3. A service the discovery was not started with is ignored.
do {
  let a = Attr("FEF3"), stranger = Attr("FEF3")
  var progress = Progress(services: ids([a]), withDescriptors: false)
  check(!progress.characteristicsDiscovered(for: ObjectIdentifier(stranger), []),
        "stranger: a service with the same UUID but not in the list is refused")
  check(!progress.isComplete, "stranger: and does not complete the discovery")
  progress.characteristicsDiscovered(for: ObjectIdentifier(a), [])
  check(progress.isComplete, "stranger: the real one does")
}

// 4. With descriptors: two characteristics of one UUID in one service, and
//    two services of one UUID — every characteristic counted by itself.
do {
  let s1 = Attr("FEF3"), s2 = Attr("FEF3")
  let c1 = Attr("2A05"), c2 = Attr("2A05"), c3 = Attr("2A05")
  var progress = Progress(services: ids([s1, s2]), withDescriptors: true)
  progress.characteristicsDiscovered(for: ObjectIdentifier(s1), ids([c1, c2]))
  progress.characteristicsDiscovered(for: ObjectIdentifier(s2), ids([c3]))
  check(!progress.isComplete, "descriptors: none known yet")
  progress.descriptorsDiscovered(for: ObjectIdentifier(c1))
  check(!progress.isComplete(ObjectIdentifier(s1)), "descriptors: one of the twin characteristics is not enough")
  progress.descriptorsDiscovered(for: ObjectIdentifier(c2))
  check(progress.isComplete(ObjectIdentifier(s1)) && !progress.isComplete, "descriptors: the first service done, the second open")
  progress.descriptorsDiscovered(for: ObjectIdentifier(c3))
  check(progress.isComplete, "descriptors: all three complete it")
}

// 5. Edges: no services; a service without characteristics; a key given twice.
do {
  check(Progress(services: [], withDescriptors: true).isComplete, "edge: no services is complete at once")
  let a = Attr("180F")
  var progress = Progress(services: ids([a]), withDescriptors: true)
  progress.characteristicsDiscovered(for: ObjectIdentifier(a), [])
  check(progress.isComplete, "edge: a service with no characteristics is complete")
  let twice = Progress(services: ids([a, a]), withDescriptors: false)
  check(twice.services.count == 1, "edge: a key given twice is kept once")
}

print("\(checks - failures)/\(checks) passed")
exit(failures == 0 ? 0 : 1)
