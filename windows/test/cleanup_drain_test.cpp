#include "callback_drain.h"

#include <atomic>
#include <iostream>
#include <thread>
#include <utility>

namespace {
constexpr UINT kForeignMessage = WM_APP + 91;
int dispatched = 0;
LRESULT CALLBACK ForeignWindowProc(HWND window, UINT message, WPARAM wparam,
                                   LPARAM lparam) {
  if (message == kForeignMessage) {
    ++dispatched;
    return 0;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}
}  // namespace

#define CHECK(expression)                                        \
  do {                                                           \
    if (!(expression)) {                                         \
      std::cerr << "CHECK failed: " << #expression << std::endl; \
      return 1;                                                  \
    }                                                            \
  } while (false)

int main() {
  CHECK(SUCCEEDED(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED)));
  WNDCLASSW cls{};
  cls.lpfnWndProc = ForeignWindowProc;
  cls.hInstance = GetModuleHandleW(nullptr);
  cls.lpszClassName = L"UniversalBleCleanupDrainTest";
  CHECK(RegisterClassW(&cls));
  HWND window = CreateWindowExW(0, cls.lpszClassName, L"", 0, 0, 0, 0, 0,
                                HWND_MESSAGE, nullptr, cls.hInstance, nullptr);
  CHECK(window);
  CHECK(PostMessageW(window, kForeignMessage, 0, 0));
  std::atomic<bool> sent = false;
  std::thread sender([&] {
    sent = SendNotifyMessageW(window, kForeignMessage, 0, 0) != FALSE;
  });
  sender.join();
  CHECK(sent);
  PostQuitMessage(37);

  universal_ble::AsyncOperationTracker cleanup;
  auto lease = cleanup.TryAcquire();
  CHECK(lease.has_value());
  std::thread worker([owned = std::move(lease.value())]() mutable {
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
    owned.reset();
  });
  lease.reset();
  cleanup.Close();
  universal_ble::WaitForCallbacksWithoutMessagePump(cleanup);
  worker.join();
  CHECK(cleanup.IsIdle());
  CHECK(!cleanup.TryAcquire().has_value());
  CHECK(dispatched == 0);

  MSG message{};
  // PeekMessage dispatches the pending sent message; the posted one remains
  // available for normal dispatch only after teardown has finished.
  CHECK(PeekMessageW(&message, window, kForeignMessage, kForeignMessage,
                     PM_REMOVE));
  CHECK(dispatched == 1);
  DispatchMessageW(&message);
  CHECK(dispatched == 2);
  CHECK(PeekMessageW(&message, nullptr, WM_QUIT, WM_QUIT, PM_REMOVE));
  CHECK(message.wParam == 37);
  DestroyWindow(window);
  UnregisterClassW(cls.lpszClassName, cls.hInstance);
  CoUninitialize();
  return 0;
}
