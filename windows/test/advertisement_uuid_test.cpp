// Covers the UUID expansion used when reading advertised Service Data. Builds
// and runs without a Flutter engine or WinRT:
// see windows/src/advertisement_uuid.h.
#include <cstdint>
#include <iostream>
#include <string>
#include <vector>

#include "advertisement_uuid.h"
#include "helper/universal_enum.h"

namespace {

using universal_ble::AdvertisementSectionType;
using universal_ble::ExpandServiceUuid;

int Failures = 0;

void Expect(bool condition, const std::string &what) {
  if (!condition) {
    std::cerr << "FAILED: " << what << "\n";
    Failures++;
  }
}

std::string Expand(const std::vector<uint8_t> &uuid_bytes,
                   AdvertisementSectionType type) {
  return ExpandServiceUuid(uuid_bytes, static_cast<uint8_t>(type));
}

}  // namespace

int main() {
  // Advertising data carries a 128-bit UUID little-endian, so the bytes on air
  // are the reverse of the canonical string (#356).
  const std::vector<uint8_t> air_128 = {0x09, 0xd4, 0xaf, 0x99, 0x79, 0x63,
                                        0x68, 0xa7, 0x39, 0x41, 0x3e, 0xf8,
                                        0xb2, 0xaa, 0xcd, 0x32};
  Expect(Expand(air_128, AdvertisementSectionType::ServiceData128BitUuids) ==
             "32cdaab2-f83e-4139-a768-637999afd409",
         "128-bit service data UUID is read little-endian");

  // A UUID that is already symmetric would hide a missing reversal, so check a
  // second one whose halves differ too.
  const std::vector<uint8_t> air_128_2 = {0xfb, 0x34, 0x9b, 0x5f, 0x80, 0x00,
                                          0x00, 0x80, 0x00, 0x10, 0x00, 0x00,
                                          0x0d, 0x18, 0x00, 0x00};
  Expect(Expand(air_128_2, AdvertisementSectionType::ServiceData128BitUuids) ==
             "0000180d-0000-1000-8000-00805f9b34fb",
         "128-bit UUID with a 16-bit alias keeps the alias in the tail");

  // 16-bit and 32-bit UUIDs are little-endian over the air and expand into the
  // Bluetooth base UUID.
  Expect(Expand({0x0d, 0x18},
                AdvertisementSectionType::ServiceData16BitUuids) ==
             "0000180d-0000-1000-8000-00805f9b34fb",
         "16-bit service data UUID expands to the full form");
  Expect(Expand({0x78, 0x56, 0x34, 0x12},
                AdvertisementSectionType::ServiceData32BitUuids) ==
             "12345678-0000-1000-8000-00805f9b34fb",
         "32-bit service data UUID expands to the full form");

  // Too short for the type, or not a service-data type at all: no UUID.
  Expect(Expand({0x0d}, AdvertisementSectionType::ServiceData16BitUuids)
             .empty(),
         "16-bit UUID shorter than 2 bytes is rejected");
  Expect(Expand({0x78, 0x56, 0x34},
                AdvertisementSectionType::ServiceData32BitUuids)
             .empty(),
         "32-bit UUID shorter than 4 bytes is rejected");
  Expect(Expand(std::vector<uint8_t>(15, 0x00),
                AdvertisementSectionType::ServiceData128BitUuids)
             .empty(),
         "128-bit UUID shorter than 16 bytes is rejected");
  Expect(Expand({0x0d, 0x18}, AdvertisementSectionType::Flags).empty(),
         "non service-data section is ignored");

  if (Failures == 0) {
    std::cout << "All advertisement UUID cases passed\n";
  }
  return Failures == 0 ? 0 : 1;
}
