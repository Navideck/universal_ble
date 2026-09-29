#include "callback_drain.h"

#include <atomic>
#include <coroutine>
#include <iostream>
#include <thread>
#include <utility>

#include <winrt/base.h>

using universal_ble::AsyncOperationTracker;
using universal_ble::WaitForCallbacksWithMessagePump;

namespace {

constexpr UINT kForeignMessage = WM_APP + 1;
int foreign_messages_dispatched = 0;

LRESULT CALLBACK ForeignWindowProc(HWND window, UINT message, WPARAM wparam,
                                   LPARAM lparam) {
  if (message == kForeignMessage) {
    ++foreign_messages_dispatched;
    return 0;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

struct ResumeOnInitializedMta {
  bool await_ready() const noexcept { return false; }

  void await_suspend(std::coroutine_handle<> continuation) const {
    std::thread([continuation] {
      winrt::init_apartment(winrt::apartment_type::multi_threaded);
      std::this_thread::sleep_for(std::chrono::milliseconds(50));
      continuation.resume();
      winrt::uninit_apartment();
    }).detach();
  }

  void await_resume() const noexcept {}
};

winrt::fire_and_forget ReleaseLeaseOnOriginalApartment(
    AsyncOperationTracker::Lease lease, std::atomic<bool> &resumed,
    std::atomic<int32_t> &error) {
  try {
    winrt::apartment_context original_apartment;
    co_await ResumeOnInitializedMta{};
    co_await original_apartment;
    resumed = true;
  } catch (const winrt::hresult_error &exception) {
    error = exception.code().value;
  } catch (...) {
    error = -1;
  }
  lease.reset();
}

bool Check(bool condition, const char *expression, int line) {
  if (condition) {
    return true;
  }
  std::cerr << "CHECK failed at line " << line << ": " << expression
            << std::endl;
  return false;
}

}  // namespace

#define CHECK(expression)                                      \
  do {                                                         \
    if (!Check((expression), #expression, __LINE__)) return 1; \
  } while (false)

int main() {
  winrt::init_apartment(winrt::apartment_type::single_threaded);

  WNDCLASSW window_class{};
  window_class.lpfnWndProc = ForeignWindowProc;
  window_class.hInstance = GetModuleHandleW(nullptr);
  window_class.lpszClassName = L"UniversalBleForeignWindowTest";
  CHECK(RegisterClassW(&window_class) != 0);
  const auto foreign_window = CreateWindowExW(
      0, window_class.lpszClassName, L"", 0, 0, 0, 0, 0, HWND_MESSAGE,
      nullptr, window_class.hInstance, nullptr);
  CHECK(foreign_window != nullptr);
  CHECK(PostMessageW(foreign_window, kForeignMessage, 0, 0));
  CHECK(PostThreadMessageW(GetCurrentThreadId(), WM_APP + 2, 0, 0));
  PostQuitMessage(37);

  AsyncOperationTracker tracker;
  auto lease = tracker.TryAcquire();
  CHECK(lease.has_value());

  std::atomic<bool> resumed = false;
  std::atomic<int32_t> error = 0;
  ReleaseLeaseOnOriginalApartment(std::move(lease.value()), resumed, error);
  lease.reset();
  tracker.Close();

  WaitForCallbacksWithMessagePump(tracker);

  if (error.load() != 0) {
    std::cerr << "Apartment continuation failed with HRESULT 0x" << std::hex
              << static_cast<uint32_t>(error.load()) << std::endl;
    return 1;
  }
  CHECK(resumed.load());
  CHECK(tracker.IsIdle());
  CHECK(!tracker.TryAcquire().has_value());
  CHECK(foreign_messages_dispatched == 0);
  MSG message{};
  CHECK(PeekMessageW(&message, foreign_window, kForeignMessage,
                    kForeignMessage, PM_REMOVE));
  CHECK(PeekMessageW(&message, reinterpret_cast<HWND>(-1), WM_APP + 2,
                    WM_APP + 2, PM_REMOVE));
  CHECK(PeekMessageW(&message, nullptr, WM_QUIT, WM_QUIT, PM_REMOVE));
  CHECK(message.wParam == 37);
  DestroyWindow(foreign_window);
  UnregisterClassW(window_class.lpszClassName, window_class.hInstance);
  winrt::uninit_apartment();

  // MTA completions do not require a hidden STA window or message dispatch.
  winrt::init_apartment(winrt::apartment_type::multi_threaded);
  AsyncOperationTracker background_tracker;
  auto background_lease = background_tracker.TryAcquire();
  CHECK(background_lease.has_value());
  std::thread worker([lease = std::move(background_lease.value())]() mutable {
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
    lease.reset();
  });
  background_lease.reset();
  background_tracker.Close();
  WaitForCallbacksWithMessagePump(background_tracker);
  worker.join();
  CHECK(background_tracker.IsIdle());
  WaitForCallbacksWithMessagePump(background_tracker);
  winrt::uninit_apartment();
  return 0;
}
