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
    CHECK(log.Update("char-a", true, true));
    CHECK(!log.Update("char-a", true, true));
    CHECK(log.failing_count() == 1);
    CHECK(log.Update("char-a", false, true));
    CHECK(!log.Update("char-a", false, true));
    CHECK(log.failing_count() == 0);
  }

  {
    // A characteristic that never fails never logs, so a healthy stream does
    // not accumulate entries.
    NotificationFailureLog log;
    for (int i = 0; i < 100; ++i) {
      CHECK(!log.Update("char-a", false, true));
    }
    CHECK(log.failing_count() == 0);
  }

  {
    // Characteristics are tracked separately: a wedged client on one does not
    // hide the first failure of another.
    NotificationFailureLog log;
    CHECK(log.Update("char-a", true, true));
    CHECK(log.Update("char-b", true, true));
    CHECK(!log.Update("char-b", true, true));
    CHECK(!log.Update("char-a", true, true));
    CHECK(log.failing_count() == 2);
    CHECK(log.Update("char-b", false, true));
    CHECK(log.failing_count() == 1);
    CHECK(log.Update("char-a", false, true));
    CHECK(log.failing_count() == 0);
  }

  {
    // Turning logging on during a persistent failure reports the next failed
    // update, then suppresses repeats as usual.
    NotificationFailureLog log;
    for (int i = 0; i < 100; ++i) {
      CHECK(!log.Update("char-a", true, false));
    }
    CHECK(log.failing_count() == 0);
    CHECK(log.Update("char-a", true, true));
    CHECK(!log.Update("char-a", true, true));
    CHECK(log.failing_count() == 1);
  }

  {
    // Recovery while logging is disabled still resets suppression, so the
    // next failure can be reported after logging is re-enabled.
    NotificationFailureLog log;
    CHECK(log.Update("char-a", true, true));
    CHECK(log.Update("char-a", false, false));
    CHECK(log.failing_count() == 0);
    CHECK(!log.Update("char-a", true, false));
    CHECK(log.Update("char-a", true, true));
    CHECK(!log.Update("char-a", true, true));
  }

  return 0;
}
