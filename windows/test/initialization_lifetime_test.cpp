#include <windows.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/base.h>

#include "callback_drain.h"

#include <atomic>
#include <functional>
#include <iostream>
#include <memory>
#include <mutex>
#include <thread>
#include <vector>

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

struct CompletionState {
  HANDLE release_operation = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  HANDLE callback_entered = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  HANDLE release_callback = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  HANDLE finished = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  std::mutex mutex;
  std::vector<std::function<void()>> ui_work;
  std::atomic<int> publications{0};
  std::atomic<int> ignored_completions{0};
  ~CompletionState() {
    CloseHandle(release_operation);
    CloseHandle(callback_entered);
    CloseHandle(release_callback);
    CloseHandle(finished);
  }
};

winrt::Windows::Foundation::IAsyncAction PendingEnumeration(
    std::shared_ptr<CompletionState> state) {
  co_await winrt::resume_background();
  WaitForSingleObject(state->release_operation, INFINITE);
}

// Model the plugin's initialization-only lifetime protocol with a controlled
// WinRT operation. The real plugin is also exercised by close_repro.py.
class Initializer {
public:
  Initializer(std::shared_ptr<CompletionState> state) : state_(state) {
    const auto initialization_operations = initialization_operations_;
    const auto publications = publications_;
    PendingEnumeration(state).Completed(
        [this, state, initialization_operations, publications](const auto &operation,
                                                 const auto &) {
          const auto callback = initialization_operations.TryAcquire();
          if (!callback.has_value()) {
            ++state->ignored_completions;
            SetEvent(state->callback_entered);
            return;
          }
          SetEvent(state->callback_entered);
          WaitForSingleObject(state->release_callback, INFINITE);
          operation.GetResults();
          universal_ble::QueueInitializationPublication(
              publications,
              [state](auto task) {
                std::lock_guard<std::mutex> lock(state->mutex);
                state->ui_work.push_back(std::move(task));
              },
              [this] { ++state_->publications; });
          SetEvent(state->finished);
        });
  }

  ~Initializer() {
    // Intentionally mirrors UniversalBlePlugin's teardown ordering. Keep this
    // model in sync with the production destructor; close_repro.py exercises
    // the actual plugin in a Flutter runner.
    callback_operations_.Close();
    initialization_operations_.Close();
    publications_.Close();
    universal_ble::DrainConnectionCleanup(initialization_operations_,
                                          std::chrono::milliseconds(25),
                                          [] { return true; });
    universal_ble::WaitForCallbacksWithoutMessagePump(publications_);
    WaitForCallbacksWithMessagePump(callback_operations_);
  }

private:
  std::shared_ptr<CompletionState> state_;
  AsyncOperationTracker callback_operations_;
  AsyncOperationTracker initialization_operations_;
  AsyncOperationTracker publications_;
};

bool Check(bool condition, const char *expression, int line) {
  if (condition)
    return true;
  std::cerr << "CHECK failed at line " << line << ": " << expression
            << std::endl;
  return false;
}

void RunUiWork(const std::shared_ptr<CompletionState> &state) {
  std::vector<std::function<void()>> work;
  {
    std::lock_guard<std::mutex> lock(state->mutex);
    work.swap(state->ui_work);
  }
  for (auto &callback : work) callback();
}
}  // namespace

#define CHECK(expression)                            \
  do {                                               \
    if (!Check((expression), #expression, __LINE__)) \
      return 1;                                      \
  } while (false)

int main() {
  winrt::init_apartment(winrt::apartment_type::single_threaded);

  // Closing before enumeration finishes must neither wait for it nor allow
  // its eventual completion to dereference the destroyed owner.
  auto late = std::make_shared<CompletionState>();
  auto initializer = std::make_unique<Initializer>(late);
  initializer.reset();
  SetEvent(late->release_callback);
  SetEvent(late->release_operation);
  CHECK(WaitForSingleObject(late->callback_entered, 2000) == WAIT_OBJECT_0);
  CHECK(late->ignored_completions == 1);
  CHECK(late->publications == 0);

  WNDCLASSW cls{};
  cls.lpfnWndProc = ForeignWindowProc;
  cls.hInstance = GetModuleHandleW(nullptr);
  cls.lpszClassName = L"UniversalBleInitializationLifetimeTest";
  CHECK(RegisterClassW(&cls) != 0);
  HWND foreign_window =
      CreateWindowExW(0, cls.lpszClassName, L"", 0, 0, 0, 0, 0, HWND_MESSAGE,
                      nullptr, cls.hInstance, nullptr);
  CHECK(foreign_window != nullptr);
  CHECK(PostMessageW(foreign_window, kForeignMessage, 0, 0));
  std::atomic<bool> sent = false;
  std::thread sender([&] {
    sent = SendNotifyMessageW(foreign_window, kForeignMessage, 0, 0) != FALSE;
  });
  sender.join();
  CHECK(sent);
  PostQuitMessage(37);

  // An admitted enumeration can outlive destruction without publishing or
  // dispatching posted or cross-thread sent window messages.
  auto active = std::make_shared<CompletionState>();
  initializer = std::make_unique<Initializer>(active);
  SetEvent(active->release_operation);
  CHECK(WaitForSingleObject(active->callback_entered, 2000) == WAIT_OBJECT_0);
  initializer.reset();
  SetEvent(active->release_callback);
  CHECK(WaitForSingleObject(active->finished, 2000) == WAIT_OBJECT_0);
  CHECK(foreign_messages_dispatched == 0);
  CHECK(active->ui_work.empty());
  CHECK(active->publications == 0);
  MSG message{};
  CHECK(PeekMessageW(&message, foreign_window, kForeignMessage, kForeignMessage,
                     PM_REMOVE));
  CHECK(foreign_messages_dispatched == 1);
  CHECK(PeekMessageW(&message, nullptr, WM_QUIT, WM_QUIT, PM_REMOVE));
  CHECK(message.wParam == 37);

  // Queue a real publication before closing its owner, then deliver it late.
  auto queued = std::make_shared<CompletionState>();
  initializer = std::make_unique<Initializer>(queued);
  SetEvent(queued->release_callback);
  SetEvent(queued->release_operation);
  CHECK(WaitForSingleObject(queued->finished, 2000) == WAIT_OBJECT_0);
  CHECK(queued->ui_work.size() == 1);
  initializer.reset();
  RunUiWork(queued);
  CHECK(queued->publications == 0);

  // Successful initialization is still published while the owner is alive.
  auto success = std::make_shared<CompletionState>();
  initializer = std::make_unique<Initializer>(success);
  SetEvent(success->release_callback);
  SetEvent(success->release_operation);
  CHECK(WaitForSingleObject(success->callback_entered, 2000) == WAIT_OBJECT_0);
  for (int attempt = 0; attempt < 200 && success->publications == 0;
       ++attempt) {
    RunUiWork(success);
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
  CHECK(success->publications == 1);
  initializer.reset();

  DestroyWindow(foreign_window);
  UnregisterClassW(cls.lpszClassName, cls.hInstance);
  winrt::uninit_apartment();
  return 0;
}
