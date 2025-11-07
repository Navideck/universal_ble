#pragma once

#include <cstdint>
#include <exception>
#include <string>

#include "winrt/Windows.Foundation.h"
#include "winrt/Windows.Storage.Streams.h"
#include "winrt/base.h"
#include "universal_ble_base.h"
#include "generated/universal_ble.g.h"

constexpr uint32_t TEN_SECONDS_IN_MSECS = 10000;

namespace universal_ble
{

    std::string mac_address_to_str(uint64_t mac_address);
    uint64_t str_to_mac_address(const std::string& mac_str);

    guid uuid_to_guid(const std::string &uuid);
    std::string guid_to_uuid(const guid &guid);

    std::vector<uint8_t> to_bytevc(const IBuffer& buffer);
    IBuffer from_bytevc(std::vector<uint8_t> bytes);
    std::string to_hexstring(const std::vector<uint8_t>& bytes);

    std::string to_uuidstr(guid guid);
    bool is_little_endian();
    bool is_windows11_or_greater();

    /// Maps string error codes to UniversalBleErrorCode enum
    UniversalBleErrorCode map_error_code_to_enum(const std::string& code);

    /// Maps GATT communication status to UniversalBleErrorCode enum
    UniversalBleErrorCode map_gatt_status_to_enum(const std::optional<std::string>& error);

    /// Creates a FlutterError with the error code enum in details
    FlutterError create_flutter_error(
        UniversalBleErrorCode code,
        const std::string& message = "",
        const std::string& details = ""
    );

    /// To call async functions synchronously
    template <typename AsyncT>
    static auto async_get(AsyncT const &async)
    {
        if (async.Status() == AsyncStatus::Started)
        {
            wait_for_completed(async, TEN_SECONDS_IN_MSECS);
        }
        try
        {
            return async.GetResults();
        }
        catch (const hresult_error &err)
        {
            throw FlutterError("Failed", to_string(err.message()));
        }
        catch (...)
        {
            throw FlutterError("Failed", "Unknown error");
        }
    }

} // namespace universal_ble