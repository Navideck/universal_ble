#pragma once

#include <cstdint>
#include <exception>
#include <string>

#include "helper/universal_ble_base.h"
#include "generated/universal_ble.g.h"

namespace universal_ble
{
    void setScanFilter(const UniversalScanFilter filter);
    void resetScanFilter();
    bool filterDevice(const std::string *name, const IVector<BluetoothLEManufacturerData> manufacturerData, const IVector<winrt::guid> serviceUuids);

} // namespace universal_ble