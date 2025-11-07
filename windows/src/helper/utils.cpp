#include "Utils.h"
#include "generated/universal_ble.g.h"

#include <iomanip>
#include <iostream>
#include <sstream>
#include <algorithm>
#include <windows.h>
#include <stdio.h>
#include <sdkddkver.h>

#if WDK_NTDDI_VERSION < NTDDI_WIN10_VB
#error "Windows SDK version before 10.0.19041.0 is not supported"
#elif WDK_NTDDI_VERSION == NTDDI_WIN10_VB
#define WINRT_IMPL_CoGetApartmentType WINRT_CoGetApartmentType
#endif

#define MAC_ADDRESS_STR_LENGTH (size_t)17
typedef LONG NTSTATUS, *PNTSTATUS;
#define STATUS_SUCCESS (0x00000000)
typedef NTSTATUS(WINAPI *RtlGetVersionPtr)(PRTL_OSVERSIONINFOW);

namespace universal_ble
{

    std::string mac_address_to_str(uint64_t mac_address)
    {
        uint8_t* mac_ptr = (uint8_t*)&mac_address;
        char mac_str[MAC_ADDRESS_STR_LENGTH + 1] = { 0 };
        snprintf(mac_str, MAC_ADDRESS_STR_LENGTH + 1, "%02x:%02x:%02x:%02x:%02x:%02x", mac_ptr[5], mac_ptr[4], mac_ptr[3],
            mac_ptr[2], mac_ptr[1], mac_ptr[0]);
        return std::string(mac_str);
    }

    uint64_t str_to_mac_address(const std::string& mac_str)
    {
        uint64_t mac_address_number = 0;
        uint8_t* mac_ptr = (uint8_t*)&mac_address_number;
        sscanf_s(mac_str.c_str(), "%02hhx:%02hhx:%02hhx:%02hhx:%02hhx:%02hhx", &mac_ptr[5], &mac_ptr[4], &mac_ptr[3],
            &mac_ptr[2], &mac_ptr[1], &mac_ptr[0]);
        return mac_address_number;
    }

    guid uuid_to_guid(const std::string &uuid)
    {
        std::stringstream helper;
        for (int i = 0; i < uuid.length(); i++)
        {
            if (uuid[i] != '-')
            {
                helper << uuid[i];
            }
        }
        std::string clean_uuid = helper.str();
        winrt::guid guid;
        uint64_t* data4_ptr = (uint64_t*)guid.Data4;

        guid.Data1 = static_cast<uint32_t>(std::strtoul(clean_uuid.substr(0, 8).c_str(), nullptr, 16));
        guid.Data2 = static_cast<uint16_t>(std::strtoul(clean_uuid.substr(8, 4).c_str(), nullptr, 16));
        guid.Data3 = static_cast<uint16_t>(std::strtoul(clean_uuid.substr(12, 4).c_str(), nullptr, 16));
        *data4_ptr = _byteswap_uint64(std::strtoull(clean_uuid.substr(16, 16).c_str(), nullptr, 16));

        return guid;
    }

    std::string guid_to_uuid(const guid &guid)
    {
        std::stringstream helper;
        for (uint32_t i = 0; i < 4; i++)
        {
            helper << std::hex << std::setw(2) << std::setfill('0') << (int)((uint8_t*)&guid.Data1)[3 - i];
        }
        helper << '-';
        for (uint32_t i = 0; i < 2; i++)
        {
            helper << std::hex << std::setw(2) << std::setfill('0') << (int)((uint8_t*)&guid.Data2)[1 - i];
        }
        helper << '-';
        for (uint32_t i = 0; i < 2; i++)
        {
            helper << std::hex << std::setw(2) << std::setfill('0') << (int)((uint8_t*)&guid.Data3)[1 - i];
        }
        helper << '-';
        for (uint32_t i = 0; i < 2; i++)
        {
            helper << std::hex << std::setw(2) << std::setfill('0') << (int)guid.Data4[i];
        }
        helper << '-';
        for (uint32_t i = 0; i < 6; i++)
        {
            helper << std::hex << std::setw(2) << std::setfill('0') << (int)guid.Data4[2 + i];
        }
        return helper.str();
    }

    std::vector<uint8_t> to_bytevc(const IBuffer& buffer)
    {
        auto reader = DataReader::FromBuffer(buffer);
        auto result = std::vector<uint8_t>(reader.UnconsumedBufferLength());
        reader.ReadBytes(result);
        return result;
    }

    IBuffer from_bytevc(std::vector<uint8_t> bytes)
    {
        auto writer = DataWriter();
        writer.WriteBytes(bytes);
        return writer.DetachBuffer();
    }

    std::string to_hexstring(const std::vector<uint8_t>& bytes)
    {
        auto ss = std::stringstream();
        for (auto b : bytes)
            ss << std::setw(2) << std::setfill('0') << std::hex << static_cast<int>(b);
        return ss.str();
    }

    std::string to_uuidstr(const guid guid)
    {
        char chars[36 + 1];
        sprintf_s(chars, "%08x-%04hx-%04hx-%02hhx%02hhx-%02hhx%02hhx%02hhx%02hhx%02hhx%02hhx",
            guid.Data1, guid.Data2, guid.Data3, guid.Data4[0], guid.Data4[1], guid.Data4[2],
            guid.Data4[3], guid.Data4[4], guid.Data4[5], guid.Data4[6], guid.Data4[7]);
        return std::string{ chars };
    }

    bool is_little_endian()
    {
        uint16_t number = 0x1;
        char* numPtr = (char*)&number;
        return (numPtr[0] == 1);
    }

    bool is_windows11_or_greater()
    {
        const HMODULE h_mod = GetModuleHandleW(L"ntdll.dll");
        if (!h_mod)
        {
            std::cout << "Failed to get ntdll" << std::endl;
            return false;
        }

        const auto fx_ptr = reinterpret_cast<RtlGetVersionPtr>(GetProcAddress(h_mod, "RtlGetVersion"));
        if (fx_ptr == nullptr)
        {
            std::cout << "Failed to get RtlGetVersionPtr" << std::endl;
            return false;
        }

        RTL_OSVERSIONINFOW rove = {0};
        rove.dwOSVersionInfoSize = sizeof(rove);
        if (STATUS_SUCCESS != fx_ptr(&rove))
        {
            std::cout << "Failed to get RTL_OSVERSIONINFOW" << std::endl;
            return false;
        }

        // Windows 11 => MajorVersion = 10 and BuildNumber >= 22000
        return rove.dwMajorVersion == 10 && rove.dwBuildNumber >= 22000;
    }

    UniversalBleErrorCode map_error_code_to_enum(const std::string& code)
    {
        std::string lower_code = code;
        std::transform(lower_code.begin(), lower_code.end(), lower_code.begin(), ::tolower);
        
        if (lower_code == "notsupported" || lower_code == "not_supported")
            return UniversalBleErrorCode::kNotSupported;
        if (lower_code == "notimplemented" || lower_code == "not_implemented")
            return UniversalBleErrorCode::kNotImplemented;
        if (lower_code == "channel-error" || lower_code == "channelerror")
            return UniversalBleErrorCode::kChannelError;
        if (lower_code == "failed")
            return UniversalBleErrorCode::kFailed;
        if (lower_code == "bluetoothnotavailable" || lower_code == "bluetooth_not_available")
            return UniversalBleErrorCode::kBluetoothNotAvailable;
        if (lower_code == "bluetoothnotenabled" || lower_code == "bluetooth_not_enabled")
            return UniversalBleErrorCode::kBluetoothNotEnabled;
        if (lower_code == "devicedisconnected" || lower_code == "device_disconnected")
            return UniversalBleErrorCode::kDeviceDisconnected;
        if (lower_code == "illegalargument" || lower_code == "illegal_argument")
            return UniversalBleErrorCode::kIllegalArgument;
        if (lower_code == "invalidaction" || lower_code == "invalid_action")
            return UniversalBleErrorCode::kInvalidAction;
        if (lower_code == "devicenotfound" || lower_code == "device_not_found")
            return UniversalBleErrorCode::kDeviceNotFound;
        if (lower_code == "servicenotfound" || lower_code == "service_not_found")
            return UniversalBleErrorCode::kServiceNotFound;
        if (lower_code == "characteristicnotfound" || lower_code == "characteristic_not_found")
            return UniversalBleErrorCode::kCharacteristicNotFound;
        if (lower_code == "invalidserviceuuid" || lower_code == "invalid_service_uuid")
            return UniversalBleErrorCode::kInvalidServiceUuid;
        if (lower_code == "readfailed" || lower_code == "read_failed")
            return UniversalBleErrorCode::kReadFailed;
        if (lower_code == "writefailed" || lower_code == "write_failed")
            return UniversalBleErrorCode::kWriteFailed;
        if (lower_code == "notpaired" || lower_code == "not_paired")
            return UniversalBleErrorCode::kNotPaired;
        if (lower_code == "notpairable" || lower_code == "not_pairable")
            return UniversalBleErrorCode::kNotPairable;
        if (lower_code == "alreadyinprogress" || lower_code == "already_in_progress")
            return UniversalBleErrorCode::kOperationInProgress;
        if (lower_code == "stopping scan in progress" || lower_code == "stoppingscaninprogress")
            return UniversalBleErrorCode::kStoppingScanInProgress;
        
        return UniversalBleErrorCode::kUnknownError;
    }

    UniversalBleErrorCode map_gatt_status_to_enum(const std::optional<std::string>& error)
    {
        if (!error.has_value())
            return UniversalBleErrorCode::kUnknownError;
        
        std::string lower_error = error.value();
        std::transform(lower_error.begin(), lower_error.end(), lower_error.begin(), ::tolower);
        
        // Consolidated: Windows-specific GATT errors -> failed
        if (lower_error == "unreachable" || 
            lower_error == "protocolerror" || lower_error == "protocol_error" ||
            lower_error == "accessdenied" || lower_error == "access_denied")
            return UniversalBleErrorCode::kFailed;
        
        return UniversalBleErrorCode::kFailed;
    }

    FlutterError create_flutter_error(
        UniversalBleErrorCode code,
        const std::string& message,
        const std::string& details
    )
    {
        // Pass the enum's underlying integer value as string in code, and enum name or details in details
        std::string code_str = std::to_string(static_cast<int>(code));
        std::string details_str = details.empty() ? std::to_string(static_cast<int>(code)) : details;
        return FlutterError(code_str, message, details_str);
    }

} // namespace universal_ble
