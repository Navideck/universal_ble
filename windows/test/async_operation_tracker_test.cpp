#include "async_operation_tracker.h"

#include <atomic>
#include <cassert>
#include <chrono>
#include <thread>

using universal_ble::AsyncOperationTracker;

int main() {
  {
    AsyncOperationTracker tracker;
    auto first = tracker.TryAcquire();
    assert(first.has_value());
    auto retained_copy = first.value();
    first.reset();
    assert(!tracker.IsIdle());
    retained_copy.reset();
    assert(tracker.IsIdle());
  }

  {
    AsyncOperationTracker tracker;
    auto operation = tracker.TryAcquire();
    assert(operation.has_value());
    tracker.Close();
    assert(!tracker.TryAcquire().has_value());

    std::atomic<bool> wait_completed = false;
    std::thread waiter([&] {
      tracker.WaitUntilIdle();
      wait_completed = true;
    });
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
    assert(!wait_completed.load());
    operation.reset();
    waiter.join();
    assert(wait_completed.load());
  }

  return 0;
}
