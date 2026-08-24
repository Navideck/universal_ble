#pragma once

#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <memory>
#include <mutex>
#include <optional>

namespace universal_ble {

// Keeps native objects alive while asynchronous work is using them and lets
// teardown wait until callbacks which already entered the plugin have left.
class AsyncOperationTracker {
 private:
  struct State {
    std::mutex mutex;
    std::condition_variable idle;
    std::size_t active = 0;
    bool accepting = true;
  };

  struct Token {
    explicit Token(std::shared_ptr<State> state) : state(std::move(state)) {}
    ~Token() {
      std::lock_guard<std::mutex> lock(state->mutex);
      if (--state->active == 0) {
        state->idle.notify_all();
      }
    }
    std::shared_ptr<State> state;
  };

 public:
  using Lease = std::shared_ptr<Token>;

  AsyncOperationTracker() : state_(std::make_shared<State>()) {}

  std::optional<Lease> TryAcquire() const {
    std::lock_guard<std::mutex> lock(state_->mutex);
    if (!state_->accepting) {
      return std::nullopt;
    }
    // Allocate before incrementing. If allocation throws, no active operation
    // exists and the count must remain unchanged.
    auto lease = std::make_shared<Token>(state_);
    ++state_->active;
    return lease;
  }

  bool IsIdle() const {
    std::lock_guard<std::mutex> lock(state_->mutex);
    return state_->active == 0;
  }

  void Close() const {
    std::lock_guard<std::mutex> lock(state_->mutex);
    state_->accepting = false;
  }

  template <typename Rep, typename Period>
  bool
  WaitUntilIdleFor(const std::chrono::duration<Rep, Period> &timeout) const {
    std::unique_lock<std::mutex> lock(state_->mutex);
    return state_->idle.wait_for(lock, timeout,
                                 [this] { return state_->active == 0; });
  }

 private:
  std::shared_ptr<State> state_;
};

}  // namespace universal_ble
