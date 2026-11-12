#include "callback_drain.h"

#include <atomic>
#include <future>
#include <iostream>
#include <string_view>
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

int CheckStalledCleanup(bool pin_succeeds) {
  using namespace std::chrono_literals;
  std::optional<universal_ble::AsyncOperationTracker> cleanup(std::in_place);
  auto lease = cleanup->TryAcquire();
  CHECK(lease.has_value());
  cleanup->Close();

  // Model a disposal worker stuck in WinRT. The watchdog releases its lease
  // only to let the test report a failure instead of hanging CTest.
  std::promise<void> drain_returned;
  auto returned = drain_returned.get_future();
  bool watchdog_released_lease = false;
  std::thread worker([&, owned = std::move(*lease)]() mutable {
    watchdog_released_lease =
        returned.wait_for(5s) == std::future_status::timeout;
    owned.reset();
  });

  constexpr auto timeout = 250ms;
  // Allow for scheduling delays on busy Windows runners.
  constexpr auto latest_return = 2s;
  using Clock = std::chrono::steady_clock;
  std::optional<Clock::duration> time_to_pin;
  const auto start = Clock::now();
  universal_ble::DrainConnectionCleanup(*cleanup, timeout, [&] {
    time_to_pin = Clock::now() - start;
    return pin_succeeds;
  });
  const auto elapsed = Clock::now() - start;
  cleanup.reset();
  drain_returned.set_value();
  worker.join();
  if (pin_succeeds && watchdog_released_lease) {
    std::cerr << "Cleanup drain stayed blocked until the watchdog released "
                 "the stalled disposal lease."
              << std::endl;
    return 1;
  }
  CHECK(time_to_pin.has_value());
  CHECK(*time_to_pin >= timeout);
  CHECK(*time_to_pin < latest_return);
  CHECK(!pin_succeeds || elapsed < latest_return);
  CHECK(watchdog_released_lease == !pin_succeeds);
  return 0;
}

int main(int argc, char **argv) {
  if (argc == 2 && std::string_view(argv[1]) == "--stalled-cleanup") {
    return CheckStalledCleanup(true);
  }
  if (argc == 2 && std::string_view(argv[1]) == "--pin-failure") {
    return CheckStalledCleanup(false);
  }
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
  bool pin_attempted = false;
  const auto pin = [&] {
    pin_attempted = true;
    return false;
  };
  universal_ble::DrainConnectionCleanup(cleanup, std::chrono::seconds(3), pin);
  const bool idle_at_return = cleanup.IsIdle();
  worker.join();
  universal_ble::DrainConnectionCleanup(cleanup, std::chrono::seconds(0), pin);
  CHECK(!pin_attempted);
  CHECK(idle_at_return);
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
