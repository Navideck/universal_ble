// Drives the Windows filter core from the shared conformance fixture
// (test/fixtures/scan_filter_cases.tsv), so its semantics stay identical to the
// Dart, Kotlin and Swift implementations. Builds and runs without a Flutter
// engine or WinRT: see windows/src/scan_filter_matcher.h.
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

#include "scan_filter_matcher.h"

namespace {

using universal_ble::AdvertisementValues;
using universal_ble::HasAnyFilter;
using universal_ble::ManufacturerDataValue;
using universal_ble::MatchesScanFilter;
using universal_ble::NormalizeUuid;
using universal_ble::ScanFilterValues;

#ifndef SCAN_FILTER_FIXTURE_PATH
#error "SCAN_FILTER_FIXTURE_PATH must point at test/fixtures/scan_filter_cases.tsv"
#endif

std::vector<std::string> Split(const std::string &value, char separator) {
  std::vector<std::string> parts;
  std::stringstream stream(value);
  std::string part;
  while (std::getline(stream, part, separator)) {
    if (!part.empty()) {
      parts.push_back(part);
    }
  }
  return parts;
}

struct Case {
  std::string id;
  std::vector<std::string> with_services;
  std::vector<std::string> with_service_data;
  std::vector<std::string> with_name_prefix;
  std::vector<std::string> with_manufacturer_ids;
  std::string device_name;
  std::vector<std::string> device_services;
  std::vector<std::string> device_service_data;
  std::vector<std::string> device_manufacturer_ids;
  bool expected = false;
};

std::vector<std::string> SplitRow(const std::string &line) {
  std::vector<std::string> columns;
  std::stringstream stream(line);
  std::string column;
  while (std::getline(stream, column, '|')) {
    columns.push_back(column);
  }
  return columns;
}

std::vector<int64_t> ToCompanyIds(const std::vector<std::string> &values,
                                  const std::string &row_id) {
  std::vector<int64_t> ids;
  ids.reserve(values.size());
  for (const auto &value : values) {
    try {
      ids.push_back(std::stoll(value));
    } catch (const std::exception &) {
      std::cerr << "Bad company identifier '" << value << "' in fixture row '"
                << row_id << "' (columns shifted?)\n";
      std::exit(2);
    }
  }
  return ids;
}

std::vector<Case> LoadCases(const std::string &path) {
  std::ifstream file(path);
  if (!file.is_open()) {
    std::cerr << "Failed to open fixture: " << path << "\n";
    std::exit(2);
  }

  std::vector<Case> cases;
  std::string line;
  while (std::getline(file, line)) {
    if (line.empty() || line[0] == '#' || line.rfind("id|", 0) == 0) {
      continue;
    }
    const auto columns = SplitRow(line);
    if (columns.size() != 10) {
      std::cerr << "Bad fixture row: " << line << "\n";
      std::exit(2);
    }

    Case test_case;
    test_case.id = columns[0];
    test_case.with_services = Split(columns[1], ';');
    test_case.with_service_data = Split(columns[2], ';');
    test_case.with_name_prefix = Split(columns[3], ';');
    test_case.with_manufacturer_ids = Split(columns[4], ';');
    test_case.device_name = columns[5];
    test_case.device_services = Split(columns[6], ';');
    test_case.device_service_data = Split(columns[7], ';');
    test_case.device_manufacturer_ids = Split(columns[8], ';');
    test_case.expected = columns[9] == "1";
    cases.push_back(test_case);
  }
  return cases;
}

ScanFilterValues BuildFilter(const Case &test_case) {
  ScanFilterValues filter;
  filter.services = test_case.with_services;
  filter.service_data = test_case.with_service_data;
  filter.name_prefix = test_case.with_name_prefix;
  for (const auto company_id : ToCompanyIds(test_case.with_manufacturer_ids, test_case.id)) {
    universal_ble::ManufacturerDataFilterValue value;
    value.company_identifier = company_id;
    filter.manufacturer_data.push_back(value);
  }
  return filter;
}

AdvertisementValues BuildAdvertisement(const Case &test_case) {
  AdvertisementValues advertisement;
  advertisement.name = test_case.device_name;
  advertisement.services = test_case.device_services;
  advertisement.service_data_uuids = test_case.device_service_data;
  for (const auto company_id : ToCompanyIds(test_case.device_manufacturer_ids, test_case.id)) {
    ManufacturerDataValue value;
    value.company_identifier = company_id;
    advertisement.manufacturer_data.push_back(value);
  }
  return advertisement;
}

int Failures = 0;

void Expect(bool condition, const std::string &what) {
  if (!condition) {
    std::cerr << "FAILED: " << what << "\n";
    Failures++;
  }
}

}  // namespace

int main() {
  const auto cases = LoadCases(SCAN_FILTER_FIXTURE_PATH);
  Expect(!cases.empty(), "fixture should contain cases");

  for (const auto &test_case : cases) {
    const auto filter = BuildFilter(test_case);
    const auto advertisement = BuildAdvertisement(test_case);

    if (!HasAnyFilter(filter)) {
      Expect(test_case.expected, test_case.id + ": empty filter should accept");
      continue;
    }
    Expect(MatchesScanFilter(filter, advertisement) == test_case.expected,
           test_case.id + ": unexpected match result");
  }

  // UUID normalisation, which every comparison above relies on.
  Expect(NormalizeUuid("181A") == "0000181a00001000800000805f9b34fb",
         "short UUID expands to the 128-bit form");
  Expect(NormalizeUuid("0000181A-0000-1000-8000-00805F9B34FB") ==
             "0000181a00001000800000805f9b34fb",
         "dashes and case are ignored");
  Expect(NormalizeUuid("181a") == NormalizeUuid("181A"),
         "normalisation is case-insensitive");

  if (Failures == 0) {
    std::cout << "All " << cases.size() << " scan filter cases passed\n";
  }
  return Failures == 0 ? 0 : 1;
}
