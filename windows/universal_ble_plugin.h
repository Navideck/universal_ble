#ifndef FLUTTER_PLUGIN_UNIVERSAL_BLE_PLUGIN_H_
#define FLUTTER_PLUGIN_UNIVERSAL_BLE_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <windows.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/Windows.Devices.Enumeration.h>
#include <winrt/Windows.Devices.Radios.h>
#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Devices.Bluetooth.Advertisement.h>
#include <winrt/Windows.Devices.Bluetooth.GenericAttributeProfile.h>

#include <memory>
#include "Utils.h"
#include "UniversalBle.g.h"
#include "universal_enum.h"

namespace universal_ble
{
    using namespace winrt;
    using namespace winrt::Windows::Devices;
    using namespace winrt::Windows::Foundation;
    using namespace winrt::Windows::Foundation::Collections;
    using namespace winrt::Windows::Storage::Streams;
    using namespace winrt::Windows::Devices::Radios;
    using namespace winrt::Windows::Devices::Bluetooth;
    using namespace winrt::Windows::Devices::Bluetooth::Advertisement;
    using namespace winrt::Windows::Devices::Bluetooth::GenericAttributeProfile;
    using namespace Windows::Devices::Enumeration;

    struct gatt_characteristic_t
    {
        GattCharacteristic obj = nullptr;
        // winrt::event_token value_changed_token;
    };

    struct gatt_service_t
    {
        GattDeviceService obj = nullptr;
        std::map<std::string, gatt_characteristic_t> characteristics;
    };

    struct BluetoothDeviceAgent
    {
        BluetoothLEDevice device;
        winrt::event_token connnectionStatusChangedToken;
        std::map<std::string, gatt_service_t> gatt_map_;

        BluetoothDeviceAgent(BluetoothLEDevice device, winrt::event_token connnectionStatusChangedToken, std::map<std::string, gatt_service_t> gatt_map_)
            : device(device),
              connnectionStatusChangedToken(connnectionStatusChangedToken),
              gatt_map_(gatt_map_) {}

        ~BluetoothDeviceAgent()
        {
            device = nullptr;
        }

        gatt_characteristic_t &_fetch_characteristic(const std::string &service_uuid,
                                                     const std::string &characteristic_uuid)
        {
            if (gatt_map_.count(service_uuid) == 0)
            {
                throw FlutterError("Service not found");
            }

            if (gatt_map_[service_uuid].characteristics.count(characteristic_uuid) == 0)
            {
                throw FlutterError("Characteristic not found");
            }

            return gatt_map_[service_uuid].characteristics.at(characteristic_uuid);
        }
    };

    class UniversalBlePlugin : public flutter::Plugin, public UniversalBlePlatformChannel
    {
    public:
        static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

        UniversalBlePlugin(flutter::PluginRegistrarWindows *registrar);

        ~UniversalBlePlugin();

        static void SuccessCallback() {}
        static void ErrorCallback(const FlutterError &error)
        {
            std::cout << "ErrorCallback: " << error.message() << std::endl;
        }

        // Disallow copy and assign.
        UniversalBlePlugin(const UniversalBlePlugin &) = delete;
        UniversalBlePlugin &operator=(const UniversalBlePlugin &) = delete;

        flutter::PluginRegistrarWindows *registrar_;
        int64_t window_proc_delegate_id_ = -1;

        HWND GetWindow();
        std::optional<LRESULT> WindowProcDelegate(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);
        winrt::fire_and_forget InitializeAsync();
        Radio bluetoothRadio{nullptr};
        void Radio_StateChanged(Radio sender, IInspectable args);
        RadioState oldRadioState = RadioState::Unknown;
        BluetoothLEAdvertisementWatcher bluetoothLEWatcher{nullptr};
        winrt::event_token bluetoothLEWatcherReceivedToken;
        void BluetoothLEWatcher_Received(BluetoothLEAdvertisementWatcher sender, BluetoothLEAdvertisementReceivedEventArgs args);
        std::map<uint64_t, std::unique_ptr<BluetoothDeviceAgent>> connectedDevices{};
        std::map<uint64_t, bool> deviceConnectableStatus{};
        winrt::event_revoker<IRadio> radioStateChangedRevoker;
        winrt::fire_and_forget ConnectAsync(uint64_t bluetoothAddress);
        void BluetoothLEDevice_ConnectionStatusChanged(BluetoothLEDevice sender, IInspectable args);
        void CleanConnection(uint64_t bluetoothAddress);
        winrt::fire_and_forget DiscoverServicesAsync(BluetoothDeviceAgent &bluetoothDeviceAgent, std::function<void(ErrorOr<flutter::EncodableList> reply)>);
        winrt::fire_and_forget SetNotifiableAsync(BluetoothDeviceAgent &bluetoothDeviceAgent, const std::string &service,
                                                  const std::string &characteristic, GattClientCharacteristicConfigurationDescriptorValue descriptorValue);
        void GattCharacteristic_ValueChanged(GattCharacteristic sender, GattValueChangedEventArgs args);
        AvailabilityState getAvailabilityStateFromRadio(RadioState radioState);
        std::string parsePairingFailError(Enumeration::DevicePairingResult result);
        void PostConnectionUpdate(uint64_t bluetoothAddress, ConnectionState connectionState);
        winrt::fire_and_forget GetConnectedDevicesAsync(std::vector<std::string> with_services,
                                                        std::function<void(ErrorOr<flutter::EncodableList> reply)> result);
        winrt::fire_and_forget IsPairedAsync(std::string device_id, std::function<void(ErrorOr<bool> reply)> result);

        // UniversalBlePlatformChannel implementation.
        void GetBluetoothAvailabilityState(std::function<void(ErrorOr<int64_t> reply)> result) override;
        void EnableBluetooth(std::function<void(ErrorOr<bool> reply)> result) override;
        std::optional<FlutterError> StartScan() override;
        std::optional<FlutterError> StopScan() override;
        std::optional<FlutterError> Connect(const std::string &device_id) override;
        std::optional<FlutterError> Disconnect(const std::string &device_id) override;
        void DiscoverServices(
            const std::string &device_id,
            std::function<void(ErrorOr<flutter::EncodableList> reply)> result) override;
        std::optional<FlutterError> SetNotifiable(
            const std::string &device_id,
            const std::string &service,
            const std::string &characteristic,
            int64_t ble_input_property) override;
        void ReadValue(
            const std::string &device_id,
            const std::string &service,
            const std::string &characteristic,
            std::function<void(ErrorOr<std::vector<uint8_t>> reply)> result) override;
        void WriteValue(
            const std::string &device_id,
            const std::string &service,
            const std::string &characteristic,
            const std::vector<uint8_t> &value,
            int64_t ble_output_property,
            std::function<void(std::optional<FlutterError> reply)> result) override;
        void RequestMtu(
            const std::string &device_id,
            int64_t expected_mtu,
            std::function<void(ErrorOr<int64_t> reply)> result) override;
        void IsPaired(
            const std::string &device_id,
            std::function<void(ErrorOr<bool> reply)> result) override;
        std::optional<FlutterError> Pair(const std::string &device_id) override;
        std::optional<FlutterError> UnPair(const std::string &device_id) override;
        void GetConnectedDevices(
            const flutter::EncodableList &with_services,
            std::function<void(ErrorOr<flutter::EncodableList> reply)> result);
    };

} // namespace universal_ble

#endif // FLUTTER_PLUGIN_UNIVERSAL_BLE_PLUGIN_H_