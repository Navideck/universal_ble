#ifndef FLUTTER_PLUGIN_UNIVERSAL_BLE_PLUGIN_H_
#define FLUTTER_PLUGIN_UNIVERSAL_BLE_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <windows.h>
#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/Windows.Devices.Enumeration.h>
#include <winrt/Windows.Devices.Radios.h>
#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Devices.Bluetooth.Advertisement.h>
#include <winrt/Windows.Devices.Bluetooth.GenericAttributeProfile.h>

#include <memory>
#include "helper/utils.h"
#include "helper/universal_enum.h"
#include "helper/universal_ble_base.h"
#include "generated/universal_ble.g.h"
#include "ui_thread_handler.hpp"

namespace universal_ble
{
    struct GattCharacteristicObject
    {
        GattCharacteristic obj = nullptr;
    };

    struct GattServiceObject
    {
        GattDeviceService obj = nullptr;
        std::unordered_map<std::string, GattCharacteristicObject> characteristics;
    };

    struct BluetoothDeviceAgent
    {
        BluetoothLEDevice device;
        winrt::event_token connnectionStatusChangedToken;
        std::unordered_map<std::string, GattServiceObject> gatt_map_;

        BluetoothDeviceAgent(BluetoothLEDevice device, winrt::event_token connnectionStatusChangedToken, std::unordered_map<std::string, GattServiceObject> gatt_map_)
            : device(device),
              connnectionStatusChangedToken(connnectionStatusChangedToken),
              gatt_map_(gatt_map_) {}

        ~BluetoothDeviceAgent()
        {
            device = nullptr;
        }

        GattCharacteristicObject &_fetch_characteristic(const std::string &service_uuid,
                                                        const std::string &characteristic_uuid)
        {
            if (gatt_map_.count(service_uuid) == 0)
                throw FlutterError("Service not found");
            if (gatt_map_[service_uuid].characteristics.count(characteristic_uuid) == 0)
                throw FlutterError("Characteristic not found");
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

        UniversalBleUiThreadHandler uiThreadHandler_;
        Radio bluetoothRadio{nullptr};
        RadioState oldRadioState = RadioState::Unknown;
        BluetoothLEAdvertisementWatcher bluetoothLEWatcher{nullptr};
        DeviceWatcher deviceWatcher{nullptr};
        std::unordered_map<uint64_t, std::unique_ptr<BluetoothDeviceAgent>> connectedDevices{};
        std::unordered_map<std::string, DeviceInformation> deviceWatcherDevices{};

        winrt::event_token bluetoothLEWatcherReceivedToken;
        winrt::event_token deviceWatcherAddedToken;
        winrt::event_token deviceWatcherUpdatedToken;
        winrt::event_token deviceWatcherRemovedToken;

        winrt::fire_and_forget InitializeAsync();
        void Radio_StateChanged(Radio sender, IInspectable args);

        void setupDeviceWatcher();
        void disposeDeviceWatcher();
        void pushUniversalScanResult(UniversalBleScanResult scanResult, bool isConnectable);
        void BluetoothLEWatcher_Received(BluetoothLEAdvertisementWatcher sender, BluetoothLEAdvertisementReceivedEventArgs args);
        void onDeviceInfoReceived(DeviceInformation deviceInfo);

        std::string GattCommunicationStatusToString(GattCommunicationStatus status);
        std::unordered_map<std::string, UniversalBleScanResult> scanResults{};
        winrt::event_revoker<IRadio> radioStateChangedRevoker;
        winrt::fire_and_forget ConnectAsync(uint64_t bluetoothAddress);
        void BluetoothLEDevice_ConnectionStatusChanged(BluetoothLEDevice sender, IInspectable args);
        void CleanConnection(uint64_t bluetoothAddress);
        void DiscoverServicesAsync(BluetoothDeviceAgent &bluetoothDeviceAgent, std::function<void(ErrorOr<flutter::EncodableList> reply)>);
        winrt::fire_and_forget SetNotifiableAsync(BluetoothDeviceAgent &bluetoothDeviceAgent, const std::string &service,
                                                  const std::string &characteristic, GattClientCharacteristicConfigurationDescriptorValue descriptorValue,
                                                  std::function<void(std::optional<FlutterError> reply)> result);
        void GattCharacteristic_ValueChanged(GattCharacteristic sender, GattValueChangedEventArgs args);
        AvailabilityState getAvailabilityStateFromRadio(RadioState radioState);
        std::string parsePairingFailError(Enumeration::DevicePairingResult result);
        winrt::fire_and_forget GetSystemDevicesAsync(std::vector<std::string> with_services,
                                                     std::function<void(ErrorOr<flutter::EncodableList> reply)> result);
        winrt::fire_and_forget IsPairedAsync(std::string device_id, std::function<void(ErrorOr<bool> reply)> result);
        winrt::fire_and_forget WriteAsync(GattCharacteristic characteristic, GattWriteOption writeOption,
                                          const std::vector<uint8_t> &value,
                                          std::function<void(std::optional<FlutterError> reply)> result);
        winrt::fire_and_forget PairAsync(std::string device_id, std::function<void(ErrorOr<bool> reply)> result);
        winrt::fire_and_forget CustomPairAsync(std::string device_id, std::function<void(ErrorOr<bool> reply)> result);
        void PairingRequestedHandler(DeviceInformationCustomPairing sender, DevicePairingRequestedEventArgs eventArgs);

        // UniversalBlePlatformChannel implementation.
        void GetBluetoothAvailabilityState(std::function<void(ErrorOr<int64_t> reply)> result) override;
        void EnableBluetooth(std::function<void(ErrorOr<bool> reply)> result) override;
        void DisableBluetooth(std::function<void(ErrorOr<bool> reply)> result) override;
        ErrorOr<int64_t> GetConnectionState(const std::string &device_id) override;
        std::optional<FlutterError> StartScan(const UniversalScanFilter *filter) override;
        std::optional<FlutterError> StopScan() override;
        std::optional<FlutterError> Connect(const std::string &device_id) override;
        std::optional<FlutterError> Disconnect(const std::string &device_id) override;
        void DiscoverServices(
            const std::string &device_id,
            std::function<void(ErrorOr<flutter::EncodableList> reply)> result) override;
        void SetNotifiable(
            const std::string &device_id,
            const std::string &service,
            const std::string &characteristic,
            int64_t ble_input_property,
            std::function<void(std::optional<FlutterError> reply)> result) override;
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
        void Pair(
            const std::string &device_id,
            std::function<void(ErrorOr<bool> reply)> result) override;
        std::optional<FlutterError> UnPair(const std::string &device_id) override;
        void GetSystemDevices(
            const flutter::EncodableList &with_services,
            std::function<void(ErrorOr<flutter::EncodableList> reply)> result);
    };

} // namespace universal_ble

#endif // FLUTTER_PLUGIN_UNIVERSAL_BLE_PLUGIN_H_