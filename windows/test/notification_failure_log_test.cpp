#include "notification_failure_log.h"

#include <iostream>

using universal_ble::NotificationFailureLog;

namespace {
bool Check(bool condition, const char *expression, int line) {
  if (condition) {
    return true;
  }
  std::cerr << "CHECK failed at line " << line << ": " << expression
            << std::endl;
  return false;
}
}  // namespace

#define CHECK(expression)                              \
  do {                                                 \
    if (!Check((expression), #expression, __LINE__)) { \
      return 1;                                        \
    }                                                  \
  } while (false)

int main() {
  {
    // One entry per failure run: the first failure is logged, repeats are not,
    // the recovery is logged and the following successes are not.
    NotificationFailureLog log;
    CHECK(log.Update("char-a", true));
    CHECK(!log.Update("char-a", true));
    CHECK(log.failing_count() == 1);
    CHECK(log.Update("char-a", false));
    CHECK(!log.Update("char-a", false));
    CHECK(log.failing_count() == 0);
  }

  {
    // A characteristic that never fails never logs, so a healthy stream does
    // not accumulate entries.
    NotificationFailureLog log;
    for (int i = 0; i < 100; ++i) {
      CHECK(!log.Update("char-a", false));
    }
    CHECK(log.failing_count() == 0);
  }

  {
    // Characteristics are tracked separately: a wedged client on one does not
    // hide the first failure of another.
    NotificationFailureLog log;
    CHECK(log.Update("char-a", true));
    CHECK(log.Update("char-b", true));
    CHECK(!log.Update("char-b", true));
    CHECK(!log.Update("char-a", true));
    CHECK(log.failing_count() == 2);
    CHECK(log.Update("char-b", false));
    CHECK(log.failing_count() == 1);
    CHECK(log.Update("char-a", false));
    CHECK(log.failing_count() == 0);
  }

  return 0;
}
