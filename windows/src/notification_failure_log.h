#pragma once

#include <cstddef>
#include <mutex>
#include <set>
#include <string>

namespace universal_ble {

// Remembers, per characteristic, whether the last peripheral notification
// reported a problem on the transport. A client that stops reading makes every
// `updateCharacteristicValue` fail, so logging each one would emit a line per
// notification at stream rate; the notification completion handler logs
// transitions instead.
//
// Platform-agnostic on purpose so it is covered by `windows/test` on every
// host.
class NotificationFailureLog {
public:
  // Records `failing` for `characteristic_id` and returns true when that is a
  // change from the recorded state, which is the first failure and the
  // recovery after one. Successful updates only ever clear state, so the set
  // stays as small as the characteristics currently failing.
  bool Update(const std::string &characteristic_id, bool failing) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (failing) {
      return failing_.insert(characteristic_id).second;
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
