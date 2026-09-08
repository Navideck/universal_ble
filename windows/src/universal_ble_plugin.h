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
#include "async_operation_tracker.h"
#include "helper/universal_ble_base.h"
#include "helper/universal_enum.h"
#include "helper/utils.h"
#include "ui_thread_handler.hpp"
#include "universal_ble_thread_safe.h"
#include <atomic>
#include <memory>
#include <mutex>
#include <utility>
#include <unordered_set>
#include <vector>

namespace universal_ble {
struct GattCharacteristicObject {
  GattCharacteristic obj = nullptr;
  std::optional<event_token> subscription_token;
  bool notification_operation_in_progress = false;
};

struct GattServiceObject {
  GattDeviceService obj = nullptr;
  std::unordered_map<std::string, GattCharacteristicObject> characteristics;
};

struct GattSubscriptionSnapshot {
  uint64_t revision = 0;
  std::vector<std::pair<std::string, std::string>> characteristics;
};

struct GattCharacteristicLease {
  GattCharacteristicObject characteristic;
  AsyncOperationTracker::Lease operation;
};

struct GattMapLease {
  std::unordered_map<std::string, GattServiceObject> map;
  AsyncOperationTracker::Lease operation;
};

struct PeripheralGattCharacteristicObject {
  GattLocalCharacteristic obj = nullptr;
  IVectorView<GattSubscribedClient> stored_clients;
  winrt::event_token value_changed_token;
  winrt::event_token read_requested_token;
  winrt::event_token write_requested_token;
};

struct PeripheralGattServiceProviderObject {
  GattServiceProvider obj = nullptr;
  winrt::event_token advertisement_status_changed_token;
  std::map<std::string, PeripheralGattCharacteristicObject*> characteristics;
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
  event_token gatt_services_changed_token;
  std::unordered_map<std::string, GattServiceObject> gatt_map;
  mutable std::mutex gatt_mutex;
  std::atomic<bool> active{true};
  bool gatt_refresh_in_progress = false;
  bool gatt_refresh_requested = false;
  uint64_t gatt_revision = 0;
  AsyncOperationTracker gatt_operations;

  BluetoothDeviceAgent(
      const BluetoothLEDevice &device,
      const event_token connection_status_changed_token,
      const event_token gatt_services_changed_token,
      std::unordered_map<std::string, GattServiceObject> gatt_map)
      : device(device),
        connection_status_changed_token(connection_status_changed_token),
        gatt_services_changed_token(gatt_services_changed_token),
        gatt_map(std::move(gatt_map)) {}

  ~BluetoothDeviceAgent() { device = nullptr; }

  bool Deactivate() noexcept {
    std::lock_guard<std::mutex> lock(gatt_mutex);
    const bool was_active = active.exchange(false, std::memory_order_acq_rel);
    if (was_active) {
      gatt_operations.Close();
    }
    return was_active;
  }

  bool IsActive() const noexcept {
    return active.load(std::memory_order_acquire);
  }

  GattCharacteristicObject
  FetchCharacteristic(const std::string &service_uuid,
                      const std::string &characteristic_uuid) {
    std::lock_guard<std::mutex> lock(gatt_mutex);
    if (!IsActive()) {
      throw create_flutter_error(UniversalBleErrorCode::kDeviceDisconnected,
                                 "Device disconnected");
    }
    const auto service = gatt_map.find(service_uuid);
    if (service == gatt_map.end()) {
      throw create_flutter_error(UniversalBleErrorCode::kServiceNotFound,
                                 "Service not found");
    }
    const auto characteristic =
        service->second.characteristics.find(characteristic_uuid);
    if (characteristic == service->second.characteristics.end()) {
      throw create_flutter_error(UniversalBleErrorCode::kCharacteristicNotFound,
                                 "Characteristic not found");
    }
    return characteristic->second;
  }

  GattCharacteristicLease FetchCharacteristicForOperation(
      const std::string &service_uuid,
      const std::string &characteristic_uuid) {
    std::lock_guard<std::mutex> lock(gatt_mutex);
    if (!IsActive()) {
      throw create_flutter_error(UniversalBleErrorCode::kDeviceDisconnected,
                                 "Device disconnected");
    }
    const auto service = gatt_map.find(service_uuid);
    if (service == gatt_map.end()) {
      throw create_flutter_error(UniversalBleErrorCode::kServiceNotFound,
                                 "Service not found");
    }
    const auto characteristic =
        service->second.characteristics.find(characteristic_uuid);
    if (characteristic == service->second.characteristics.end()) {
      throw create_flutter_error(UniversalBleErrorCode::kCharacteristicNotFound,
                                 "Characteristic not found");
    }
    const auto operation = gatt_operations.TryAcquire();
    if (!operation.has_value()) {
      throw create_flutter_error(UniversalBleErrorCode::kDeviceDisconnected,
                                 "Device disconnected");
    }
    return {characteristic->second, operation.value()};
  }

  std::vector<GattDeviceService> SnapshotGattServices() const {
    std::lock_guard<std::mutex> lock(gatt_mutex);
    std::vector<GattDeviceService> services;
    services.reserve(gatt_map.size());
    for (const auto &[service_id, service] : gatt_map) {
      (void)service_id;
      services.push_back(service.obj);
    }
    return services;
  }

  GattMapLease SnapshotGattMapForOperation() {
    std::lock_guard<std::mutex> lock(gatt_mutex);
    if (!IsActive()) {
      throw create_flutter_error(UniversalBleErrorCode::kDeviceDisconnected,
                                 "Device disconnected");
    }
    const auto operation = gatt_operations.TryAcquire();
    if (!operation.has_value()) {
      throw create_flutter_error(UniversalBleErrorCode::kDeviceDisconnected,
                                 "Device disconnected");
    }
    return {gatt_map, operation.value()};
  }

  std::unordered_map<std::string, GattServiceObject> TakeGattMap() {
    std::lock_guard<std::mutex> lock(gatt_mutex);
    std::unordered_map<std::string, GattServiceObject> result;
    result.swap(gatt_map);
    ++gatt_revision;
    return result;
  }

  std::optional<GattSubscriptionSnapshot> SnapshotSubscriptions() const {
    std::lock_guard<std::mutex> lock(gatt_mutex);
    if (!IsActive()) {
      return std::nullopt;
    }
    GattSubscriptionSnapshot snapshot;
    snapshot.revision = gatt_revision;
    for (const auto &[service_id, service] : gatt_map) {
      for (const auto &[characteristic_id, characteristic] :
           service.characteristics) {
        if (characteristic.notification_operation_in_progress) {
          return std::nullopt;
        }
        if (characteristic.subscription_token.has_value()) {
          snapshot.characteristics.emplace_back(service_id,
                                                characteristic_id);
        }
      }
    }
    return snapshot;
  }

  bool ReplaceGattMapIfUnchanged(
      std::unordered_map<std::string, GattServiceObject> &replacement,
      const uint64_t expected_revision,
      std::unordered_map<std::string, GattServiceObject> &previous) {
    std::lock_guard<std::mutex> lock(gatt_mutex);
    if (!IsActive() || gatt_revision != expected_revision ||
        !gatt_operations.IsIdle()) {
      return false;
    }
    for (const auto &[service_id, service] : gatt_map) {
      (void)service_id;
      for (const auto &[characteristic_id, characteristic] :
           service.characteristics) {
        (void)characteristic_id;
        if (characteristic.notification_operation_in_progress) {
          return false;
        }
      }
    }
    previous.swap(gatt_map);
    gatt_map.swap(replacement);
    ++gatt_revision;
    return true;
  }

  bool BeginGattRefresh() {
    std::lock_guard<std::mutex> lock(gatt_mutex);
    if (!IsActive()) {
      return false;
    }
    if (gatt_refresh_in_progress) {
      gatt_refresh_requested = true;
      return false;
    }
    gatt_refresh_in_progress = true;
    return true;
  }

  bool FinishGattRefresh() {
    std::lock_guard<std::mutex> lock(gatt_mutex);
    const bool repeat = gatt_refresh_requested;
    gatt_refresh_requested = false;
    gatt_refresh_in_progress = repeat;
    return repeat;
  }

  void RequestGattRefresh() {
    std::lock_guard<std::mutex> lock(gatt_mutex);
    if (IsActive()) {
      gatt_refresh_requested = true;
    }
  }

  bool BeginNotificationOperation(
      const std::string &service_uuid,
      const std::string &characteristic_uuid,
      GattCharacteristicObject &characteristic) {
    std::lock_guard<std::mutex> lock(gatt_mutex);
    if (!IsActive()) {
      return false;
    }
    const auto service = gatt_map.find(service_uuid);
    if (service == gatt_map.end()) {
      return false;
    }
    const auto found =
        service->second.characteristics.find(characteristic_uuid);
    if (found == service->second.characteristics.end() ||
        found->second.notification_operation_in_progress) {
      return false;
    }
    found->second.notification_operation_in_progress = true;
    ++gatt_revision;
    characteristic = found->second;
    return true;
  }

  bool UpdateNotificationOperationToken(
      const std::string &service_uuid,
      const std::string &characteristic_uuid,
      const std::optional<event_token> &subscription_token) {
    std::lock_guard<std::mutex> lock(gatt_mutex);
    if (!IsActive()) {
      return false;
    }
    const auto service = gatt_map.find(service_uuid);
    if (service == gatt_map.end()) {
      return false;
    }
    const auto found =
        service->second.characteristics.find(characteristic_uuid);
    if (found == service->second.characteristics.end() ||
        !found->second.notification_operation_in_progress) {
      return false;
    }
    found->second.subscription_token = subscription_token;
    ++gatt_revision;
    return true;
  }

  bool FinishNotificationOperation(
      const std::string &service_uuid,
      const std::string &characteristic_uuid,
      const std::optional<event_token> &subscription_token) {
    std::lock_guard<std::mutex> lock(gatt_mutex);
    if (!IsActive()) {
      return false;
    }
    const auto service = gatt_map.find(service_uuid);
    if (service == gatt_map.end()) {
      return false;
    }
    const auto found =
        service->second.characteristics.find(characteristic_uuid);
    if (found == service->second.characteristics.end() ||
        !found->second.notification_operation_in_progress) {
      return false;
    }
    found->second.subscription_token = subscription_token;
    found->second.notification_operation_in_progress = false;
    ++gatt_revision;
    return true;
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
  static int64_t GetCurrentTimestampMicros() {
    return std::chrono::duration_cast<std::chrono::microseconds>(
               std::chrono::system_clock::now().time_since_epoch())
        .count();
  }

  flutter::PluginRegistrarWindows *registrar_;
  bool initialized_ = false;

  UniversalBleUiThreadHandler ui_thread_handler_;
  AsyncOperationTracker callback_operations_;
  Radio bluetooth_radio_{nullptr};
  RadioState old_radio_state_ = RadioState::Unknown;
  BluetoothLEAdvertisementWatcher bluetooth_le_watcher_{nullptr};
  DeviceWatcher device_watcher_{nullptr};

  std::unordered_map<uint64_t, std::shared_ptr<BluetoothDeviceAgent>>
      connected_devices_{};
  std::unordered_map<uint64_t, uint64_t> connect_generations_{};
  std::unordered_set<uint64_t> pending_connects_{};
  uint64_t next_connect_generation_ = 0;
  std::mutex connected_devices_mutex_;
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
  fire_and_forget ConnectAsync(uint64_t bluetooth_address,
                               uint64_t connect_generation);
  fire_and_forget RefreshGattServicesAsync(
      uint64_t bluetooth_address,
      std::shared_ptr<BluetoothDeviceAgent> device_agent);
  fire_and_forget SetNotifiableAsync(
      std::string device_id, std::string service,
      std::string characteristic,
      BleInputProperty ble_input_property,
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
  void BluetoothLeDeviceGattServicesChanged(const BluetoothLEDevice &sender,
                                             const IInspectable &args);
  std::shared_ptr<BluetoothDeviceAgent>
  GetConnectedDevice(uint64_t bluetooth_address);
  void InvalidateConnectAttempt(uint64_t bluetooth_address);
  std::shared_ptr<BluetoothDeviceAgent>
  RemoveConnectedDevice(uint64_t bluetooth_address,
                        const BluetoothLEDevice *expected_device = nullptr,
                        uint64_t *removed_generation = nullptr);
  bool InstallConnectedDevice(
      uint64_t bluetooth_address, uint64_t connect_generation,
      std::shared_ptr<BluetoothDeviceAgent> device_agent,
      std::shared_ptr<BluetoothDeviceAgent> &previous_device_agent);
  bool NotifyConnectedIfCurrent(
      uint64_t bluetooth_address, uint64_t connect_generation,
      const BluetoothLEDevice &expected_device);
  void NotifyConnectFailureIfCurrent(
      uint64_t bluetooth_address, uint64_t connect_generation,
      const std::string &error_message) noexcept;
  void NotifyConnectionChanged(uint64_t bluetooth_address, bool connected,
                               std::optional<std::string> error = std::nullopt,
                               std::optional<uint64_t> expected_generation =
                                   std::nullopt);
  void NotifyConnectionException(uint64_t bluetooth_address,
                                 const std::string &error_message,
                                 const BluetoothLEDevice *expected_device =
                                     nullptr);
  bool CleanConnection(uint64_t bluetooth_address,
                       const BluetoothLEDevice *expected_device = nullptr,
                       uint64_t *removed_generation = nullptr);
  void DisposeConnection(
      const std::shared_ptr<BluetoothDeviceAgent> &device_agent);
  void ResetState();
  void DisposeServices(
      const std::shared_ptr<BluetoothDeviceAgent> &device_agent);
  void DisposeGattMap(
      std::unordered_map<std::string, GattServiceObject> gatt_map,
      const std::vector<GattDeviceService> *retained_services = nullptr);

  event_token RegisterGattValueChangedHandler(
      const std::shared_ptr<BluetoothDeviceAgent> &device_agent,
      const std::string &device_id, const std::string &characteristic_id,
      const GattCharacteristic &characteristic);
  void GattCharacteristicValueChanged(
      const std::weak_ptr<BluetoothDeviceAgent> &device_agent,
      const std::string &device_id, const std::string &characteristic_id,
      const GattValueChangedEventArgs &args);
  // Peripheral runtime state
  std::map<std::string, PeripheralGattServiceProviderObject *> peripheral_service_provider_map_{};
  /// Lowercased service UUIDs from the last successful `StartAdvertising` call.
  /// Empty means all registered services were selected.
  std::vector<std::string> peripheral_advertising_targets_lc_{};
  BluetoothLEAdvertisementPublisher advertisement_publisher_{nullptr};
  event_token advertisement_publisher_status_token_{};
  event_revoker<IRadio> peripheral_radio_state_changed_revoker_;
  std::mutex peripheral_mutex_;

  // Peripheral helpers
  void DisposeAdvertisementPublisher();  // Requires peripheral_mutex_.
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
  bool ArePeripheralAdvertisingTargetsStarted() const;
  static uint8_t ToGattProtocolError(int64_t status_code);
  static GattCharacteristicProperties ToPeripheralGattCharacteristicProperties(
      CharacteristicProperty property);
  static std::string PeripheralAdvertisementStatusToString(
      GattServiceProviderAdvertisementStatus status);
  static std::string ParsePeripheralBluetoothClientId(hstring client_id);
  static std::string ParsePeripheralBluetoothError(BluetoothError error);

  // UniversalBlePlatformChannel implementation.
  void GetBluetoothAvailabilityState(
      std::function<void(ErrorOr<AvailabilityState> reply)> result) override;
  void
  EnableBluetooth(std::function<void(ErrorOr<bool> reply)> result) override;
  void
  DisableBluetooth(std::function<void(ErrorOr<bool> reply)> result) override;
  ErrorOr<BleConnectionState> GetConnectionState(
      const std::string &device_id) override;
  std::optional<FlutterError>
  SetLogLevel(const BleLogLevel &log_level) override;
  std::optional<FlutterError>
  StartScan(const UniversalScanFilter *filter, const UniversalScanConfig *config) override;
  std::optional<FlutterError> StopScan() override;
  ErrorOr<bool> IsScanning() override;
  std::optional<FlutterError> Connect(const std::string &device_id, const bool *auto_connect,
                                      const ConnectionPlatformConfig *platform_config) override;
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
      const std::string &characteristic,
      const BleInputProperty &ble_input_property,
      std::function<void(std::optional<FlutterError> reply)> result) override;
  void ReadValue(
      const std::string &device_id, const std::string &service,
      const std::string &characteristic,
      std::function<void(ErrorOr<std::vector<uint8_t>> reply)> result) override;
  void ReadDescriptorValue(
      const std::string &device_id, const std::string &service,
      const std::string &characteristic, const std::string &descriptor,
      std::function<void(ErrorOr<std::vector<uint8_t>> reply)> result) override;
  void WriteValue(
      const std::string &device_id, const std::string &service,
      const std::string &characteristic, const std::vector<uint8_t> &value,
      const BleOutputProperty &ble_output_property,
      std::function<void(std::optional<FlutterError> reply)> result) override;
  void WriteDescriptorValue(
      const std::string &device_id, const std::string &service,
      const std::string &characteristic, const std::string &descriptor,
      const std::vector<uint8_t> &value,
      std::function<void(std::optional<FlutterError> reply)> result) override;
  void RequestMtu(const std::string &device_id, int64_t expected_mtu,
                  std::function<void(ErrorOr<int64_t> reply)> result) override;
  void RequestConnectionPriority(
      const std::string &device_id, const BleConnectionPriority &priority,
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
  ErrorOr<PeripheralAdvertisingState> GetAdvertisingState() override;
  ErrorOr<PeripheralReadinessState> GetReadinessState() override;
  std::optional<FlutterError> StopAdvertising() override;
  std::optional<FlutterError> AddService(const PeripheralService &service) override;
  std::optional<FlutterError> RemoveService(const std::string &service_id) override;
  std::optional<FlutterError> ClearServices() override;
  ErrorOr<flutter::EncodableList> GetServices() override;
  std::optional<FlutterError> StartAdvertising(
      const flutter::EncodableList &services, const std::string *local_name,
      const int64_t *timeout,
      const UniversalManufacturerData *manufacturer_data,
      const PeripheralPlatformConfig *platform_config) override;
  std::optional<FlutterError> UpdateCharacteristic(
      const std::string &characteristic_id, const std::vector<uint8_t> &value,
      const std::string *device_id) override;
  ErrorOr<flutter::EncodableList> GetSubscribedClients(
      const std::string &characteristic_id) override;
  ErrorOr<std::optional<int64_t>> GetMaximumNotifyLength(
      const std::string &device_id) override;
};

} // namespace universal_ble

#endif // FLUTTER_PLUGIN_UNIVERSAL_BLE_PLUGIN_H_
