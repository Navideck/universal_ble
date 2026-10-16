// Drives the ATT error mapping used when a peripheral refuses a read, write or
// subscription from the shared conformance fixture
// (test/fixtures/att_error_cases.tsv), so the Windows table stays identical to
// the Android and Dart ones. Builds and runs without a Flutter engine or WinRT:
// see windows/src/att_error_mapper.h.
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

#include "att_error_mapper.h"

namespace {

using universal_ble::AttErrorToUniversalBleErrorCodeValue;

#ifndef ATT_ERROR_FIXTURE_PATH
#error "ATT_ERROR_FIXTURE_PATH must point at test/fixtures/att_error_cases.tsv"
#endif

struct Case {
  uint8_t att_code = 0;
  int expected = 0;
  std::string expected_name;
};

std::vector<Case> LoadCases(const std::string &path) {
  std::ifstream file(path);
  if (!file.is_open()) {
    std::cerr << "Failed to open fixture: " << path << "\n";
    std::exit(2);
  }

  std::vector<Case> cases;
  std::string line;
  while (std::getline(file, line)) {
    if (line.empty() || line[0] == '#' || line.rfind("att_code|", 0) == 0) {
      continue;
    }
    std::stringstream row(line);
    std::string att_code;
    std::string expected;
    std::string expected_name;
    if (!std::getline(row, att_code, '|') ||
        !std::getline(row, expected, '|') ||
        !std::getline(row, expected_name, '|')) {
      std::cerr << "Bad fixture row: " << line << "\n";
      std::exit(2);
    }
    cases.push_back(Case{
        static_cast<uint8_t>(std::stoul(att_code, nullptr, 16)),
        std::stoi(expected),
        expected_name,
    });
  }
  return cases;
}

}  // namespace

int main() {
  const auto cases = LoadCases(ATT_ERROR_FIXTURE_PATH);
  if (cases.empty()) {
    std::cerr << "Fixture contained no cases\n";
    return 1;
  }

  for (const auto &test_case : cases) {
    const int actual = AttErrorToUniversalBleErrorCodeValue(test_case.att_code);
    if (actual != test_case.expected) {
      std::cerr << "ATT code 0x" << std::hex
                << static_cast<int>(test_case.att_code) << std::dec << " ("
                << test_case.expected_name << "): expected "
                << test_case.expected << ", got " << actual << std::endl;
      return 1;
    }
  }
  return 0;
}
