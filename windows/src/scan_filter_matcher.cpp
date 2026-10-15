#include "scan_filter_matcher.h"

#include <algorithm>
#include <cctype>

namespace universal_ble {
namespace {

bool NameMatches(const std::vector<std::string> &prefixes,
                 const std::string &name) {
  if (name.empty()) {
    return false;
  }
  return std::any_of(prefixes.begin(), prefixes.end(),
                     [&name](const std::string &prefix) {
                       return name.rfind(prefix, 0) == 0;
                     });
}

bool ContainsAny(const std::vector<std::string> &filters,
                 const std::vector<std::string> &advertised) {
  for (const auto &filter : filters) {
    if (std::find(advertised.begin(), advertised.end(), filter) !=
        advertised.end()) {
      return true;
    }
  }
  return false;
}

/// Compares the advertised bytes against the filter's prefix, honouring the mask
/// when one is given (one bit set to 1 per prefix bit that must match).
bool DataMatches(const std::optional<std::vector<uint8_t>> &prefix,
                 const std::vector<uint8_t> &device_data,
                 const std::optional<std::vector<uint8_t>> &mask) {
  if (!prefix.has_value()) {
    return true;
  }
  if (prefix->size() > device_data.size()) {
    return false;
  }
  if (mask.has_value() && mask->size() != prefix->size()) {
    return false;
  }

  for (size_t i = 0; i < prefix->size(); i++) {
    const uint8_t mask_byte = mask.has_value() ? (*mask)[i] : 0xFF;
    if ((mask_byte & (*prefix)[i]) != (mask_byte & device_data[i])) {
      return false;
    }
  }
  return true;
}

bool ManufacturerDataMatches(
    const std::vector<ManufacturerDataFilterValue> &filters,
    const std::vector<ManufacturerDataValue> &advertised) {
  for (const auto &filter : filters) {
    for (const auto &data : advertised) {
      if (data.company_identifier == filter.company_identifier &&
          DataMatches(filter.payload_prefix, data.data, filter.payload_mask)) {
        return true;
      }
    }
  }
  return false;
}

/// Normalises a whole list, so both sides of a comparison use one form.
std::vector<std::string> NormalizeAll(const std::vector<std::string> &uuids) {
  std::vector<std::string> normalized;
  normalized.reserve(uuids.size());
  for (const auto &uuid : uuids) {
    normalized.push_back(NormalizeUuid(uuid));
  }
  return normalized;
}

}  // namespace

std::string NormalizeUuid(const std::string &uuid) {
  std::string hex;
  hex.reserve(uuid.size());
  for (const char c : uuid) {
    if (c != '-') {
      hex.push_back(static_cast<char>(
          std::tolower(static_cast<unsigned char>(c))));
    }
  }

  if (hex.size() == 4) {
    hex = "0000" + hex + "0000" + "1000" + "8000" + "00805f9b34fb";
  } else if (hex.size() == 8) {
    hex = hex + "0000" + "1000" + "8000" + "00805f9b34fb";
  }
  return hex;
}

bool HasAnyFilter(const ScanFilterValues &filter) {
  return !filter.name_prefix.empty() || !filter.services.empty() ||
         !filter.service_data.empty() || !filter.manufacturer_data.empty();
}

bool MatchesScanFilter(const ScanFilterValues &filter,
                       const AdvertisementValues &advertisement) {
  const auto filter_services = NormalizeAll(filter.services);
  const auto filter_service_data = NormalizeAll(filter.service_data);

  return NameMatches(filter.name_prefix, advertisement.name) ||
         ContainsAny(filter_services, NormalizeAll(advertisement.services)) ||
         ContainsAny(filter_service_data,
                     NormalizeAll(advertisement.service_data_uuids)) ||
         ManufacturerDataMatches(filter.manufacturer_data,
                                 advertisement.manufacturer_data);
}

}  // namespace universal_ble
