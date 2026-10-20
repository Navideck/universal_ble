#include "advertisement_uuid.h"

#include <cstdio>

#include "helper/universal_enum.h"

namespace universal_ble {

namespace {

// Formats the 16 little-endian bytes as the canonical lower-case UUID string:
// the whole 16 bytes are reversed (the last byte on air is the first in the
// string), then grouped 4-2-2-2-6.
std::string Format128BitUuid(const std::vector<uint8_t> &uuid_bytes) {
  char uuid_str[37];
  std::snprintf(uuid_str, sizeof(uuid_str),
                "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-"
                "%02x%02x%02x%02x%02x%02x",
                uuid_bytes[15], uuid_bytes[14], uuid_bytes[13], uuid_bytes[12],
                uuid_bytes[11], uuid_bytes[10], uuid_bytes[9], uuid_bytes[8],
                uuid_bytes[7], uuid_bytes[6], uuid_bytes[5], uuid_bytes[4],
                uuid_bytes[3], uuid_bytes[2], uuid_bytes[1], uuid_bytes[0]);
  return uuid_str;
}

}  // namespace

std::string ExpandServiceUuid(const std::vector<uint8_t> &uuid_bytes,
                              uint8_t uuid_type) {
  switch (static_cast<AdvertisementSectionType>(uuid_type)) {
    case AdvertisementSectionType::ServiceData16BitUuids: {
      // 16-bit UUID: expand to full 128-bit format.
      if (uuid_bytes.size() < 2) {
        return {};
      }
      const uint16_t uuid_16 = static_cast<uint16_t>(uuid_bytes[0]) |
                               (static_cast<uint16_t>(uuid_bytes[1]) << 8);
      char uuid_str[37];
      std::snprintf(uuid_str, sizeof(uuid_str),
                    "0000%04x-0000-1000-8000-00805f9b34fb",
                    static_cast<unsigned int>(uuid_16));
      return uuid_str;
    }
    case AdvertisementSectionType::ServiceData32BitUuids: {
      // 32-bit UUID: expand to full 128-bit format.
      if (uuid_bytes.size() < 4) {
        return {};
      }
      const uint32_t uuid_32 =
          static_cast<uint32_t>(uuid_bytes[0]) |
          (static_cast<uint32_t>(uuid_bytes[1]) << 8) |
          (static_cast<uint32_t>(uuid_bytes[2]) << 16) |
          (static_cast<uint32_t>(uuid_bytes[3]) << 24);
      char uuid_str[37];
      std::snprintf(uuid_str, sizeof(uuid_str),
                    "%08x-0000-1000-8000-00805f9b34fb",
                    static_cast<unsigned int>(uuid_32));
      return uuid_str;
    }
    case AdvertisementSectionType::ServiceData128BitUuids: {
      if (uuid_bytes.size() < 16) {
        return {};
      }
      return Format128BitUuid(uuid_bytes);
    }
    default:
      return {};
  }
}

}  // namespace universal_ble
