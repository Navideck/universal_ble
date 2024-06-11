#pragma once

#include <cstdint>
#include <exception>
#include <string>

#include "winrt/Windows.Foundation.h"
#include "winrt/Windows.Storage.Streams.h"
#include "winrt/base.h"
#include "universal_ble_base.h"

constexpr uint32_t TEN_SECONDS_IN_MSECS = 10000;

namespace universal_ble
{

    std::string _mac_address_to_str(uint64_t mac_address);
    uint64_t _str_to_mac_address(std::string mac_address);

    winrt::guid uuid_to_guid(const std::string &uuid);
    std::string guid_to_uuid(const winrt::guid &guid);

    std::vector<uint8_t> to_bytevc(IBuffer buffer);
    IBuffer from_bytevc(std::vector<uint8_t> bytes);
    std::string to_hexstring(std::vector<uint8_t> bytes);

    std::string to_uuidstr(winrt::guid guid);
    bool isLittleEndian();
    bool isWindows11OrGreater();

    /// To call async functions synchronously
    template <typename async_t>
    static auto async_get(async_t const &async)
    {
        if (async.Status() == Foundation::AsyncStatus::Started)
        {
            wait_for_completed(async, TEN_SECONDS_IN_MSECS);
        }
        try
        {
            return async.GetResults();
        }
        catch (const winrt::hresult_error &err)
        {
            throw FlutterError(winrt::to_string(err.message()));
        }
        catch (...)
        {
            throw FlutterError("Unknown error");
        }
    }

} // namespace universal_ble