#include "universal_ble_logger.h"

namespace universal_ble {

UniversalBleLogLevel UniversalBleLogger::current_level_ =
    UniversalBleLogLevel::kNone;

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

bool UniversalBleLogger::Allows(UniversalBleLogLevel level) {
  return current_level_ != UniversalBleLogLevel::kNone &&
         static_cast<int>(level) <= static_cast<int>(current_level_);
}

} // namespace universal_ble
