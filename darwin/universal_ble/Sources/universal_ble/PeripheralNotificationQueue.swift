import Foundation

/// Main-queue FIFO. Backpressure blocks all newer reports until the delegate resumes it.
struct PeripheralNotificationQueue<Element> {
  private(set) var pending = [Element]()
  private var blocked = false

  mutating func append(_ element: Element) { pending.append(element) }
  mutating func resume() { blocked = false }
  mutating func removeAll() {
    pending.removeAll()
    blocked = false
  }
  mutating func removeAll(where predicate: (Element) -> Bool) {
    pending.removeAll(where: predicate)
    if pending.isEmpty { blocked = false }
  }
  mutating func drain(_ send: (Element) -> Bool) {
    guard !blocked else { return }
    while let first = pending.first {
      guard send(first) else {
        blocked = true
        return
      }
      pending.removeFirst()
    }
  }
}
