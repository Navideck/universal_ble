#include <iomanip>
#include <iostream>
#include <sstream>
#include <windows.h>
#include <stdio.h>
#include <sdkddkver.h>
#include <vector>
#include "helper/utils.h"
#include "generated/universal_ble.g.h"

namespace universal_ble
{
    std::vector<UniversalManufacturerDataFilter> manufacturerScanFilter = std::vector<UniversalManufacturerDataFilter>();
    std::vector<winrt::guid> serviceFilterUUIDS = std::vector<winrt::guid>();
    std::vector<std::string> namePrefixFilter = std::vector<std::string>();

    void setScanFilter(const UniversalScanFilter filter)
    {
        // Set ManufacturerData filter
        const auto &manufacturerData = filter.with_manufacturer_data();
        for (const flutter::EncodableValue &data : manufacturerData)
        {
            UniversalManufacturerDataFilter manufacturerDataFilter = std::any_cast<UniversalManufacturerDataFilter>(std::get<flutter::CustomEncodableValue>(data));
            manufacturerScanFilter.push_back(manufacturerDataFilter);
        }
        // Set Services Filter
        if (!filter.with_services().empty())
        {
            for (const auto &uuid : filter.with_services())
            {
                serviceFilterUUIDS.push_back(uuid_to_guid(std::get<std::string>(uuid)));
            }
        }
        // Set Names Filter
        if (!filter.with_name_prefix().empty())
        {
            for (const auto &name : filter.with_name_prefix())
            {
                namePrefixFilter.push_back(std::get<std::string>(name));
            }
        }
    }

    void resetScanFilter()
    {
        manufacturerScanFilter.clear();
        serviceFilterUUIDS.clear();
        namePrefixFilter.clear();
    }

    bool isNameMatchingFilters(const std::string *name)
    {
        if (namePrefixFilter.empty())
            return true;
        if (name == nullptr || name->empty())
            return false;
        return std::any_of(namePrefixFilter.begin(), namePrefixFilter.end(),
                           [&name](const flutter::EncodableValue &prefix)
                           {
                               // TODO: check if it only checks for NamePrefix or all
                               return name->find(std::get<std::string>(prefix)) == 0;
                           });
    }

    bool isServicesMatchingFilters(const IVector<winrt::guid> serviceUuids)
    {
        if (serviceFilterUUIDS.empty())
            return true;
        if (serviceUuids.Size() == 0)
            return false;
        return std::any_of(serviceFilterUUIDS.begin(), serviceFilterUUIDS.end(),
                           [&serviceUuids](const winrt::guid &serviceFilterUUID)
                           {
                               uint32_t index;
                               return serviceUuids.IndexOf(serviceFilterUUID, index);
                           });
    }

    bool isManufacturerDataMatchingFilters(IVector<BluetoothLEManufacturerData> deviceManufactureData)
    {
        if (manufacturerScanFilter.empty())
            return true;

        for (auto &&filter : manufacturerScanFilter)
        {
            const std::vector<uint8_t> *data_filter = filter.data();
            const std::vector<uint8_t> *mask = filter.mask();

            uint16_t companyId = static_cast<uint16_t>(filter.company_identifier());

            for (auto &&deviceMfData : deviceManufactureData)
            {
                if (deviceMfData.CompanyId() == companyId)
                {
                    // If data filter is not present then return true
                    if (data_filter == nullptr)
                        return true;

                    auto deviceData = to_bytevc(deviceMfData.Data());
                    if (deviceData.size() < data_filter->size())
                        continue;

                    bool isMatch = true;
                    for (size_t i = 0; i < data_filter->size(); i++)
                    {
                        if (mask != nullptr && mask->size() > i)
                        {
                            if (((*mask)[i] & (*data_filter)[i]) != ((*mask)[i] & deviceData[i]))
                            {
                                isMatch = false;
                                break;
                            }
                        }
                        else
                        {
                            if ((*data_filter)[i] != deviceData[i])
                            {
                                isMatch = false;
                                break;
                            }
                        }
                    }
                    if (isMatch)
                        return true;
                }
            }
        }

        return false;
    }

    bool filterDevice(const std::string *name, const IVector<BluetoothLEManufacturerData> manufacturerData, const IVector<winrt::guid> serviceUuids)
    {
        bool hasNamePrefixFilter = !namePrefixFilter.empty();
        bool hasServiceFilter = !serviceFilterUUIDS.empty();
        bool hasManufacturerDataFilter = !manufacturerScanFilter.empty();

        // If there is no filter at all, then allow device
        if (!hasNamePrefixFilter &&
            !hasServiceFilter &&
            !hasManufacturerDataFilter)
        {
            return true;
        }

        // Check each filter condition
        return (hasNamePrefixFilter && isNameMatchingFilters(name)) ||
               (hasServiceFilter && isServicesMatchingFilters(serviceUuids)) ||
               (hasManufacturerDataFilter && isManufacturerDataMatchingFilters(manufacturerData));
    }

} // namespace universal_ble
