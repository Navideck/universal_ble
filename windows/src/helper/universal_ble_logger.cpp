#include "universal_ble_logger.h"

namespace universal_ble {

UniversalBleLogLevel UniversalBleLogger::current_level_ =
    UniversalBleLogLevel::none;

void UniversalBleLogger::SetLogLevel(UniversalBleLogLevel level) {
  current_level_ = level;
}

UniversalBleLogLevel UniversalBleLogger::current_log_level() {
  return current_level_;
}

void UniversalBleLogger::LogError(const std::string &message) {
  if (!Allows(UniversalBleLogLevel::error))
    return;
  std::cout << "UniversalBle:ERROR " << message << std::endl;
}

void UniversalBleLogger::LogWarning(const std::string &message) {
  if (!Allows(UniversalBleLogLevel::warning))
    return;
  std::cout << "UniversalBle:WARN " << message << std::endl;
}

void UniversalBleLogger::LogInfo(const std::string &message) {
  if (!Allows(UniversalBleLogLevel::info))
    return;
  std::cout << "UniversalBle:INFO " << message << std::endl;
}

void UniversalBleLogger::LogDebug(const std::string &message) {
  if (!Allows(UniversalBleLogLevel::debug))
    return;
  std::cout << "UniversalBle:DEBUG " << message << std::endl;
}

void UniversalBleLogger::LogVerbose(const std::string &message) {
  if (!Allows(UniversalBleLogLevel::verbose))
    return;
  std::cout << "UniversalBle:VERBOSE " << message << std::endl;
}

bool UniversalBleLogger::Allows(UniversalBleLogLevel level) {
  return current_level_ != UniversalBleLogLevel::none &&
         static_cast<int>(level) <= static_cast<int>(current_level_);
}

} // namespace universal_ble
