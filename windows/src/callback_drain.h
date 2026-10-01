#pragma once

#include <chrono>
#include <objbase.h>
#include <windows.h>

#include "async_operation_tracker.h"

namespace universal_ble {

// C++/WinRT may resume apartment-aware co_await continuations on the thread
// which started them. Pump that thread's Windows messages while callbacks
// drain so shutdown cannot block the continuations it is waiting for.
inline void WaitForCallbacksWithMessagePump(
    const AsyncOperationTracker &operations) noexcept {
  while (!operations.WaitUntilIdleFor(std::chrono::milliseconds(10))) {
    // C++/WinRT apartment_context resumes STA continuations through COM, not
    // necessarily through an ordinary window message. Dispatch both COM calls
    // and window messages so a continuation can release its operation lease
    // while teardown is running on the originating apartment.
    DWORD index = 0;
    CoWaitForMultipleHandles(
        COWAIT_DISPATCH_CALLS | COWAIT_DISPATCH_WINDOW_MESSAGES, 0, 0, nullptr,
        &index);

    MSG message;
    while (PeekMessage(&message, nullptr, 0, 0, PM_REMOVE)) {
      if (message.message == WM_QUIT) {
        PostQuitMessage(static_cast<int>(message.wParam));
        break;
      }
      TranslateMessage(&message);
      DispatchMessage(&message);
    }
  }
}

}  // namespace universal_ble
