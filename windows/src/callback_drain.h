#pragma once

#include <chrono>
#include <windows.h>

#include "async_operation_tracker.h"

namespace universal_ble {

inline HWND FindComApartmentWindow() noexcept {
  const DWORD thread_id = GetCurrentThreadId();
  HWND window = nullptr;
  while ((window = FindWindowExW(HWND_MESSAGE, window,
                                 L"OleMainThreadWndClass", nullptr)) != nullptr) {
    if (GetWindowThreadProcessId(window, nullptr) == thread_id) {
      return window;
    }
  }
  return nullptr;
}

// Apartment-aware WinRT continuations return through the thread's hidden COM
// window. Dispatch only queued messages for that window while draining:
// Flutter and other plugins may already be partially destroyed during teardown.
inline void WaitForCallbacksWithMessagePump(
    const AsyncOperationTracker &operations) noexcept {
  while (!operations.WaitUntilIdleFor(std::chrono::milliseconds(10))) {
    const HWND com_window = FindComApartmentWindow();
    if (com_window == nullptr) continue;
    MSG message;
    while (PeekMessageW(&message, com_window, 0, 0, PM_REMOVE)) {
      // PeekMessage retrieves WM_QUIT even when filtering by window.
      if (message.message == WM_QUIT) {
        PostQuitMessage(static_cast<int>(message.wParam));
        break;
      }
      TranslateMessage(&message);
      DispatchMessageW(&message);
    }
  }
}

}  // namespace universal_ble
