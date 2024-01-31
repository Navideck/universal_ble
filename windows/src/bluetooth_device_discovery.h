#include <winrt/Windows.Devices.Bluetooth.Advertisement.h>

namespace universal_ble
{
    class BluetoothDeviceDiscovery
    {
    public:
        BluetoothDeviceDiscovery();
        ~BluetoothDeviceDiscovery();

        void initialize();
        void StartDiscovery();
        void StopDiscovery();

    private:
        winrt::Windows::Devices::Bluetooth::Advertisement::BluetoothLEAdvertisementWatcher watcher_;
    };
}
