#pragma once

#include <algorithm>
#include <chrono>
#include <utility>
#include <objbase.h>
#include <windows.h>

#include "async_operation_tracker.h"

namespace universal_ble {

// Only for operations whose completion is independent of the calling apartment.
// Do not dispatch COM calls or application messages while draining these
// leases.
inline void WaitForCallbacksWithoutMessagePump(
    const AsyncOperationTracker &operations) noexcept {
  while (!operations.WaitUntilIdleFor(std::chrono::milliseconds(10))) {
  }
}

// Close admission before waiting. Workers that can outlive this drain must
// own their state and never access caller-owned resources. If the module
// cannot be kept loaded for those workers, continue waiting for them.
template <typename KeepModuleLoaded>
void DrainConnectionCleanup(
    const AsyncOperationTracker &operations,
    std::chrono::steady_clock::duration timeout,
    KeepModuleLoaded keep_module_loaded) noexcept {
  if (operations.WaitUntilIdleFor(timeout) || operations.IsIdle()) {
    return;
  }
  if (!keep_module_loaded()) {
    WaitForCallbacksWithoutMessagePump(operations);
  }
}

// Guard both access to the owner while enqueueing and access when the queued
// task runs. Close the gate and drain admitted publications before destroying
// the owner.
template <typename Enqueue, typename Publish>
void QueueInitializationPublication(const AsyncOperationTracker &gate,
                                    Enqueue &&enqueue, Publish &&publish) {
  const auto lease = gate.TryAcquire();
  if (!lease.has_value()) {
    return;
  }
  std::forward<Enqueue>(enqueue)(
      [gate, publish = std::forward<Publish>(publish)] {
        const auto delivery = gate.TryAcquire();
        if (delivery.has_value()) {
          publish();
        }
      });
}

// C++/WinRT may resume apartment-aware co_await continuations on the thread
// which started them. Pump that thread's Windows messages while callbacks
// drain so shutdown cannot block the continuations it is waiting for.
inline bool WaitForCallbacksWithMessagePumpUntil(
    const AsyncOperationTracker &operations,
    std::chrono::steady_clock::time_point deadline) noexcept {
  using Clock = std::chrono::steady_clock;
  while (!operations.IsIdle()) {
    const auto remaining = deadline - Clock::now();
    if (remaining <= Clock::duration::zero()) {
      return operations.IsIdle();
    }
    if (operations.WaitUntilIdleFor(
            (std::min)(remaining, Clock::duration(std::chrono::milliseconds(10))))) {
      return true;
    }
    // C++/WinRT apartment_context resumes STA continuations through COM, not
    // necessarily through an ordinary window message. Dispatch both COM calls
    // and window messages so a continuation can release its operation lease
    // while teardown is running on the originating apartment.
    DWORD index = 0;
    CoWaitForMultipleHandles(
        COWAIT_DISPATCH_CALLS | COWAIT_DISPATCH_WINDOW_MESSAGES, 0, 0, nullptr,
        &index);

    MSG message;
    while (std::chrono::steady_clock::now() < deadline &&
           PeekMessage(&message, nullptr, 0, 0, PM_REMOVE)) {
      if (message.message == WM_QUIT) {
        PostQuitMessage(static_cast<int>(message.wParam));
        break;
      }
      TranslateMessage(&message);
      DispatchMessage(&message);
    }
  }
  return true;
}

inline void WaitForCallbacksWithMessagePump(
    const AsyncOperationTracker &operations) noexcept {
  WaitForCallbacksWithMessagePumpUntil(
      operations, (std::chrono::steady_clock::time_point::max)());
}

}  // namespace universal_ble
