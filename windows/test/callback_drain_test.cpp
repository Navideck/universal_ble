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

struct ResumeOnInitializedMta {
  bool await_ready() const noexcept { return false; }

  void await_suspend(std::coroutine_handle<> continuation) const {
    std::thread([continuation] {
      winrt::init_apartment(winrt::apartment_type::multi_threaded);
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
  return 0;
}
