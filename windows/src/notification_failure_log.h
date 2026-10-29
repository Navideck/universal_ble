#pragma once

#include <cstddef>
#include <mutex>
#include <set>
#include <string>

namespace universal_ble {

// Remembers, per characteristic, whether a transport failure has been logged
// since the last successful notification. A client that stops reading makes
// every `updateCharacteristicValue` fail, so logging each one would emit a line
// per notification at stream rate; the notification completion handler logs
// transitions instead.
//
// Platform-agnostic on purpose so it is covered by `windows/test` on every
// host.
class NotificationFailureLog {
public:
  // Reports the first failure with error logging enabled and recovery after
  // one. Disabled logging never consumes the first failure; successful updates
  // always clear state, even when logging is disabled.
  bool Update(const std::string &characteristic_id, bool failing,
              bool error_logging_enabled) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (failing) {
      return error_logging_enabled && failing_.insert(characteristic_id).second;
    }
    return failing_.erase(characteristic_id) > 0;
  }

  // Number of characteristics currently recorded as failing. Only the tests
  // need this: it shows successful updates do not accumulate entries.
  std::size_t failing_count() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return failing_.size();
  }

private:
  mutable std::mutex mutex_;
  std::set<std::string> failing_;
};

}  // namespace universal_ble
