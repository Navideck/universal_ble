#include "universal_ble_filter_util.h"

#include <unordered_set>
#include <vector>

#include "helper/utils.h"
#include "scan_filter_matcher.h"

namespace universal_ble {

// The filter of the current scan, plus the last one it was set from. The matching
// rules themselves live in scan_filter_matcher.cpp; this file only translates
// the pigeon/flutter types into the plain ones it works with.
namespace {
ScanFilterValues scanFilterValues;
}  // namespace

namespace {

std::vector<std::string> ToStringList(const flutter::EncodableList &list) {
  std::vector<std::string> result;
  result.reserve(list.size());
  for (const auto &value : list) {
    if (const auto *str = std::get_if<std::string>(&value)) {
      result.push_back(*str);
    }
  }
  return result;
}

std::vector<uint8_t> ToBytes(const flutter::EncodableValue &value) {
  if (const auto *bytes = std::get_if<std::vector<uint8_t>>(&value)) {
    return *bytes;
  }
  return {};
}

std::vector<ManufacturerDataFilterValue> ToManufacturerFilters(
    const flutter::EncodableList &list) {
  std::vector<ManufacturerDataFilterValue> result;
  result.reserve(list.size());
  for (const auto &value : list) {
    const auto &filter = std::any_cast<const ManufacturerDataFilter &>(
        std::get<flutter::CustomEncodableValue>(value));
    ManufacturerDataFilterValue plain;
    plain.company_identifier = filter.company_identifier();
    if (const auto *prefix = filter.payload_prefix()) {
      plain.payload_prefix = *prefix;
    }
    if (const auto *mask = filter.payload_mask()) {
      plain.payload_mask = *mask;
    }
    result.push_back(plain);
  }
  return result;
}

AdvertisementValues ToAdvertisementValues(
    const UniversalBleScanResult &scanResult) {
  AdvertisementValues advertisement;
  if (const auto *name = scanResult.name()) {
    advertisement.name = *name;
  }
  if (const auto *services = scanResult.services()) {
    advertisement.services = ToStringList(*services);
  }
  if (const auto *service_data = scanResult.service_data()) {
    advertisement.service_data_uuids.reserve(service_data->size());
    for (const auto &entry : *service_data) {
      if (const auto *uuid = std::get_if<std::string>(&entry.first)) {
        advertisement.service_data_uuids.push_back(*uuid);
      }
    }
  }
  if (const auto *manufacturer_data = scanResult.manufacturer_data_list()) {
    advertisement.manufacturer_data.reserve(manufacturer_data->size());
    for (const auto &value : *manufacturer_data) {
      const auto &data = std::any_cast<const UniversalManufacturerData &>(
          std::get<flutter::CustomEncodableValue>(value));
      ManufacturerDataValue plain;
      plain.company_identifier = data.company_identifier();
      plain.data = data.data();
      advertisement.manufacturer_data.push_back(plain);
    }
  }
  return advertisement;
}

}  // namespace

void setScanFilter(const UniversalScanFilter filter) {
  scanFilterValues = ScanFilterValues();
  scanFilterValues.services = ToStringList(filter.with_services());
  scanFilterValues.service_data = ToStringList(filter.with_service_data());
  scanFilterValues.name_prefix = ToStringList(filter.with_name_prefix());
  scanFilterValues.manufacturer_data =
      ToManufacturerFilters(filter.with_manufacturer_data());
}

void resetScanFilter() { scanFilterValues = ScanFilterValues(); }

bool filterDevice(UniversalBleScanResult scanResult) {
  if (!HasAnyFilter(scanFilterValues)) {
    return true;
  }
  return MatchesScanFilter(scanFilterValues, ToAdvertisementValues(scanResult));
}

}  // namespace universal_ble
