#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace universal_ble {

/// A manufacturer-data filter in plain types.
///
/// Deliberately free of flutter/winrt types: the matching rules live here so they
/// can be unit tested without a Flutter engine (see
/// windows/test/scan_filter_matcher_test.cpp, which is driven by the shared
/// fixture in test/fixtures/scan_filter_cases.tsv).
struct ManufacturerDataFilterValue {
  int64_t company_identifier = 0;
  std::optional<std::vector<uint8_t>> payload_prefix;
  std::optional<std::vector<uint8_t>> payload_mask;
};

/// One manufacturer-data field of an advertisement.
struct ManufacturerDataValue {
  int64_t company_identifier = 0;
  std::vector<uint8_t> data;
};

/// The caller's ScanFilter, reduced to what matching needs.
struct ScanFilterValues {
  std::vector<std::string> services;
  std::vector<std::string> service_data;
  std::vector<std::string> name_prefix;
  std::vector<ManufacturerDataFilterValue> manufacturer_data;
};

/// One advertisement, reduced to what matching needs.
struct AdvertisementValues {
  std::string name;
  std::vector<std::string> services;
  std::vector<std::string> service_data_uuids;
  std::vector<ManufacturerDataValue> manufacturer_data;
};

/// Normalises a UUID for comparison: lowercase, dashes removed, and short
/// (16-/32-bit) forms expanded to their 128-bit equivalent.
std::string NormalizeUuid(const std::string &uuid);

/// True when the filter constrains at least one dimension.
///
/// A filter that constrains nothing accepts every advertisement.
bool HasAnyFilter(const ScanFilterValues &filter);

/// True when the advertisement matches at least one filter dimension.
///
/// The dimensions are in OR relation, and each one is a strict predicate: an
/// unfiltered dimension (empty list) matches nothing and therefore contributes
/// nothing. Callers must check [HasAnyFilter] first.
bool MatchesScanFilter(const ScanFilterValues &filter,
                       const AdvertisementValues &advertisement);
}  // namespace universal_ble
