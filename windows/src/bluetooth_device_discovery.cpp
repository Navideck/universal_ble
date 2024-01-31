// bluetooth_device_discovery.cpp

#include "bluetooth_device_discovery.h"

namespace universal_ble
{
    BluetoothDeviceDiscovery::BluetoothDeviceDiscovery()
        : watcher_(winrt::Windows::Devices::Bluetooth::Advertisement::BluetoothLEAdvertisementWatcher())
    {
    }
    BluetoothDeviceDiscovery::~BluetoothDeviceDiscovery()
    {
        StopDiscovery();
    }

    void BluetoothDeviceDiscovery::initialize()
    {
    }

    void BluetoothDeviceDiscovery::StartDiscovery()
    {
        watcher_.Start();
    }

    void BluetoothDeviceDiscovery::StopDiscovery()
    {
        if (watcher_.Status() == winrt::Windows::Devices::Bluetooth::Advertisement::BluetoothLEAdvertisementWatcherStatus::Started)
        {
            watcher_.Stop();
        }
    }

} // namespace universal_ble