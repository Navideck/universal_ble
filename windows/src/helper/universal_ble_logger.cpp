#include "universal_ble_logger.h"
#include <chrono>
#include <iomanip>
#include <sstream>

namespace universal_ble {

UniversalBleLogLevel UniversalBleLogger::current_level_ =
    UniversalBleLogLevel::kNone;

static std::string GetCurrentTimestampString() {
  auto now = std::chrono::system_clock::now();
  auto time_t = std::chrono::system_clock::to_time_t(now);
  auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                now.time_since_epoch()) %
            1000;

  std::tm timeinfo;
  localtime_s(&timeinfo, &time_t);

  std::ostringstream oss;
  oss << std::put_time(&timeinfo, "%H:%M:%S");
  oss << "." << std::setfill('0') << std::setw(3) << ms.count();
  return "[" + oss.str() + "]";
}

void UniversalBleLogger::SetLogLevel(UniversalBleLogLevel level) {
  current_level_ = level;
}

UniversalBleLogLevel UniversalBleLogger::current_log_level() {
  return current_level_;
}

void UniversalBleLogger::LogError(const std::string &message) {
  if (!Allows(UniversalBleLogLevel::kError))
    return;
  std::cout << "UniversalBle:ERROR " << message << std::endl;
}

void UniversalBleLogger::LogWarning(const std::string &message) {
  if (!Allows(UniversalBleLogLevel::kWarning))
    return;
  std::cout << "UniversalBle:WARN " << message << std::endl;
}

void UniversalBleLogger::LogInfo(const std::string &message) {
  if (!Allows(UniversalBleLogLevel::kInfo))
    return;
  std::cout << "UniversalBle:INFO " << message << std::endl;
}

void UniversalBleLogger::LogDebug(const std::string &message) {
  if (!Allows(UniversalBleLogLevel::kDebug))
    return;
  std::cout << "UniversalBle:DEBUG " << message << std::endl;
}

void UniversalBleLogger::LogVerbose(const std::string &message) {
  if (!Allows(UniversalBleLogLevel::kVerbose))
    return;
  std::cout << "UniversalBle:VERBOSE " << message << std::endl;
}

void UniversalBleLogger::LogDebugWithTimestamp(const std::string &message) {
  if (!Allows(UniversalBleLogLevel::kDebug))
    return;
  std::cout << "UniversalBle:DEBUG " << GetCurrentTimestampString() << " " << message
            << std::endl;
}

void UniversalBleLogger::LogVerboseWithTimestamp(const std::string &message) {
  if (!Allows(UniversalBleLogLevel::kVerbose))
    return;
  std::cout << "UniversalBle:VERBOSE " << GetCurrentTimestampString() << " "
            << message << std::endl;
}

bool UniversalBleLogger::Allows(UniversalBleLogLevel level) {
  return current_level_ != UniversalBleLogLevel::kNone &&
         static_cast<int>(level) <= static_cast<int>(current_level_);
}

} // namespace universal_ble
