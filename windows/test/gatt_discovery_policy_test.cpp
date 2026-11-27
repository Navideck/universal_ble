// Covers the GATT status policy discovery uses. Windows denies app access to a
// few services it reserves for itself (HID over GATT, 0x1812, is the common
// one) and answers GetCharacteristicsAsync with AccessDenied for them, so that
// single status is skipped. Every other status, including one this policy has
// never seen, still ends discovery. The loops that consume the classification
// are covered by the Windows HIL suite, which needs a physical device and does
// not run in CI: see windows/src/gatt_discovery_policy.h and
// hil/integration_test/baseline_hil_test.dart.
#include <iostream>
#include <string>

#include "gatt_discovery_policy.h"

namespace {

using Status =
    winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
        GattCommunicationStatus;
using universal_ble::classify_discovery_status;
using universal_ble::GattDiscoveryAction;

int Failures = 0;

void Expect(bool condition, const std::string &what) {
  if (!condition) {
    std::cerr << "FAILED: " << what << "\n";
    Failures++;
  }
}

}  // namespace

int main() {
  Expect(classify_discovery_status(Status::Success) ==
             GattDiscoveryAction::kInclude,
         "Success includes the service");
  Expect(classify_discovery_status(Status::AccessDenied) ==
             GattDiscoveryAction::kSkipDenied,
         "AccessDenied names a service the OS denies to apps");
  Expect(classify_discovery_status(Status::Unreachable) ==
             GattDiscoveryAction::kFail,
         "Unreachable still fails discovery");
  Expect(classify_discovery_status(Status::ProtocolError) ==
             GattDiscoveryAction::kFail,
         "ProtocolError still fails discovery");
  Expect(classify_discovery_status(static_cast<Status>(99)) ==
             GattDiscoveryAction::kFail,
         "An unknown status fails discovery instead of being skipped");

  if (Failures != 0) {
    std::cerr << Failures << " check(s) failed\n";
    return 1;
  }
  std::cout << "gatt_discovery_policy_test passed\n";
  return 0;
}
