#pragma once

#include <cstdint>
#include <exception>
#include <string>

#include "winrt/Windows.Foundation.h"
#include "winrt/Windows.Storage.Streams.h"
#include "winrt/Windows.Devices.Bluetooth.GenericAttributeProfile.h"
#include "winrt/base.h"
#include "universal_ble_base.h"
#include "../generated/universal_ble.g.h"
#include "universal_ble_logger.h" 

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

    /// Creates a FlutterError with the error code enum in details
    FlutterError create_flutter_error(
        UniversalBleErrorCode code,
        const std::string& message = "",
        const std::string& details = ""
    );


    // Error creation functions
    /// Creates a FlutterError from GATT communication status
    FlutterError create_flutter_error_from_gatt_communication_status(
        GattCommunicationStatus status,
        const std::string& message = ""
    );

    /// Creates a FlutterError from device pairing result status
    FlutterError create_flutter_error_from_pairing_status(
        DevicePairingResultStatus status,
        const std::string& message = ""
    );

    /// Creates a FlutterError from device unpairing result status
    FlutterError create_flutter_error_from_unpairing_status(
        DeviceUnpairingResultStatus status,
        const std::string& message = ""
    );
    
    // Create Flutter unknown error
    inline FlutterError create_flutter_unknown_error(
        const std::string& message = "Unknown error"
    ) {
        return create_flutter_error(UniversalBleErrorCode::kUnknownError, message);
    }

    inline void log_and_swallow(const char* where, const std::exception& ex) { 
        UniversalBleLogger::LogError(std::string(where) + ": " + ex.what()); 
    } 

    inline void log_and_swallow_unknown(const char* where) { 
        UniversalBleLogger::LogError(std::string(where) + ": unknown native exception"); 
    } 

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
            throw create_flutter_error(UniversalBleErrorCode::kFailed, to_string(err.message()));
        }
        catch (...)
        {
            throw create_flutter_unknown_error();
        }
    }

} // namespace universal_ble