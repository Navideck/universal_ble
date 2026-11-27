import Foundation

/// Main-queue O(1) FIFO. Backpressure blocks all newer notifications until the
/// delegate resumes it.
///
/// The queue keeps a read head index instead of removing the first element on
/// every drain: `Array.removeFirst()` shifts the whole tail, so draining a bulk
/// transfer one chunk at a time was O(N²). Elements are compacted away in
/// batches, and the storage is released once the queue is drained.
struct PeripheralNotificationQueue<Element> {
  private var storage = [Element]()
  private var head = 0
  private var blocked = false

  var pending: ArraySlice<Element> { storage[head...] }
  var isEmpty: Bool { head >= storage.count }

  mutating func append(_ element: Element) { storage.append(element) }
  mutating func resume() { blocked = false }

  /// Discards every pending element and returns them, so their callers can be
  /// failed instead of waiting forever.
  @discardableResult
  mutating func removeAll() -> [Element] {
    let removed = Array(storage[head...])
    storage.removeAll(keepingCapacity: false)
    head = 0
    blocked = false
    return removed
  }

  /// Discards the pending elements matching [predicate] and returns them.
  @discardableResult
  mutating func removeAll(where predicate: (Element) -> Bool) -> [Element] {
    var removed = [Element]()
    var kept = [Element]()
    kept.reserveCapacity(storage.count - head)
    for index in head..<storage.count {
      let element = storage[index]
      if predicate(element) {
        removed.append(element)
      } else {
        kept.append(element)
      }
    }
    storage = kept
    head = 0
    if storage.isEmpty { blocked = false }
    return removed
  }

  /// Sends pending elements in FIFO order until [send] refuses one. Each
  /// accepted element is reported exactly once through [onSent]; a refused one
  /// stays queued and blocks the queue until [resume].
  mutating func drain(_ send: (Element) -> Bool, onSent: (Element) -> Void = { _ in }) {
    guard !blocked else { return }
    while head < storage.count {
      let first = storage[head]
      guard send(first) else {
        blocked = true
        compactIfNeeded()
        return
      }
      head += 1
      onSent(first)
    }
    compactIfNeeded()
  }

  private mutating func compactIfNeeded() {
    if head >= storage.count {
      storage.removeAll(keepingCapacity: false)
      head = 0
    } else if head >= 64 && head * 2 >= storage.count {
      storage.removeFirst(head)
      head = 0
    }
  }
}
