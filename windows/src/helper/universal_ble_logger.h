#pragma once

#include <iostream>
#include <string>

#include "../generated/universal_ble.g.h"

namespace universal_ble {

class UniversalBleLogger {
public:
  static void SetLogLevel(UniversalBleLogLevel level);
  static UniversalBleLogLevel current_log_level();

  static void LogError(const std::string &message);
  static void LogWarning(const std::string &message);
  static void LogInfo(const std::string &message);
  static void LogDebug(const std::string &message);
  static void LogVerbose(const std::string &message);

private:
  static UniversalBleLogLevel current_level_;
  static bool Allows(UniversalBleLogLevel level);
};

} // namespace universal_ble
