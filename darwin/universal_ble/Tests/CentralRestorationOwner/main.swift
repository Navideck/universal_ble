// UniversalBleCentralRestorationOwner on its own —
// no Flutter, no CoreBluetooth. Run Tests/run_central_restoration_owner_test.sh
// on a Mac. An `Engine` here stands in for one FlutterEngine's BleCentralDarwin.
import Foundation

var failures = 0
var checks = 0
func check(_ ok: Bool, _ what: String, line: Int = #line) {
  checks += 1
  if ok { print("ok    \(what)") } else { failures += 1; print("FAIL  \(what)  (line \(line))") }
}

/// One engine of the process: the identity the identifier is claimed for.
final class Engine {}

let identifier = "com.universalble.central.restoration"

// 1. The first live engine claims; a second engine does not, and a second claim
//    by the owner changes nothing.
do {
  let owners = UniversalBleCentralRestorationOwner()
  let first = Engine(), second = Engine()
  check(owners.claim(identifier, for: first), "two engines: the first claims")
  check(owners.owner(of: identifier) === first, "two engines: the first is the owner")
  check(!owners.claim(identifier, for: second), "two engines: the second does not claim")
  check(owners.owner(of: identifier) === first, "two engines: the first still owns it")
  check(owners.claim(identifier, for: first), "two engines: the owner's own claim is idempotent")
  check(!owners.claim(identifier, for: second), "two engines: the second still does not claim")
  check(owners.owner(of: identifier) === first, "two engines: no owner was replaced")
}

// 2. The identifier is available again when the owner is deallocated, and a
//    later engine claims it. Three engines come and go, one at a time.
do {
  let owners = UniversalBleCentralRestorationOwner()
  weak var weakEngine: Engine?

  /// Builds an engine, lets it claim, then returns so ARC deallocates it.
  func engineClaimsAndDies(_ n: Int) {
    let engine = Engine()
    weakEngine = engine
    check(owners.claim(identifier, for: engine), "dealloc: engine \(n) claims while it lives")
    check(owners.owner(of: identifier) === engine, "dealloc: engine \(n) is the owner while it lives")
  }

  engineClaimsAndDies(1)
  check(weakEngine == nil, "dealloc: engine 1 was deallocated (test premise)")
  check(owners.owner(of: identifier) == nil, "dealloc: engine 1 took the identifier with it")

  engineClaimsAndDies(2)
  check(weakEngine == nil, "dealloc: engine 2 was deallocated (test premise)")
  check(owners.owner(of: identifier) == nil, "dealloc: engine 2 took the identifier with it")

  let third = Engine()
  check(owners.claim(identifier, for: third), "dealloc: a third engine claims what the first two released")
  check(!owners.claim(identifier, for: Engine()), "dealloc: a fourth engine is refused while the third lives")
  check(owners.owner(of: identifier) === third, "dealloc: the third still owns it")
}

// 3. Explicit release: only the owner can give an identifier up, and once it is
//    free another engine claims it.
do {
  let owners = UniversalBleCentralRestorationOwner()
  let first = Engine(), second = Engine()
  owners.claim(identifier, for: first)
  owners.release(identifier, heldBy: second)
  check(owners.owner(of: identifier) === first, "release: an engine that does not own it cannot release it")
  owners.release(identifier, heldBy: first)
  check(owners.owner(of: identifier) == nil, "release: the owner can release it")
  check(owners.claim(identifier, for: second), "release: the freed identifier is claimable by the next engine")
}

// 4. Identifiers are independent: a second identifier has its own owner, as the
//    peripheral plugin's identifiers do in the same process.
do {
  let owners = UniversalBleCentralRestorationOwner()
  let central = Engine(), peripheral = Engine()
  check(owners.claim(identifier, for: central), "identifiers: the central identifier goes to one engine")
  check(owners.claim("com.universalble.peripheral.restoration", for: peripheral),
        "identifiers: a different identifier still goes to another engine")
  check(owners.owner(of: "com.universalble.peripheral.restoration") === peripheral,
        "identifiers: each identifier keeps its own owner")
}

// 5. Edge: an identifier nobody claimed has no owner, and the map starts empty.
do {
  let owners = UniversalBleCentralRestorationOwner()
  check(owners.owner(of: identifier) == nil, "edge: an unclaimed identifier has no owner")
  owners.release(identifier, heldBy: Engine())
  check(owners.owner(of: identifier) == nil, "edge: releasing an unclaimed identifier does nothing")
}

// 6. Claims that race across threads: exactly one engine wins, every time.
//    Without the owner's lock two claims can both see the identifier as free and
//    both report success, which is the two-managers bug. With it, the outcome is
//    deterministic — the loser sees a live owner — so this is an invariant test,
//    not a timing test. The engines stay in `engines` so the winner remains live
//    while the result is checked, and each round starts from a fresh owner map so
//    a round cannot inherit a winner from the previous one.
//
//    Release is deliberately not raced here: releasing an identifier while
//    other engines claim it has a different legal outcome per interleaving (a
//    claim that lands after the release wins), so asserting on it would be flaky
//    rather than meaningful. `claim` alone is the invariant worth pinning down.
do {
  let rounds = 500
  let enginesPerRound = 8
  var roundsWithOneWinner = 0
  var roundsWithCorrectOwner = 0

  for _ in 0..<rounds {
    let owners = UniversalBleCentralRestorationOwner()
    let engines = (0..<enginesPerRound).map { _ in Engine() }
    let resultsLock = NSLock()
    var winners: [Int] = []
    let group = DispatchGroup()
    let queue = DispatchQueue(label: "central-restoration-claim", attributes: .concurrent)

    for (index, engine) in engines.enumerated() {
      queue.async(group: group) {
        let won = owners.claim(identifier, for: engine)
        if won {
          resultsLock.lock()
          winners.append(index)
          resultsLock.unlock()
        }
      }
    }
    group.wait()

    if winners.count == 1 { roundsWithOneWinner += 1 }
    if let winner = winners.first, owners.owner(of: identifier) === engines[winner] {
      roundsWithCorrectOwner += 1
    }
  }

  check(roundsWithOneWinner == rounds, "concurrency: one of \(enginesPerRound) racing claims wins in each of \(rounds) rounds")
  check(roundsWithCorrectOwner == rounds, "concurrency: the engine that won the race is the owner in each of \(rounds) rounds")
}

print("\(checks - failures)/\(checks) passed")
exit(failures == 0 ? 0 : 1)
