// ReSharper disable CppTooWideScopeInitStatement
// ReSharper disable CppTooWideScope
#include "universal_ble_plugin.h"
#include <windows.h>

#include <flutter/plugin_registrar_windows.h>

#include <algorithm>
#include <iomanip>
#include <memory>
#include <regex>
#include <sstream>
#include <thread>

#include "enum_parser.h"
#include "generated/universal_ble.g.h"
#include "helper/universal_ble_logger.h"
#include "helper/universal_enum.h"
#include "helper/utils.h"
#include "pin_entry.h"
#include "universal_ble_filter_util.h"

namespace universal_ble {
using universal_ble::ErrorOr;
using universal_ble::UniversalBleCallbackChannel;
using universal_ble::UniversalBlePlatformChannel;
using universal_ble::UniversalBleScanResult;

const auto is_connectable_key =
    L"System.Devices.Aep.Bluetooth.Le.IsConnectable";
const auto is_connected_key = L"System.Devices.Aep.IsConnected";
const auto is_paired_key = L"System.Devices.Aep.IsPaired";
const auto is_present_key = L"System.Devices.Aep.IsPresent";
const auto device_address_key = L"System.Devices.Aep.DeviceAddress";
const auto signal_strength_key = L"System.Devices.Aep.SignalStrength";
static std::unique_ptr<UniversalBleCallbackChannel> callback_channel;

void UniversalBlePlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto plugin = std::make_unique<UniversalBlePlugin>(registrar);
  SetUp(registrar->messenger(), plugin.get());
  callback_channel =
      std::make_unique<UniversalBleCallbackChannel>(registrar->messenger());
  registrar->AddPlugin(std::move(plugin));
}

UniversalBlePlugin::UniversalBlePlugin(
    flutter::PluginRegistrarWindows *registrar)
    : ui_thread_handler_(registrar) {
  InitializeAsync();
}

UniversalBlePlugin::~UniversalBlePlugin() = default;

// UniversalBlePlatformChannel implementation.
void UniversalBlePlugin::GetBluetoothAvailabilityState(
    std::function<void(ErrorOr<int64_t> reply)> result) {
  if (!bluetooth_radio_) {
    if (!initialized_) {
      result(static_cast<int>(AvailabilityState::unknown));
    } else {
      result(static_cast<int>(AvailabilityState::unsupported));
    }
  } else {
    result(static_cast<int>(
        get_availability_state_from_radio(bluetooth_radio_.State())));
  }
};

void UniversalBlePlugin::EnableBluetooth(
    std::function<void(ErrorOr<bool> reply)> result) {
  if (!bluetooth_radio_) {
    result(create_flutter_error(UniversalBleErrorCode::kBluetoothNotAvailable,
                                "Bluetooth is not available"));
    return;
  }

  if (bluetooth_radio_.State() == RadioState::On) {
    result(true);
    return;
  }

  bluetooth_radio_.SetStateAsync(RadioState::On)
      .Completed([&, result](const IAsyncOperation<RadioAccessStatus> &sender,
                             const AsyncStatus args) {
        if (const auto radio_access_status = sender.GetResults();
            radio_access_status == RadioAccessStatus::Allowed) {
          result(true);
        } else {
          result(create_flutter_error(UniversalBleErrorCode::kFailed,
                                      "Failed to enable bluetooth"));
        }
      });
}

void UniversalBlePlugin::DisableBluetooth(
    std::function<void(ErrorOr<bool> reply)> result) {
  if (!bluetooth_radio_) {
    result(create_flutter_error(UniversalBleErrorCode::kBluetoothNotAvailable,
                                "Bluetooth is not available"));
    return;
  }

  if (bluetooth_radio_.State() == RadioState::Off) {
    result(true);
    return;
  }

  bluetooth_radio_.SetStateAsync(RadioState::Off)
      .Completed([&, result](IAsyncOperation<RadioAccessStatus> const &sender,
                             AsyncStatus const args) {
        if (const auto radio_access_status = sender.GetResults();
            radio_access_status == RadioAccessStatus::Allowed) {
          result(true);
        } else {
          result(create_flutter_error(UniversalBleErrorCode::kFailed,
                                      "Failed to disable bluetooth"));
        }
      });
}

ErrorOr<bool>
UniversalBlePlugin::HasPermissions(bool with_android_fine_location) {
  // Windows does not require runtime permissions for Bluetooth
  return true;
}

void UniversalBlePlugin::RequestPermissions(
    bool with_android_fine_location,
    std::function<void(std::optional<FlutterError> reply)> result) {
  // Windows does not require runtime permissions for Bluetooth
  result(std::nullopt);
  return;
}

std::optional<FlutterError>
UniversalBlePlugin::StartScan(const UniversalScanFilter *filter, const UniversalScanConfig *config) {

  if (!bluetooth_radio_ || bluetooth_radio_.State() != RadioState::On) {
    return create_flutter_error(UniversalBleErrorCode::kBluetoothNotAvailable,
                                "Bluetooth is not available");
  }

  try {
    SetupDeviceWatcher();
    scan_results_.clear();
    const DeviceWatcherStatus device_watcher_status = device_watcher_.Status();
    // std::cout << "DeviceWatcherState: " <<
    // DeviceWatcherStatusToString(deviceWatcherStatus) << std::endl;
    // DeviceWatcher can only start if its in Created, Stopped, or Aborted state
    if (device_watcher_status == DeviceWatcherStatus::Created ||
        device_watcher_status == DeviceWatcherStatus::Stopped ||
        device_watcher_status == DeviceWatcherStatus::Aborted) {
      device_watcher_.Start();
    } else if (device_watcher_status == DeviceWatcherStatus::Stopping) {
      return create_flutter_error(
          UniversalBleErrorCode::kStoppingScanInProgress,
          "StoppingScan in progress");
    }

    // Setup LeWatcher and apply filters
    if (!bluetooth_le_watcher_) {
      bluetooth_le_watcher_ = BluetoothLEAdvertisementWatcher();
      bluetooth_le_watcher_.ScanningMode(BluetoothLEScanningMode::Active);
      resetScanFilter();

      if (filter != nullptr) {
        UniversalBleLogger::LogInfo("Using Custom Scan Filter");
        setScanFilter(*filter);
      }

      bluetooth_le_watcher_received_token_ = bluetooth_le_watcher_.Received(
          {this, &UniversalBlePlugin::BluetoothLeWatcherReceived});
    }
    bluetooth_le_watcher_.Start();
    return std::nullopt;
  } catch (...) {
    UniversalBleLogger::LogError("Unknown error StartScan");
    return create_flutter_error(UniversalBleErrorCode::kUnknownError,
                                "Unknown error");
  }
};

std::optional<FlutterError> UniversalBlePlugin::StopScan() {
  if (bluetooth_radio_ && bluetooth_radio_.State() == RadioState::On) {
    try {
      if (bluetooth_le_watcher_) {
        bluetooth_le_watcher_.Received(bluetooth_le_watcher_received_token_);
        bluetooth_le_watcher_.Stop();
      }
      bluetooth_le_watcher_ = nullptr;
      DisposeDeviceWatcher();
      scan_results_.clear();
      return std::nullopt;
    } catch (const hresult_error &err) {
      const int error_code = err.code();
      UniversalBleLogger::LogError("StopScanLog: " + to_string(err.message()) +
                                   " ErrorCode: " + std::to_string(error_code));
      return create_flutter_error(UniversalBleErrorCode::kFailed,
                                  to_string(err.message()),
                                  std::to_string(error_code));
    } catch (...) {
      return create_flutter_error(UniversalBleErrorCode::kFailed,
                                  "Failed to Stop");
    }
  } else {
    return create_flutter_error(UniversalBleErrorCode::kBluetoothNotAvailable,
                                "Bluetooth is not available");
  }
};

ErrorOr<bool> UniversalBlePlugin::IsScanning() {
  if (bluetooth_le_watcher_ != nullptr) {
    try {
      return bluetooth_le_watcher_.Status() ==
             BluetoothLEAdvertisementWatcherStatus::Started;
    } catch (...) {
    }
  }
  return false;
}

ErrorOr<int64_t>
UniversalBlePlugin::GetConnectionState(const std::string &device_id) {
  const auto it = connected_devices_.find(str_to_mac_address(device_id));
  if (it == connected_devices_.end()) {
    return static_cast<int>(ConnectionState::disconnected);
  }

  const auto device_agent = *it->second;

  if (device_agent.device.ConnectionStatus() ==
      BluetoothConnectionStatus::Connected) {
    return static_cast<int>(ConnectionState::connected);
  } else {
    return static_cast<int>(ConnectionState::disconnected);
  }
}

std::optional<FlutterError>
UniversalBlePlugin::SetLogLevel(const UniversalBleLogLevel &log_level) {
  UniversalBleLogger::SetLogLevel(log_level);
  return std::nullopt;
}

std::optional<FlutterError>
UniversalBlePlugin::Connect(const std::string &device_id,
                            const bool *auto_connect) {
  // Note: autoConnect is not directly supported on Windows platform
  ConnectAsync(str_to_mac_address(device_id));
  return std::nullopt;
};

std::optional<FlutterError>
UniversalBlePlugin::Disconnect(const std::string &device_id) {
  auto device_address = str_to_mac_address(device_id);
  const auto it = connected_devices_.find(device_address);
  if (it != connected_devices_.end()) {
    it->second->device.Close();
    DisposeServices(it->second);
  } else {
    ui_thread_handler_.Post([device_id] {
      callback_channel->OnConnectionChanged(device_id, false, nullptr,
                                            SuccessCallback, ErrorCallback);
    });
  }
  return std::nullopt;
}

void UniversalBlePlugin::DiscoverServices(
    const std::string &device_id, bool with_descriptors,
    std::function<void(ErrorOr<flutter::EncodableList> reply)> result) {
  DiscoverServicesAsync(device_id, with_descriptors, result);
}

void UniversalBlePlugin::SetNotifiable(
    const std::string &device_id, const std::string &service,
    const std::string &characteristic, int64_t ble_input_property,
    std::function<void(std::optional<FlutterError> reply)> result) {
  SetNotifiableAsync(device_id, service, characteristic, ble_input_property,
                     result);
};

void UniversalBlePlugin::ReadValue(
    const std::string &device_id, const std::string &service,
    const std::string &characteristic,
    std::function<void(ErrorOr<std::vector<uint8_t>> reply)> result) {
  UniversalBleLogger::LogDebugWithTimestamp("READ -> " + device_id + " " +
                                            service + " " + characteristic);
  try {
    const auto it = connected_devices_.find(str_to_mac_address(device_id));
    if (it == connected_devices_.end()) {
      result(create_flutter_error(UniversalBleErrorCode::kDeviceNotFound,
                                  "Unknown devicesId:" + device_id));
      return;
    }

    auto bluetooth_agent = *it->second;
    const GattCharacteristicObject &gatt_characteristic_holder =
        bluetooth_agent.FetchCharacteristic(service, characteristic);
    const GattCharacteristic gatt_characteristic =
        gatt_characteristic_holder.obj;

    const auto properties = gatt_characteristic.CharacteristicProperties();
    if ((properties & GattCharacteristicProperties::Read) ==
        GattCharacteristicProperties::None) {
      result(create_flutter_error(
          UniversalBleErrorCode::kCharacteristicDoesNotSupportRead,
          "Characteristic does not support read"));
      return;
    }

    gatt_characteristic.ReadValueAsync(BluetoothCacheMode::Uncached)
        .Completed([&, result](IAsyncOperation<GattReadResult> const &sender,
                               AsyncStatus const args) {
          const auto read_value_result = sender.GetResults();
          const auto status = read_value_result.Status();
          if (status != GattCommunicationStatus::Success) {
            UniversalBleLogger::LogError(
                "READ_FAILED <- " + device_id + " " + service + " " +
                characteristic +
                " status=" + std::to_string(static_cast<int>(status)));
            result(create_flutter_error_from_gatt_communication_status(status));
          } else {
            result(to_bytevc(read_value_result.Value()));
          }
        });
  } catch (const FlutterError &err) {
    return result(err);
  } catch (...) {
    UniversalBleLogger::LogError("ReadValueLog: Unknown error");
    return result(create_flutter_unknown_error());
  }
}

void UniversalBlePlugin::WriteValue(
    const std::string &device_id, const std::string &service,
    const std::string &characteristic, const std::vector<uint8_t> &value,
    int64_t ble_output_property,
    std::function<void(std::optional<FlutterError> reply)> result) {
  UniversalBleLogger::LogDebugWithTimestamp(
      "WRITE -> " + device_id + " " + service + " " + characteristic +
      " len=" + std::to_string(value.size()) +
      " property=" + std::to_string(ble_output_property));
  try {
    const auto it = connected_devices_.find(str_to_mac_address(device_id));
    if (it == connected_devices_.end()) {
      result(create_flutter_error(UniversalBleErrorCode::kDeviceNotFound,
                                  "Unknown devicesId:" + device_id));
      return;
    }
    auto bluetooth_agent = *it->second;
    const GattCharacteristicObject &gatt_characteristic_holder =
        bluetooth_agent.FetchCharacteristic(service, characteristic);
    const GattCharacteristic gatt_characteristic =
        gatt_characteristic_holder.obj;
    const auto properties = gatt_characteristic.CharacteristicProperties();

    auto write_option = GattWriteOption::WriteWithResponse;
    if (ble_output_property ==
        static_cast<int>(BleOutputProperty::withoutResponse)) {
      write_option = GattWriteOption::WriteWithoutResponse;
      if ((properties & GattCharacteristicProperties::WriteWithoutResponse) ==
          GattCharacteristicProperties::None) {
        result(create_flutter_error(
            UniversalBleErrorCode::
                kCharacteristicDoesNotSupportWriteWithoutResponse,
            "Characteristic does not support WriteWithoutResponse"));
        return;
      }
    } else {
      if ((properties & GattCharacteristicProperties::Write) ==
          GattCharacteristicProperties::None) {
        result(create_flutter_error(
            UniversalBleErrorCode::kCharacteristicDoesNotSupportWrite,
            "Characteristic does not support Write"));
        return;
      }
    }

    gatt_characteristic.WriteValueAsync(from_bytevc(value), write_option)
        .Completed([&, result](
                       IAsyncOperation<GattCommunicationStatus> const &sender,
                       AsyncStatus const args) {
          if (args == AsyncStatus::Error) {
            result(create_flutter_error(UniversalBleErrorCode::kFailed,
                                        "Encountered an error."));
            return;
          }

          const auto status = sender.GetResults();
          if (status != GattCommunicationStatus::Success) {
            UniversalBleLogger::LogError(
                "WRITE_FAILED <- " + device_id + " " + service + " " +
                characteristic +
                " status=" + std::to_string(static_cast<int>(status)));
            result(create_flutter_error_from_gatt_communication_status(status));
          } else {
            result(std::nullopt);
          }
        });
  } catch (const FlutterError &err) {
    result(err);
  } catch (...) {
    UniversalBleLogger::LogError("WriteValue: Unknown error");
    result(create_flutter_unknown_error());
  }
}

void UniversalBlePlugin::RequestMtu(
    const std::string &device_id, int64_t expected_mtu,
    std::function<void(ErrorOr<int64_t> reply)> result) {
  UniversalBleLogger::LogDebugWithTimestamp(
      "REQUEST_MTU -> " + device_id +
      " expected=" + std::to_string(expected_mtu));
  try {
    const auto it = connected_devices_.find(str_to_mac_address(device_id));
    if (it == connected_devices_.end()) {
      result(create_flutter_error(UniversalBleErrorCode::kDeviceNotFound,
                                  "Unknown devicesId:" + device_id));
      return;
    }
    const auto bluetooth_agent = *it->second;
    GattSession::FromDeviceIdAsync(bluetooth_agent.device.BluetoothDeviceId())
        .Completed([&, result](IAsyncOperation<GattSession> const &sender,
                               AsyncStatus const args) {
          if (args == AsyncStatus::Error) {
            result(create_flutter_unknown_error());
            return;
          }

          result((int64_t)sender.GetResults().MaxPduSize());
        });
  } catch (const FlutterError &err) {
    result(err);
  }
}

void UniversalBlePlugin::ReadRssi(
    const std::string &device_id,
    std::function<void(ErrorOr<int64_t> reply)> result) {
  result(
      create_flutter_error(UniversalBleErrorCode::kNotImplemented,
                           "readRssi is not implemented on Windows platform"));
}

void UniversalBlePlugin::IsPaired(
    const std::string &device_id,
    std::function<void(ErrorOr<bool> reply)> result) {
  IsPairedAsync(device_id, result);
}

void UniversalBlePlugin::Pair(const std::string &device_id,
                              std::function<void(ErrorOr<bool> reply)> result) {
  try {
    if (is_windows11_or_greater()) {
      PairAsync(device_id, result);
    } else {
      CustomPairAsync(device_id, result);
    }
  } catch (const FlutterError &err) {
    result(err);
  }
}

std::optional<FlutterError>
UniversalBlePlugin::UnPair(const std::string &device_id) {
  try {
    const auto device = async_get(BluetoothLEDevice::FromBluetoothAddressAsync(
        str_to_mac_address(device_id)));
    if (device == nullptr) {
      return create_flutter_error(UniversalBleErrorCode::kDeviceNotFound,
                                  "Unknown devicesId:" + device_id);
    }
    const auto device_information = device.DeviceInformation();

    if (!device_information.Pairing().IsPaired()) {
      return create_flutter_error(UniversalBleErrorCode::kNotPaired,
                                  "Device is not paired");
    }

    const auto device_unpairing_result =
        async_get(device_information.Pairing().UnpairAsync());

    const auto status = device_unpairing_result.Status();
    if (status != DeviceUnpairingResultStatus::Unpaired) {
      return create_flutter_error_from_unpairing_status(status);
    }
    return std::nullopt;
  } catch (const FlutterError &err) {
    return err;
  }
}

void UniversalBlePlugin::GetSystemDevices(
    const flutter::EncodableList &with_services,
    std::function<void(ErrorOr<flutter::EncodableList> reply)> result) {
  auto with_services_str = std::vector<std::string>();
  for (const auto &item : with_services) {
    auto service_id = std::get<std::string>(item);
    with_services_str.push_back(service_id);
  }
  GetSystemDevicesAsync(with_services_str, result);
}

/// Helper Methods

fire_and_forget UniversalBlePlugin::InitializeAsync() {
  const auto radios = co_await Radio::GetRadiosAsync();
  for (auto &&radio : radios) {
    if (radio.Kind() == RadioKind::Bluetooth) {
      bluetooth_radio_ = radio;
      radio_state_changed_revoker_ = bluetooth_radio_.StateChanged(
          auto_revoke, {this, &UniversalBlePlugin::RadioStateChanged});
      RadioStateChanged(bluetooth_radio_, nullptr);
      break;
    }
  }
  if (!bluetooth_radio_) {
    UniversalBleLogger::LogError("Bluetooth is not available");
    ui_thread_handler_.Post([] {
      callback_channel->OnAvailabilityChanged(
          static_cast<int>(AvailabilityState::unsupported), SuccessCallback,
          ErrorCallback);
    });
  }
  initialized_ = true;
}

fire_and_forget UniversalBlePlugin::PairAsync(
    const std::string &device_id,
    const std::function<void(ErrorOr<bool> reply)> result) {
  try {
    UniversalBleLogger::LogInfo("Trying to pair");

    const auto device = co_await BluetoothLEDevice::FromBluetoothAddressAsync(
        str_to_mac_address(device_id));
    if (device == nullptr) {
      result(create_flutter_error(UniversalBleErrorCode::kDeviceNotFound,
                                  "Unknown devicesId:" + device_id));
      co_return;
    }

    UniversalBleLogger::LogInfo("Got device");

    const auto device_information = device.DeviceInformation();
    if (device_information.Pairing().IsPaired())
      result(true);
    else if (!device_information.Pairing().CanPair())
      result(create_flutter_error(UniversalBleErrorCode::kNotPairable,
                                  "Device is not pairable"));
    else {
      const auto pair_result =
          co_await device_information.Pairing().PairAsync();
      UniversalBleLogger::LogInfo("PairLog: Received pairing status");
      bool is_paired =
          pair_result.Status() == DevicePairingResultStatus::Paired;
      result(is_paired);

      const auto error_str =
          device_pairing_result_to_string(pair_result.Status());
      std::optional<std::string> captured_error;
      if (error_str.has_value()) {
        captured_error = error_str.value();
      }
      ui_thread_handler_.Post([device_id, is_paired, captured_error] {
        const std::string *error_msg = nullptr;
        std::string error_string;
        if (captured_error.has_value()) {
          error_string = captured_error.value();
          error_msg = &error_string;
        }
        callback_channel->OnPairStateChange(device_id, is_paired, error_msg,
                                            SuccessCallback, ErrorCallback);
      });
    }
  } catch (...) {
    result(false);
    UniversalBleLogger::LogError("PairLog: Unknown error");
  }
}

fire_and_forget UniversalBlePlugin::CustomPairAsync(
    const std::string &device_id,
    const std::function<void(ErrorOr<bool> reply)> result) {
  try {
    const auto device = co_await BluetoothLEDevice::FromBluetoothAddressAsync(
        str_to_mac_address(device_id));
    if (device == nullptr) {
      result(create_flutter_error(UniversalBleErrorCode::kDeviceNotFound,
                                  "Unknown devicesId:" + device_id));
      co_return;
    }
    const auto device_information = device.DeviceInformation();
    if (device_information.Pairing().IsPaired())
      result(true);
    else if (!device_information.Pairing().CanPair())
      result(create_flutter_error(UniversalBleErrorCode::kNotPairable,
                                  "Device is not pairable"));
    else {
      const auto custom_pairing = device_information.Pairing().Custom();
      const event_token token = custom_pairing.PairingRequested(
          {this, &UniversalBlePlugin::PairingRequestedHandler});
      UniversalBleLogger::LogInfo("PairLog: Trying to pair");
      const DevicePairingProtectionLevel protection_level =
          device_information.Pairing().ProtectionLevel();
      // DevicePairingKinds => None, ConfirmOnly, DisplayPin, ProvidePin,
      // ConfirmPinMatch, ProvidePasswordCredential
      const auto pair_result = co_await custom_pairing.PairAsync(
          DevicePairingKinds::ConfirmOnly | DevicePairingKinds::ProvidePin,
          protection_level);
      UniversalBleLogger::LogInfo("PairLog: Got Pair Result");
      const DevicePairingResultStatus status = pair_result.Status();
      custom_pairing.PairingRequested(token);
      bool is_paired = status == DevicePairingResultStatus::Paired;
      result(is_paired);

      const auto error_str = device_pairing_result_to_string(status);
      std::optional<std::string> captured_error;
      if (error_str.has_value()) {
        captured_error = error_str.value();
      }
      ui_thread_handler_.Post([device_id, is_paired, captured_error] {
        const std::string *error_msg = nullptr;
        std::string error_string;
        if (captured_error.has_value()) {
          error_string = captured_error.value();
          error_msg = &error_string;
        }
        callback_channel->OnPairStateChange(device_id, is_paired, error_msg,
                                            SuccessCallback, ErrorCallback);
      });
    }
  } catch (...) {
    result(false);
    UniversalBleLogger::LogError("PairLog Error: Pairing Failed");
  }
}

// ReSharper disable once CppMemberFunctionMayBeStatic
void UniversalBlePlugin::PairingRequestedHandler(
    DeviceInformationCustomPairing sender,
    const DevicePairingRequestedEventArgs &event_args) {
  UniversalBleLogger::LogInfo("PairLog: Got PairingRequest");
  const DevicePairingKinds kind = event_args.PairingKind();
  if (kind != DevicePairingKinds::ProvidePin) {
    event_args.Accept();
    return;
  }

  UniversalBleLogger::LogInfo("PairLog: Trying to get pin from user");
  const hstring pin = askForPairingPin();
  UniversalBleLogger::LogInfo("PairLog: Got Pin: " + to_string(pin));
  event_args.Accept(pin);
}

std::string
UniversalBlePlugin::ExpandServiceUuid(const std::vector<uint8_t> &uuid_bytes,
                                      uint8_t uuid_type) {
  if (uuid_type ==
      static_cast<uint8_t>(AdvertisementSectionType::ServiceData16BitUuids)) {
    // 16-bit UUID: expand to full 128-bit format
    if (uuid_bytes.size() >= 2) {
      uint16_t uuid_16 = (uuid_bytes[1] << 8) | uuid_bytes[0];
      char uuid_str[37];
      sprintf_s(uuid_str, "0000%04x-0000-1000-8000-00805f9b34fb", uuid_16);
      return std::string(uuid_str);
    }
  } else if (uuid_type ==
             static_cast<uint8_t>(
                 AdvertisementSectionType::ServiceData32BitUuids)) {
    // 32-bit UUID: expand to full 128-bit format
    if (uuid_bytes.size() >= 4) {
      uint32_t uuid_32 = (uuid_bytes[3] << 24) | (uuid_bytes[2] << 16) |
                         (uuid_bytes[1] << 8) | uuid_bytes[0];
      char uuid_str[37];
      sprintf_s(uuid_str, "%08x-0000-1000-8000-00805f9b34fb", uuid_32);
      return std::string(uuid_str);
    }
  } else if (uuid_type ==
             static_cast<uint8_t>(
                 AdvertisementSectionType::ServiceData128BitUuids)) {
    // 128-bit UUID: parse with proper endianness handling
    // BLE service data stores UUIDs in little-endian byte order
    // guid_to_uuid reads: Data1/Data2/Data3 as big-endian (reverse), Data4 as
    // little-endian (forward)
    if (uuid_bytes.size() >= 16) {
      guid uuid_guid{};

      // Data1: bytes [0-3] - guid_to_uuid reads in reverse (big-endian), so
      // store in reverse
      uuid_guid.Data1 = static_cast<uint32_t>(uuid_bytes[3]) |
                        (static_cast<uint32_t>(uuid_bytes[2]) << 8) |
                        (static_cast<uint32_t>(uuid_bytes[1]) << 16) |
                        (static_cast<uint32_t>(uuid_bytes[0]) << 24);

      // Data2: bytes [4-5] - guid_to_uuid reads in reverse (big-endian), so
      // store in reverse
      uuid_guid.Data2 = static_cast<uint16_t>(uuid_bytes[5]) |
                        (static_cast<uint16_t>(uuid_bytes[4]) << 8);

      // Data3: bytes [6-7] - guid_to_uuid reads in reverse (big-endian), so
      // store in reverse
      uuid_guid.Data3 = static_cast<uint16_t>(uuid_bytes[7]) |
                        (static_cast<uint16_t>(uuid_bytes[6]) << 8);

      // Data4: bytes [8-15] - guid_to_uuid reads in order (little-endian), so
      // store in order
      for (size_t i = 0; i < 8; i++) {
        uuid_guid.Data4[i] = uuid_bytes[8 + i];
      }

      return guid_to_uuid(uuid_guid);
    }
  }
  return std::string();
}

// Send device to callback channel
// if device is already discovered in deviceWatcher then merge the scan result
void UniversalBlePlugin::PushUniversalScanResult(
    UniversalBleScanResult scan_result, const bool is_connectable) {
  const std::optional<UniversalBleScanResult> it =
      scan_results_.get(scan_result.device_id());
  if (it.has_value()) {
    const UniversalBleScanResult &current_scan_result = it.value();
    bool should_update = false;

    // Check if current scanResult name is longer than the received scanResult
    // name
    if (scan_result.name() != nullptr && !scan_result.name()->empty() &&
        current_scan_result.name() != nullptr &&
        !current_scan_result.name()->empty()) {
      if (current_scan_result.name()->size() > scan_result.name()->size()) {
        scan_result.set_name(*current_scan_result.name());
      }
    }

    if ((scan_result.name() == nullptr || scan_result.name()->empty()) &&
        (current_scan_result.name() != nullptr &&
         !current_scan_result.name()->empty())) {
      scan_result.set_name(*current_scan_result.name());
      should_update = true;
    }

    if (scan_result.is_paired() == nullptr &&
        current_scan_result.is_paired() != nullptr) {
      scan_result.set_is_paired(current_scan_result.is_paired());
      should_update = true;
    }

    if ((scan_result.manufacturer_data_list() == nullptr ||
         scan_result.manufacturer_data_list()->empty()) &&
        current_scan_result.manufacturer_data_list() != nullptr) {
      scan_result.set_manufacturer_data_list(
          current_scan_result.manufacturer_data_list());
      should_update = true;
    }

    if (scan_result.services() == nullptr &&
        current_scan_result.services() != nullptr) {
      scan_result.set_services(current_scan_result.services());
      should_update = true;
    }

    // if nothing to update then return
    if (!should_update) {
      return;
    }
  }

  // Update cache
  scan_results_.insert_or_assign(scan_result.device_id(), scan_result);

  // Filter final result before sending to Flutter
  if (is_connectable && filterDevice(scan_result)) {
    scan_result.set_timestamp(GetCurrentTimestampMillis());
    ui_thread_handler_.Post([scan_result] {
      callback_channel->OnScanResult(scan_result, SuccessCallback,
                                     ErrorCallback);
    });
  }
}

void UniversalBlePlugin::SetupDeviceWatcher() {
  if (device_watcher_ != nullptr)
    return;

  device_watcher_ = DeviceInformation::CreateWatcher(
      L"(System.Devices.Aep.ProtocolId:=\"{bb7bb05e-5972-42b5-94fc-"
      L"76eaa7084d49}\")",
      {
          device_address_key,
          is_connected_key,
          is_paired_key,
          is_present_key,
          is_connectable_key,
          signal_strength_key,
      },
      DeviceInformationKind::AssociationEndpoint);

  /// Device Added from DeviceWatcher
  device_watcher_added_token_ = device_watcher_.Added(
      [this](DeviceWatcher sender, const DeviceInformation &device_info) {
        const auto properties = device_info.Properties();
        if (!properties.HasKey(device_address_key)) {
          return;
        }
        const auto device_address =
            to_string(properties.Lookup(device_address_key)
                          .as<IPropertyValue>()
                          .GetString());
        const std::string device_info_id = to_string(device_info.Id());
        // Map Id -> MAC and MAC -> DeviceInformation
        device_watcher_id_to_mac_.insert_or_assign(device_info_id,
                                                   device_address);
        device_watcher_devices_.insert_or_assign(device_address, device_info);
        OnDeviceInfoReceived(device_info);
        // On Device Added
      });

  // Update only if device is already discovered in deviceWatcher.Added
  device_watcher_updated_token_ = device_watcher_.Updated(
      [this](DeviceWatcher sender,
             const DeviceInformationUpdate &device_info_update) {
        const std::string device_info_id = to_string(device_info_update.Id());
        // Resolve MAC from Id
        const auto mac_lookup = device_watcher_id_to_mac_.get(device_info_id);
        if (!mac_lookup.has_value()) {
          return;
        }
        const std::string mac_key = mac_lookup.value();
        const auto it = device_watcher_devices_.get(mac_key);
        if (it.has_value()) {
          const auto value = it.value();
          value.Update(device_info_update);
          device_watcher_devices_.insert_or_assign(mac_key, value);
          OnDeviceInfoReceived(value);
        }
        // On Device Updated
      });

  device_watcher_removed_token_ = device_watcher_.Removed(
      [this](DeviceWatcher sender, const DeviceInformationUpdate &args) {
        const std::string device_id = to_string(args.Id());
        const auto mac_lookup = device_watcher_id_to_mac_.get(device_id);
        if (mac_lookup.has_value()) {
          const std::string mac_key = mac_lookup.value();
          device_watcher_devices_.remove(mac_key);
          device_watcher_id_to_mac_.remove(device_id);
        }
        // On Device Removed
      });

  device_watcher_enumeration_completed_token_ =
      device_watcher_.EnumerationCompleted([this](DeviceWatcher sender,
                                                  IInspectable args) {
        UniversalBleLogger::LogInfo("DeviceWatcherEvent: EnumerationCompleted");
        DisposeDeviceWatcher();
        // EnumerationCompleted
      });

  device_watcher_stopped_token_ =
      device_watcher_.Stopped([this](DeviceWatcher sender, IInspectable args) {
        // std::cout << "DeviceWatcherEvent: Stopped" << std::endl;
        //  disposeDeviceWatcher();
        // DeviceWatcher Stopped
      });
}

void UniversalBlePlugin::DisposeDeviceWatcher() {
  if (device_watcher_ != nullptr) {
    device_watcher_.Added(device_watcher_added_token_);
    device_watcher_.Updated(device_watcher_updated_token_);
    device_watcher_.Removed(device_watcher_removed_token_);
    device_watcher_.EnumerationCompleted(
        device_watcher_enumeration_completed_token_);
    device_watcher_.Stopped(device_watcher_stopped_token_);
    const auto status = device_watcher_.Status();
    // std::cout << "DisposingDeviceWatcher, CurrentState: " <<
    // DeviceWatcherStatusToString(status) << std::endl;
    if (status == DeviceWatcherStatus::Started) {
      device_watcher_.Stop();
    }
    device_watcher_ = nullptr;
    device_watcher_devices_.clear();
    device_watcher_id_to_mac_.clear();
  }
}

void UniversalBlePlugin::OnDeviceInfoReceived(
    const DeviceInformation &device_info) {
  const auto properties = device_info.Properties();

  // Avoid devices if not connectable or if deviceAddressKey is not present
  if (!(properties.HasKey(is_connectable_key) &&
        (properties.Lookup(is_connectable_key).as<IPropertyValue>())
            .GetBoolean()) ||
      !properties.HasKey(device_address_key))
    return;

  const auto bluetooth_address_property_value =
      properties.Lookup(device_address_key).as<IPropertyValue>();
  const std::string device_address =
      to_string(bluetooth_address_property_value.GetString());

  // Update device info if already discovered in advertisementWatcher
  if (scan_results_.get(device_address).has_value()) {
    bool is_paired = device_info.Pairing().IsPaired();
    if (properties.HasKey(is_paired_key)) {
      const auto is_paired_property_value =
          properties.Lookup(is_paired_key).as<IPropertyValue>();
      is_paired = is_paired_property_value.GetBoolean();
    }

    UniversalBleScanResult universal_scan_result(device_address);
    universal_scan_result.set_is_paired(is_paired);

    if (!device_info.Name().empty())
      universal_scan_result.set_name(to_string(device_info.Name()));

    if (properties.HasKey(signal_strength_key)) {
      const auto rssi_property_value =
          properties.Lookup(signal_strength_key).as<IPropertyValue>();
      const int16_t rssi = rssi_property_value.GetInt16();
      universal_scan_result.set_rssi(rssi);
    }

    PushUniversalScanResult(universal_scan_result, true);
  }
}

/// Advertisement received from advertisementWatcher
void UniversalBlePlugin::BluetoothLeWatcherReceived(
    const BluetoothLEAdvertisementWatcher &,
    const BluetoothLEAdvertisementReceivedEventArgs &args) {
  try {
    auto device_id = mac_address_to_str(args.BluetoothAddress());
    auto universal_scan_result = UniversalBleScanResult(device_id);
    std::string name = to_string(args.Advertisement().LocalName());

    auto manufacturer_data_encodable_list = flutter::EncodableList();
    if (args.Advertisement() != nullptr) {
      for (BluetoothLEManufacturerData msd :
           args.Advertisement().ManufacturerData()) {
        auto universal_manufacturer_data = UniversalManufacturerData(
            static_cast<int64_t>(msd.CompanyId()), to_bytevc(msd.Data()));
        manufacturer_data_encodable_list.push_back(
            flutter::CustomEncodableValue(universal_manufacturer_data));
      }
    }

    auto service_data_map = flutter::EncodableMap();
    auto data_section = args.Advertisement().DataSections();
    for (auto &&data : data_section) {
      auto data_bytes = to_bytevc(data.Data());
      auto data_type = data.DataType();

      // Use CompleteName from dataType if localName is empty
      if (name.empty() &&
          data_type == static_cast<uint8_t>(
                           AdvertisementSectionType::CompleteLocalName)) {
        name = std::string(data_bytes.begin(), data_bytes.end());
      }
      // Use ShortenedLocalName from dataType if localName is empty
      else if (name.empty() &&
               data_type == static_cast<uint8_t>(
                                AdvertisementSectionType::ShortenedLocalName)) {
        name = std::string(data_bytes.begin(), data_bytes.end());
      }
      // Extract service data
      else if (data_type ==
                   static_cast<uint8_t>(
                       AdvertisementSectionType::ServiceData16BitUuids) ||
               data_type ==
                   static_cast<uint8_t>(
                       AdvertisementSectionType::ServiceData32BitUuids) ||
               data_type ==
                   static_cast<uint8_t>(
                       AdvertisementSectionType::ServiceData128BitUuids)) {
        // Helper lambda to parse UUID and extract service data
        auto parse_service_data =
            [&](const std::vector<uint8_t> &bytes,
                uint8_t type) -> std::pair<std::string, std::vector<uint8_t>> {
          std::string uuid;
          std::vector<uint8_t> data_payload;
          size_t uuid_size = 0;

          if (type == static_cast<uint8_t>(
                          AdvertisementSectionType::ServiceData16BitUuids)) {
            uuid_size = 2;
          } else if (type ==
                     static_cast<uint8_t>(
                         AdvertisementSectionType::ServiceData32BitUuids)) {
            uuid_size = 4;
          } else if (type ==
                     static_cast<uint8_t>(
                         AdvertisementSectionType::ServiceData128BitUuids)) {
            uuid_size = 16;
          }

          if (bytes.size() >= uuid_size) {
            std::vector<uint8_t> uuid_bytes(bytes.begin(),
                                            bytes.begin() + uuid_size);
            uuid = ExpandServiceUuid(uuid_bytes, type);
            if (bytes.size() > uuid_size) {
              data_payload =
                  std::vector<uint8_t>(bytes.begin() + uuid_size, bytes.end());
            }
          }

          return {uuid, data_payload};
        };

        auto [service_uuid, service_data_bytes] =
            parse_service_data(data_bytes, data_type);
        if (!service_uuid.empty()) {
          service_data_map[service_uuid] =
              flutter::EncodableValue(service_data_bytes);
        }
      }
    }

    if (!name.empty()) {
      universal_scan_result.set_name(name);
    }

    if (!manufacturer_data_encodable_list.empty()) {
      universal_scan_result.set_manufacturer_data_list(
          manufacturer_data_encodable_list);
    }

    universal_scan_result.set_rssi(args.RawSignalStrengthInDBm());

    // Add services
    auto services = flutter::EncodableList();
    for (auto &&uuid : args.Advertisement().ServiceUuids())
      services.push_back(guid_to_uuid(uuid));
    universal_scan_result.set_services(services);

    // Add service data
    if (!service_data_map.empty()) {
      universal_scan_result.set_service_data(&service_data_map);
    }

    // check if this device already discovered in deviceWatcher
    auto it = device_watcher_devices_.get(device_id);
    if (it.has_value()) {
      auto &device_info = it.value();
      auto properties = device_info.Properties();

      // Update Paired Status
      bool is_paired = device_info.Pairing().IsPaired();
      if (properties.HasKey(is_paired_key))
        is_paired = (properties.Lookup(is_paired_key).as<IPropertyValue>())
                        .GetBoolean();
      universal_scan_result.set_is_paired(is_paired);

      // Update Name
      if (name.empty() && !device_info.Name().empty())
        universal_scan_result.set_name(to_string(device_info.Name()));
    }

    // Filter Device
    PushUniversalScanResult(universal_scan_result, args.IsConnectable());
  } catch (...) {
    UniversalBleLogger::LogError("ScanResultErrorInParsing");
  }
}

void UniversalBlePlugin::RadioStateChanged(const Radio &sender,
                                           const IInspectable &) {
  const auto radio_state = !sender ? RadioState::Disabled : sender.State();
  if (old_radio_state_ == radio_state) {
    return;
  }
  old_radio_state_ = radio_state;
  auto state = get_availability_state_from_radio(radio_state);

  ui_thread_handler_.Post([state] {
    callback_channel->OnAvailabilityChanged(static_cast<int>(state),
                                            SuccessCallback, ErrorCallback);
  });
}

fire_and_forget UniversalBlePlugin::ConnectAsync(uint64_t bluetooth_address) {
  BluetoothLEDevice device =
      co_await BluetoothLEDevice::FromBluetoothAddressAsync(bluetooth_address);
  if (!device) {
    UniversalBleLogger::LogError(
        "ConnectionLog: ConnectionFailed: Failed to get device");
    ui_thread_handler_.Post([bluetooth_address] {
      callback_channel->OnConnectionChanged(
          mac_address_to_str(bluetooth_address), false,
          new std::string("Failed to get device"), SuccessCallback,
          ErrorCallback);
    });

    co_return;
  }
  UniversalBleLogger::LogInfo("ConnectionLog: Device found");
  auto services_result =
      co_await device.GetGattServicesAsync((BluetoothCacheMode::Uncached));
  auto services_result_error =
      gatt_communication_status_to_error(services_result.Status());
  if (services_result_error.has_value()) {
    UniversalBleLogger::LogError("ConnectionFailed: Failed to get services: " +
                                 services_result_error.value());
    ui_thread_handler_.Post([bluetooth_address, services_result_error] {
      callback_channel->OnConnectionChanged(
          mac_address_to_str(bluetooth_address), false,
          &services_result_error.value(), SuccessCallback, ErrorCallback);
    });
    co_return;
  }

  UniversalBleLogger::LogInfo("ConnectionLog: Services discovered");
  std::unordered_map<std::string, GattServiceObject> gatt_map;
  auto gatt_services = services_result.Services();
  for (GattDeviceService &&service : gatt_services) {
    GattServiceObject gatt_service;
    gatt_service.obj = service;
    std::string service_uuid = guid_to_uuid(service.Uuid());
    auto characteristics_result =
        co_await service.GetCharacteristicsAsync(BluetoothCacheMode::Uncached);
    auto characteristics_result_error =
        gatt_communication_status_to_error(characteristics_result.Status());

    if (characteristics_result_error.has_value()) {
      UniversalBleLogger::LogError(
          "Failed to get characteristics for service: " + service_uuid +
          ", With Status: " + characteristics_result_error.value());
      continue;
      // PostConnectionUpdate(bluetoothAddress, ConnectionState::disconnected);
      // co_return;
    }
    auto gatt_characteristics = characteristics_result.Characteristics();
    for (GattCharacteristic &&characteristic : gatt_characteristics) {
      GattCharacteristicObject gatt_characteristic;
      gatt_characteristic.obj = characteristic;
      gatt_characteristic.subscription_token = std::nullopt;
      std::string characteristic_uuid = guid_to_uuid(characteristic.Uuid());
      gatt_service.characteristics.insert_or_assign(
          characteristic_uuid, std::move(gatt_characteristic));
    }
    gatt_map.insert_or_assign(service_uuid, std::move(gatt_service));
  }

  event_token connection_status_changed_token = device.ConnectionStatusChanged(
      {this, &UniversalBlePlugin::BluetoothLeDeviceConnectionStatusChanged});
  auto device_agent = std::make_unique<BluetoothDeviceAgent>(
      device, connection_status_changed_token, gatt_map);
  auto pair = std::make_pair(bluetooth_address, std::move(device_agent));
  connected_devices_.insert(std::move(pair));
  UniversalBleLogger::LogInfo("ConnectionLog: Connected");
  ui_thread_handler_.Post([bluetooth_address] {
    callback_channel->OnConnectionChanged(mac_address_to_str(bluetooth_address),
                                          true, nullptr, SuccessCallback,
                                          ErrorCallback);
  });
}

void UniversalBlePlugin::BluetoothLeDeviceConnectionStatusChanged(
    const BluetoothLEDevice &sender, const IInspectable &) {
  if (sender.ConnectionStatus() == BluetoothConnectionStatus::Disconnected) {
    CleanConnection(sender.BluetoothAddress());
    auto bluetooth_address = sender.BluetoothAddress();
    ui_thread_handler_.Post([bluetooth_address] {
      callback_channel->OnConnectionChanged(
          mac_address_to_str(bluetooth_address), false, nullptr,
          SuccessCallback, ErrorCallback);
    });
  }
}

void UniversalBlePlugin::CleanConnection(const uint64_t bluetooth_address) {
  const auto node = connected_devices_.extract(bluetooth_address);
  if (!node.empty()) {
    const auto device_agent = std::move(node.mapped());
    device_agent->device.ConnectionStatusChanged(
        device_agent->connection_status_changed_token);
    DisposeServices(device_agent);
  }
}

void UniversalBlePlugin::DisposeServices(
    const std::unique_ptr<BluetoothDeviceAgent> &device_agent) {
  for (auto &[service_id, service] : device_agent->gatt_map) {
    for (auto &[char_id, characteristic] : service.characteristics) {
      if (characteristic.subscription_token.has_value()) {
        characteristic.obj.ValueChanged(
            characteristic.subscription_token.value());
        characteristic.subscription_token = std::nullopt;
      }
    }
  }
  device_agent->gatt_map.clear();
}

fire_and_forget UniversalBlePlugin::GetSystemDevicesAsync(
    std::vector<std::string> with_services,
    std::function<void(ErrorOr<flutter::EncodableList> reply)> result) {
  try {
    auto selector = BluetoothLEDevice::GetDeviceSelectorFromConnectionStatus(
        BluetoothConnectionStatus::Connected);
    DeviceInformationCollection devices =
        co_await DeviceInformation::FindAllAsync(selector);
    auto results = flutter::EncodableList();
    for (auto &&device_info : devices) {
      try {
        BluetoothLEDevice device =
            co_await BluetoothLEDevice::FromIdAsync(device_info.Id());
        auto device_id = mac_address_to_str(device.BluetoothAddress());
        // Filter by services
        if (!with_services.empty()) {
          auto service_result =
              co_await device.GetGattServicesAsync(BluetoothCacheMode::Cached);
          if (service_result.Status() == GattCommunicationStatus::Success) {
            bool has_service = false;
            for (auto service : service_result.Services()) {
              std::string service_uuid = to_uuidstr(service.Uuid());
              if (std::find(with_services.begin(), with_services.end(),
                            service_uuid) != with_services.end()) {
                has_service = true;
                break;
              }
            }
            if (!has_service)
              continue;
          }
        }
        // Add to results, if pass all filters
        auto universal_scan_result = UniversalBleScanResult(device_id);
        universal_scan_result.set_name(to_string(device_info.Name()));
        universal_scan_result.set_is_paired(device_info.Pairing().IsPaired());
        results.push_back(flutter::CustomEncodableValue(universal_scan_result));
      } catch (...) {
      }
    }
    result(results);
  } catch (const hresult_error &err) {
    int error_code = err.code();
    UniversalBleLogger::LogError(
        "GetConnectedDeviceLog: " + to_string(err.message()) +
        " ErrorCode: " + std::to_string(error_code));
    result(create_flutter_error(UniversalBleErrorCode::kFailed,
                                to_string(err.message()),
                                std::to_string(error_code)));
  } catch (...) {
    UniversalBleLogger::LogError("Unknown error GetSystemDevicesAsyncAsync");
    result(create_flutter_error(UniversalBleErrorCode::kUnknownError,
                                "Unknown error"));
  }
}

fire_and_forget UniversalBlePlugin::DiscoverServicesAsync(
    const std::string &device_id, bool with_descriptors,
    std::function<void(ErrorOr<flutter::EncodableList> reply)> result) {
  try {
    const auto it = connected_devices_.find(str_to_mac_address(device_id));
    if (it == connected_devices_.end()) {
      result(create_flutter_error(UniversalBleErrorCode::kDeviceNotFound,
                                  "Unknown devicesId:" + device_id));
      co_return;
    }

    auto universal_services = flutter::EncodableList();
    for (auto &[service_id, service] : it->second->gatt_map) {
      flutter::EncodableList universal_characteristics;
      for (auto [char_id, characteristic] : service.characteristics) {
        auto &c = characteristic.obj;
        const auto properties_value = c.CharacteristicProperties();
        auto properties = properties_to_flutter_encodable(properties_value);
        auto descriptors = flutter::EncodableList();
        if (with_descriptors) {
          try {
            // move continuation to background and execute in safe thread
            // context
            co_await winrt::resume_background();
            auto descriptor_result =
                co_await c.GetDescriptorsAsync(BluetoothCacheMode::Cached);
            if (descriptor_result.Status() ==
                GattCommunicationStatus::Success) {
              auto descriptors_list = descriptor_result.Descriptors();
              for (auto &&descriptor : descriptors_list) {
                descriptors.push_back(flutter::CustomEncodableValue(
                    UniversalBleDescriptor(to_uuidstr(descriptor.Uuid()))));
              }
            }
          } catch (...) {
            UniversalBleLogger::LogError("DiscoverServicesAsync: failed to get "
                                         "descriptors for characteristic");
          }
        }
        universal_characteristics.push_back(
            flutter::CustomEncodableValue(UniversalBleCharacteristic(
                to_uuidstr(c.Uuid()), properties, descriptors)));
      }

      auto universal_ble_service =
          UniversalBleService(to_uuidstr(service.obj.Uuid()));
      universal_ble_service.set_characteristics(universal_characteristics);
      universal_services.push_back(
          flutter::CustomEncodableValue(universal_ble_service));
    }
    result(universal_services);
  } catch (const hresult_error &err) {
    const int error_code = err.code();
    result(create_flutter_error(UniversalBleErrorCode::kFailed,
                                "DiscoverServicesAsync failed",
                                std::to_string(error_code)));
  } catch (const FlutterError &err) {
    result(err);
  } catch (...) {
    result(create_flutter_error(UniversalBleErrorCode::kUnknownError,
                                "Unknown error"));
  }
}

fire_and_forget UniversalBlePlugin::IsPairedAsync(
    const std::string &device_id,
    const std::function<void(ErrorOr<bool> reply)> result) {
  try {
    const auto device = co_await BluetoothLEDevice::FromBluetoothAddressAsync(
        str_to_mac_address(device_id));
    if (device == nullptr) {
      result(create_flutter_error(UniversalBleErrorCode::kDeviceNotFound,
                                  "Unknown devicesId:" + device_id));
      co_return;
    }
    const bool is_paired = device.DeviceInformation().Pairing().IsPaired();
    result(is_paired);
  } catch (...) {
    UniversalBleLogger::LogError("IsPairedAsync: Error");
    result(create_flutter_error(UniversalBleErrorCode::kUnknownError,
                                "Unknown error"));
  }
}

fire_and_forget UniversalBlePlugin::SetNotifiableAsync(
    const std::string &device_id, const std::string &service,
    const std::string &characteristic, const int64_t ble_input_property,
    const std::function<void(std::optional<FlutterError> reply)> result) {
  UniversalBleLogger::LogDebugWithTimestamp(
      "SET_NOTIFY -> " + device_id + " " + service + " " + characteristic +
      " input=" + std::to_string(ble_input_property));
  try {
    const auto it = connected_devices_.find(str_to_mac_address(device_id));
    if (it == connected_devices_.end()) {
      result(create_flutter_error(UniversalBleErrorCode::kDeviceNotFound,
                                  "Unknown devicesId:" + device_id));
      co_return;
    }

    auto &gatt_char = it->second->FetchCharacteristic(service, characteristic);

    const auto properties = gatt_char.obj.CharacteristicProperties();
    auto descriptor_value =
        GattClientCharacteristicConfigurationDescriptorValue::None;
    if (ble_input_property ==
        static_cast<int>(BleInputProperty::notification)) {
      descriptor_value =
          GattClientCharacteristicConfigurationDescriptorValue::Notify;
      if ((properties & GattCharacteristicProperties::Notify) ==
          GattCharacteristicProperties::None) {
        result(create_flutter_error(
            UniversalBleErrorCode::kCharacteristicDoesNotSupportNotify,
            "Characteristic does not support notify"));
        co_return;
      }
    } else if (ble_input_property ==
               static_cast<int>(BleInputProperty::indication)) {
      descriptor_value =
          GattClientCharacteristicConfigurationDescriptorValue::Indicate;
      if ((properties & GattCharacteristicProperties::Indicate) ==
          GattCharacteristicProperties::None) {
        result(create_flutter_error(
            UniversalBleErrorCode::kCharacteristicDoesNotSupportIndicate,
            "Characteristic does not support indicate"));
        co_return;
      }
    }

    const auto gatt_characteristic = gatt_char.obj;
    const auto uuid = to_uuidstr(gatt_characteristic.Uuid());

    // Write to the descriptor.
    const auto status =
        co_await gatt_characteristic
            .WriteClientCharacteristicConfigurationDescriptorAsync(
                descriptor_value);
    if (status != GattCommunicationStatus::Success) {
      UniversalBleLogger::LogError("SET_NOTIFY_FAILED <- " + device_id + " " +
                                   service + " " + characteristic + " status=" +
                                   std::to_string(static_cast<int>(status)));
      result(create_flutter_error_from_gatt_communication_status(status));
      co_return;
    }

    // Register/UnRegister handler for the ValueChanged event.
    if (descriptor_value ==
        GattClientCharacteristicConfigurationDescriptorValue::None) {
      if (gatt_char.subscription_token.has_value()) {
        gatt_characteristic.ValueChanged(gatt_char.subscription_token.value());
        gatt_char.subscription_token = std::nullopt;
        UniversalBleLogger::LogInfo("Unsubscribed " +
                                    to_uuidstr(gatt_characteristic.Uuid()));
      }
    } else {
      // If a notification for the given characteristic is already in progress,
      // swap the callbacks.
      if (gatt_char.subscription_token.has_value()) {
        UniversalBleLogger::LogWarning(
            "A notification for the given characteristic is already in "
            "progress. Swapping callbacks.");
        gatt_characteristic.ValueChanged(gatt_char.subscription_token.value());
        gatt_char.subscription_token = std::nullopt;
      }

      gatt_char.subscription_token =
          std::make_optional(gatt_characteristic.ValueChanged(
              {this, &UniversalBlePlugin::GattCharacteristicValueChanged}));
    }

    result(std::nullopt);
  } catch (const FlutterError &err) {
    result(err);
  } catch (...) {
    UniversalBleLogger::LogError("SetNotifiableLog: Unknown error");
    result(create_flutter_unknown_error());
  }
}

void UniversalBlePlugin::GattCharacteristicValueChanged(
    const GattCharacteristic &sender, const GattValueChangedEventArgs &args) {
  auto uuid = to_uuidstr(sender.Uuid());
  auto bytes = to_bytevc(args.CharacteristicValue());
  auto device_id =
      mac_address_to_str(sender.Service().Device().BluetoothAddress());

  UniversalBleLogger::LogVerboseWithTimestamp(
      "NOTIFY <- " + device_id + " " + uuid +
      " len=" + std::to_string(bytes.size()));

  auto timestamp = GetCurrentTimestampMillis();
  ui_thread_handler_.Post([sender, bytes, timestamp] {
    auto uuid = to_uuidstr(sender.Uuid());
    callback_channel->OnValueChanged(
        mac_address_to_str(sender.Service().Device().BluetoothAddress()), uuid,
        bytes, &timestamp, SuccessCallback, ErrorCallback);
  });
}

} // namespace universal_ble