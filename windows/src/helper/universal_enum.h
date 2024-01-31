#pragma once

namespace universal_ble
{

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

} // namespace universal_ble