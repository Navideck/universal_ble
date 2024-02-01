#pragma once

#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Devices.Bluetooth.Advertisement.h>
#include <winrt/Windows.Devices.Bluetooth.GenericAttributeProfile.h>
#include <winrt/Windows.Devices.Enumeration.h>
#include <winrt/Windows.Devices.Radios.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Storage.Streams.h>

namespace universal_ble
{
    using namespace winrt;
    using namespace winrt::Windows;
    using namespace winrt::Windows::Devices;
    using namespace winrt::Windows::Foundation;
    using namespace winrt::Windows::Foundation::Collections;
    using namespace winrt::Windows::Storage::Streams;
    using namespace winrt::Windows::Devices::Radios;
    using namespace winrt::Windows::Devices::Bluetooth;
    using namespace winrt::Windows::Devices::Bluetooth::Advertisement;
    using namespace winrt::Windows::Devices::Bluetooth::GenericAttributeProfile;
    using namespace Windows::Devices::Enumeration;

    // Define all enums
    enum class ConnectionState : int
    {
        connected = 0,
        disconnected = 1,
    };

    enum class CharacteristicProperty : int
    {
        broadcast = 0,
        read = 1,
        writeWithoutResponse = 2,
        write = 3,
        notify = 4,
        indicate = 5,
        authenticatedSignedWrites = 6,
        extendedProperties = 7,
    };

    enum class BleInputProperty : int
    {
        disabled = 0,
        notification = 1,
        indication = 2,
    };

    enum class BleOutputProperty : int
    {
        withResponse = 0,
        withoutResponse = 1,
    };

    enum class AvailabilityState : int
    {
        unknown = 0,
        resetting = 1,
        unsupported = 2,
        unauthorized = 3,
        poweredOff = 4,
        poweredOn = 5,
    };

}