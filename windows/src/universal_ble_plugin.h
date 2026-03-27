#ifndef FLUTTER_PLUGIN_UNIVERSAL_BLE_PLUGIN_H_
#define FLUTTER_PLUGIN_UNIVERSAL_BLE_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <windows.h>
#include <winrt/Windows.Devices.Bluetooth.Advertisement.h>
#include <winrt/Windows.Devices.Bluetooth.GenericAttributeProfile.h>
#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Devices.Enumeration.h>
#include <winrt/Windows.Devices.Radios.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/base.h>

#include "generated/universal_ble.g.h"
#include "generated/universal_ble_peripheral.g.h"
#include "helper/universal_ble_base.h"
#include "helper/universal_enum.h"
#include "helper/utils.h"
#include "ui_thread_handler.hpp"
#include "universal_ble_thread_safe.h"
#include <memory>

namespace universal_ble {
struct GattCharacteristicObject {
  GattCharacteristic obj = nullptr;
  std::optional<event_token> subscription_token;
};

struct GattServiceObject {
  GattDeviceService obj = nullptr;
  std::unordered_map<std::string, GattCharacteristicObject> characteristics;
};

struct PeripheralGattCharacteristicObject {
  GattLocalCharacteristic obj = nullptr;
  event_token read_requested_token{};
  event_token write_requested_token{};
  event_token subscribed_clients_changed_token{};
  IVectorView<GattSubscribedClient> stored_clients = nullptr;
};

struct PeripheralGattServiceProviderObject {
  GattServiceProvider obj = nullptr;
  event_token advertisement_status_changed_token{};
  std::unordered_map<std::string, std::unique_ptr<PeripheralGattCharacteristicObject>>
      characteristics;
};

enum class PeripheralBlePermission {
  none,
  readable,
  writeable,
  readEncryptionRequired,
  writeEncryptionRequired,
};

struct BluetoothDeviceAgent {
  BluetoothLEDevice device;
  event_token connection_status_changed_token;
  std::unordered_map<std::string, GattServiceObject> gatt_map;

  BluetoothDeviceAgent(
      const BluetoothLEDevice &device,
      const event_token connection_status_changed_token,
      const std::unordered_map<std::string, GattServiceObject> &gatt_map)
      : device(device),
        connection_status_changed_token(connection_status_changed_token),
        gatt_map(gatt_map) {}

  ~BluetoothDeviceAgent() { device = nullptr; }

  GattCharacteristicObject &
  FetchCharacteristic(const std::string &service_uuid,
                      const std::string &characteristic_uuid) {
    if (gatt_map.count(service_uuid) == 0) {
      throw create_flutter_error(UniversalBleErrorCode::kServiceNotFound,
                                 "Service not found");
    }
    if (gatt_map[service_uuid].characteristics.count(characteristic_uuid) ==
        0) {
      throw create_flutter_error(UniversalBleErrorCode::kCharacteristicNotFound,
                                 "Characteristic not found");
    }
    return gatt_map[service_uuid].characteristics.at(characteristic_uuid);
  }
};

class UniversalBlePlugin : public flutter::Plugin,
                           public UniversalBlePlatformChannel,
                           public UniversalBlePeripheralChannel {
public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  UniversalBlePlugin(flutter::PluginRegistrarWindows *registrar);

  ~UniversalBlePlugin();

  // Disallow copy and assign.
  UniversalBlePlugin(const UniversalBlePlugin &) = delete;
  UniversalBlePlugin &operator=(const UniversalBlePlugin &) = delete;

private:
  static void SuccessCallback() {}
  static void ErrorCallback(const FlutterError &error) {
    // Ignore ChannelConnection Error, This might occur because of HotReload
    if (error.code() != "channel-error") {
      std::cout << "ErrorCode: " << error.code()
                << " Message: " << error.message() << std::endl;
    }
  }
  static int64_t GetCurrentTimestampMillis() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
               std::chrono::system_clock::now().time_since_epoch())
        .count();
  }

  flutter::PluginRegistrarWindows *registrar_;
  bool initialized_ = false;

  UniversalBleUiThreadHandler ui_thread_handler_;
  Radio bluetooth_radio_{nullptr};
  RadioState old_radio_state_ = RadioState::Unknown;
  BluetoothLEAdvertisementWatcher bluetooth_le_watcher_{nullptr};
  DeviceWatcher device_watcher_{nullptr};

  std::unordered_map<uint64_t, std::unique_ptr<BluetoothDeviceAgent>>
      connected_devices_{};
  ThreadSafeMap<std::string, DeviceInformation> device_watcher_devices_{};
  ThreadSafeMap<std::string, UniversalBleScanResult> scan_results_{};
  // Maps DeviceInformation.Id() -> MAC address string used as key in
  // device_watcher_devices_
  ThreadSafeMap<std::string, std::string> device_watcher_id_to_mac_{};

  event_token bluetooth_le_watcher_received_token_;
  event_token device_watcher_added_token_;
  event_token device_watcher_updated_token_;
  event_token device_watcher_removed_token_;
  event_token device_watcher_enumeration_completed_token_;
  event_token device_watcher_stopped_token_;
  event_revoker<IRadio> radio_state_changed_revoker_;

  fire_and_forget InitializeAsync();
  fire_and_forget ConnectAsync(uint64_t bluetooth_address);
  fire_and_forget SetNotifiableAsync(
      const std::string &device_id, const std::string &service,
      const std::string &characteristic, int64_t ble_input_property,
      std::function<void(std::optional<FlutterError> reply)> result);
  fire_and_forget PairAsync(const std::string &device_id,
                            std::function<void(ErrorOr<bool> reply)> result);
  fire_and_forget
  CustomPairAsync(const std::string &device_id,
                  std::function<void(ErrorOr<bool> reply)> result);
  static fire_and_forget GetSystemDevicesAsync(
      std::vector<std::string> with_services,
      std::function<void(ErrorOr<flutter::EncodableList> reply)> result);
  static fire_and_forget
  IsPairedAsync(const std::string &device_id,
                std::function<void(ErrorOr<bool> reply)> result);
  fire_and_forget DiscoverServicesAsync(
      const std::string &device_id, bool with_descriptors,
      std::function<void(ErrorOr<flutter::EncodableList> reply)> result);

  void
  PairingRequestedHandler(DeviceInformationCustomPairing sender,
                          const DevicePairingRequestedEventArgs &event_args);

  void RadioStateChanged(const Radio &sender, const IInspectable &);
  void SetupDeviceWatcher();
  void DisposeDeviceWatcher();
  void PushUniversalScanResult(UniversalBleScanResult scan_result,
                               bool is_connectable);
  static std::string ExpandServiceUuid(const std::vector<uint8_t>& uuid_bytes, 
                                        uint8_t uuid_type);
  void BluetoothLeWatcherReceived(
      const BluetoothLEAdvertisementWatcher &sender,
      const BluetoothLEAdvertisementReceivedEventArgs &args);
  void OnDeviceInfoReceived(const DeviceInformation &device_info);
  void BluetoothLeDeviceConnectionStatusChanged(const BluetoothLEDevice &sender,
                                                const IInspectable &args);
  void NotifyConnectionChanged(uint64_t bluetooth_address, bool connected,
                               std::optional<std::string> error = std::nullopt);
  void NotifyConnectionException(uint64_t bluetooth_address,
                                 const std::string &error_message);
  void CleanConnection(uint64_t bluetooth_address);
  void ResetState();
  void
  DisposeServices(const std::unique_ptr<BluetoothDeviceAgent> &device_agent);

  void GattCharacteristicValueChanged(const GattCharacteristic &sender,
                                      const GattValueChangedEventArgs &args);
  // Peripheral runtime state
  std::unordered_map<std::string, std::unique_ptr<PeripheralGattServiceProviderObject>>
      peripheral_service_provider_map_{};
  event_revoker<IRadio> peripheral_radio_state_changed_revoker_;
  std::unique_ptr<UniversalBlePeripheralCallback> peripheral_callback_channel_;
  std::mutex peripheral_mutex_;

  // Peripheral helpers
  fire_and_forget PeripheralAddServiceAsync(const PeripheralService &service);
  fire_and_forget PeripheralReadRequestedAsync(
      GattLocalCharacteristic const &local_char,
      GattReadRequestedEventArgs args);
  fire_and_forget PeripheralWriteRequestedAsync(
      GattLocalCharacteristic const &local_char,
      GattWriteRequestedEventArgs args);
  fire_and_forget PeripheralSubscribedClientsChanged(
      GattLocalCharacteristic const &local_char, IInspectable const &args);
  void PeripheralAdvertisementStatusChanged(
      GattServiceProvider const &sender,
      GattServiceProviderAdvertisementStatusChangedEventArgs const &args);
  void DisposePeripheralServiceProvider(
      PeripheralGattServiceProviderObject *service_provider_object);
  PeripheralGattCharacteristicObject *FindPeripheralGattCharacteristicObject(
      const std::string &characteristic_id,
      bool *ambiguous_match = nullptr);
  bool AreAllPeripheralServicesStarted() const;
  static uint8_t ToGattProtocolError(int64_t status_code);
  static GattCharacteristicProperties ToPeripheralGattCharacteristicProperties(
      int property);
  static PeripheralBlePermission ToPeripheralBlePermission(int permission);
  static std::string PeripheralAdvertisementStatusToString(
      GattServiceProviderAdvertisementStatus status);
  static std::string ParsePeripheralBluetoothClientId(hstring client_id);
  static std::string ParsePeripheralBluetoothError(BluetoothError error);

  // UniversalBlePlatformChannel implementation.
  void GetBluetoothAvailabilityState(
      std::function<void(ErrorOr<int64_t> reply)> result) override;
  void
  EnableBluetooth(std::function<void(ErrorOr<bool> reply)> result) override;
  void
  DisableBluetooth(std::function<void(ErrorOr<bool> reply)> result) override;
  ErrorOr<int64_t> GetConnectionState(const std::string &device_id) override;
  std::optional<FlutterError>
  SetLogLevel(const UniversalBleLogLevel &log_level) override;
  std::optional<FlutterError>
  StartScan(const UniversalScanFilter *filter, const UniversalScanConfig *config) override;
  std::optional<FlutterError> StopScan() override;
  ErrorOr<bool> IsScanning() override;
  std::optional<FlutterError> Connect(const std::string &device_id, const bool *auto_connect) override;
  std::optional<FlutterError> Disconnect(const std::string &device_id) override;
  ErrorOr<bool> HasPermissions(bool with_android_fine_location) override;
  void RequestPermissions(
      bool with_android_fine_location,
      std::function<void(std::optional<FlutterError> reply)> result) override;
  void
  DiscoverServices(const std::string &device_id, bool with_descriptors,
                   std::function<void(ErrorOr<flutter::EncodableList> reply)>
                       result) override;
  void SetNotifiable(
      const std::string &device_id, const std::string &service,
      const std::string &characteristic, int64_t ble_input_property,
      std::function<void(std::optional<FlutterError> reply)> result) override;
  void ReadValue(
      const std::string &device_id, const std::string &service,
      const std::string &characteristic,
      std::function<void(ErrorOr<std::vector<uint8_t>> reply)> result) override;
  void WriteValue(
      const std::string &device_id, const std::string &service,
      const std::string &characteristic, const std::vector<uint8_t> &value,
      int64_t ble_output_property,
      std::function<void(std::optional<FlutterError> reply)> result) override;
  void RequestMtu(const std::string &device_id, int64_t expected_mtu,
                  std::function<void(ErrorOr<int64_t> reply)> result) override;
  void RequestConnectionPriority(
      const std::string &device_id, int64_t priority,
      std::function<void(std::optional<FlutterError> reply)> result) override;
  void ReadRssi(const std::string &device_id,
                std::function<void(ErrorOr<int64_t> reply)> result) override;
  void IsPaired(const std::string &device_id,
                std::function<void(ErrorOr<bool> reply)> result) override;
  void Pair(const std::string &device_id,
            std::function<void(ErrorOr<bool> reply)> result) override;
  std::optional<FlutterError> UnPair(const std::string &device_id) override;
  void
  GetSystemDevices(const flutter::EncodableList &with_services,
                   std::function<void(ErrorOr<flutter::EncodableList> reply)>
                       result) override;

  // UniversalBlePeripheralChannel implementation.
  std::optional<FlutterError> Initialize() override;
  ErrorOr<std::optional<bool>> IsAdvertising() override;
  ErrorOr<bool> IsSupported() override;
  std::optional<FlutterError> StopAdvertising() override;
  std::optional<FlutterError> AddService(const PeripheralService &service) override;
  std::optional<FlutterError> RemoveService(const std::string &service_id) override;
  std::optional<FlutterError> ClearServices() override;
  ErrorOr<flutter::EncodableList> GetServices() override;
  std::optional<FlutterError> StartAdvertising(
      const flutter::EncodableList &services, const std::string *local_name,
      const int64_t *timeout,
      const PeripheralManufacturerData *manufacturer_data,
      bool add_manufacturer_data_in_scan_response) override;
  std::optional<FlutterError> UpdateCharacteristic(
      const std::string &characteristic_id, const std::vector<uint8_t> &value,
      const std::string *device_id) override;
  ErrorOr<flutter::EncodableList> GetSubscribedCentrals(
      const std::string &characteristic_id) override;
};

} // namespace universal_ble

#endif // FLUTTER_PLUGIN_UNIVERSAL_BLE_PLUGIN_H_
