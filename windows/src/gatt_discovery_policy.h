#pragma once

#include <winrt/Windows.Devices.Bluetooth.GenericAttributeProfile.h>

namespace universal_ble {

// What discovery does with one service once GetCharacteristicsAsync returned.
enum class GattDiscoveryAction {
  // The characteristics came back; add the service and its characteristics to
  // the service map.
  kInclude,
  // Windows denies app access to a few GATT services it reserves for itself -
  // HID over GATT (0x1812) is the common one - and answers
  // GetCharacteristicsAsync with AccessDenied for them whether or not the
  // device is paired. The service is unusable to an app, but the rest of the
  // database is not, so it is left out instead of failing the connection
  // (#400).
  kSkipDenied,
  // Any other failure ends discovery, so a query a dropped link cut short is
  // still reported (#284).
  kFail,
};

inline GattDiscoveryAction classify_discovery_status(
    const winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
        GattCommunicationStatus status) noexcept {
  using winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
      GattCommunicationStatus;
  if (status == GattCommunicationStatus::Success) {
    return GattDiscoveryAction::kInclude;
  }
  if (status == GattCommunicationStatus::AccessDenied) {
    return GattDiscoveryAction::kSkipDenied;
  }
  return GattDiscoveryAction::kFail;
}

}  // namespace universal_ble
