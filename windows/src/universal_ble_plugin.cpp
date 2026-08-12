// ReSharper disable CppTooWideScopeInitStatement
// ReSharper disable CppTooWideScope
#include "universal_ble_plugin.h"
#include <windows.h>

#include <flutter/plugin_registrar_windows.h>

#include <algorithm>
#include <cctype>
#include <future>
#include <iomanip>
#include <memory>
#include <regex>
#include <sstream>
#include <thread>
#include <utility>

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
std::unique_ptr<UniversalBlePeripheralCallback> peripheral_callback_channel_;

namespace {
template <typename Reply, typename Value>
void safe_reply(const char *context, const Reply &reply, Value &&value) noexcept {
  try {
    reply(std::forward<Value>(value));
  } catch (const hresult_error &err) {
    try {
      UniversalBleLogger::LogError(
          std::string(context) + " reply hresult_error hr=" +
          std::to_string(err.code()) + " msg=" + to_string(err.message()));
    } catch (...) {
    }
  } catch (const std::exception &err) {
    try {
      UniversalBleLogger::LogError(std::string(context) +
                                   " reply std::exception: " + err.what());
    } catch (...) {
    }
  } catch (...) {
    try {
      UniversalBleLogger::LogError(std::string(context) +
                                   " reply unknown exception");
    } catch (...) {
    }
  }
}

std::string to_lower_case(std::string value) {
  std::transform(
      value.begin(), value.end(), value.begin(),
      [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  return value;
}

IPropertyValue lookup_i_property_value(
    const IMapView<hstring, IInspectable> &properties, const hstring &key,
    const char *property_name, const char *context) {
  try {
    auto value = properties.Lookup(key).try_as<IPropertyValue>();
    if (!value) {
      UniversalBleLogger::LogError(std::string(context) +
                                   ": unexpected type for " + property_name +
                                   " property");
    }
    return value;
  } catch (const hresult_error &err) {
    UniversalBleLogger::LogError(std::string(context) + ": failed to lookup " +
                                 property_name + " property (hr=" +
                                 std::to_string(err.code()) + ")");
    return nullptr;
  }
}
} // namespace

void UniversalBlePlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto plugin = std::make_unique<UniversalBlePlugin>(registrar);
  UniversalBlePlatformChannel::SetUp(registrar->messenger(), plugin.get());
  UniversalBlePeripheralChannel::SetUp(registrar->messenger(), plugin.get());
  callback_channel =
      std::make_unique<UniversalBleCallbackChannel>(registrar->messenger());
  peripheral_callback_channel_ =
      std::make_unique<UniversalBlePeripheralCallback>(registrar->messenger());
  registrar->AddPlugin(std::move(plugin));
}

UniversalBlePlugin::UniversalBlePlugin(
    flutter::PluginRegistrarWindows *registrar)
    : registrar_(registrar), ui_thread_handler_(registrar) {
  InitializeAsync();
}

UniversalBlePlugin::~UniversalBlePlugin() {
  // Stop new WinRT callbacks from entering before any owned state is released.
  callback_operations_.Close();
  ResetState();
  ClearServices();
  callback_operations_.WaitUntilIdle();
  ui_thread_handler_.Shutdown();
  callback_channel.reset();
  peripheral_callback_channel_.reset();
}

// UniversalBlePlatformChannel implementation.
void UniversalBlePlugin::GetBluetoothAvailabilityState(
    std::function<void(ErrorOr<AvailabilityState> reply)> result) {
  if (!bluetooth_radio_) {
    if (!initialized_) {
      result(AvailabilityState::kUnknown);
    } else {
      result(AvailabilityState::kUnsupported);
    }
  } else {
    result(get_availability_state_from_radio(bluetooth_radio_.State()));
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
      .Completed([result](const IAsyncOperation<RadioAccessStatus> &sender,
                          const AsyncStatus args) {
        try {
          if (args != AsyncStatus::Completed) {
            safe_reply(
                "EnableBluetooth", result,
                create_flutter_error(
                    UniversalBleErrorCode::kFailed,
                    args == AsyncStatus::Canceled
                        ? "Enable bluetooth was cancelled"
                        : "Failed to enable bluetooth"));
            return;
          }
          if (const auto radio_access_status = sender.GetResults();
              radio_access_status == RadioAccessStatus::Allowed) {
            safe_reply("EnableBluetooth", result, true);
          } else {
            safe_reply("EnableBluetooth", result,
                       create_flutter_error(UniversalBleErrorCode::kFailed,
                                            "Failed to enable bluetooth"));
          }
        } catch (const hresult_error &err) {
          safe_reply("EnableBluetooth", result,
                     create_flutter_error(UniversalBleErrorCode::kFailed,
                                          to_string(err.message()),
                                          std::to_string(err.code())));
        } catch (...) {
          safe_reply("EnableBluetooth", result, create_flutter_unknown_error());
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
      .Completed([result](IAsyncOperation<RadioAccessStatus> const &sender,
                          AsyncStatus const args) {
        try {
          if (args != AsyncStatus::Completed) {
            safe_reply(
                "DisableBluetooth", result,
                create_flutter_error(
                    UniversalBleErrorCode::kFailed,
                    args == AsyncStatus::Canceled
                        ? "Disable bluetooth was cancelled"
                        : "Failed to disable bluetooth"));
            return;
          }
          if (const auto radio_access_status = sender.GetResults();
              radio_access_status == RadioAccessStatus::Allowed) {
            safe_reply("DisableBluetooth", result, true);
          } else {
            safe_reply("DisableBluetooth", result,
                       create_flutter_error(UniversalBleErrorCode::kFailed,
                                            "Failed to disable bluetooth"));
          }
        } catch (const hresult_error &err) {
          safe_reply("DisableBluetooth", result,
                     create_flutter_error(UniversalBleErrorCode::kFailed,
                                          to_string(err.message()),
                                          std::to_string(err.code())));
        } catch (...) {
          safe_reply("DisableBluetooth", result, create_flutter_unknown_error());
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
UniversalBlePlugin::StartScan(const UniversalScanFilter *filter,
                              const UniversalScanConfig *config) {

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

      const auto callback_operations = callback_operations_;
      bluetooth_le_watcher_received_token_ = bluetooth_le_watcher_.Received(
          [this, callback_operations](const auto &sender, const auto &args) {
            const auto callback = callback_operations.TryAcquire();
            if (!callback.has_value()) return;
            BluetoothLeWatcherReceived(sender, args);
          });
    }
    bluetooth_le_watcher_.Start();
    return std::nullopt;
  } catch (const hresult_error &err) {
    StopScan();
    UniversalBleLogger::LogError(
        "StartScan hresult_error hr=" + std::to_string(err.code()) +
        " msg=" + to_string(err.message()));
    return create_flutter_error(UniversalBleErrorCode::kFailed,
                                to_string(err.message()),
                                std::to_string(err.code()));
  } catch (...) {
    StopScan();
    UniversalBleLogger::LogError("Unknown error StartScan");
    return create_flutter_error(UniversalBleErrorCode::kUnknownError,
                                "Unknown error");
  }
};

std::optional<FlutterError> UniversalBlePlugin::StopScan() {
  try {
    if (bluetooth_le_watcher_) {
      try {
        bluetooth_le_watcher_.Received(bluetooth_le_watcher_received_token_);
      } catch (...) {
        log_and_swallow_unknown("StopScan unregister advertisement watcher");
      }
      try {
        bluetooth_le_watcher_.Stop();
      } catch (...) {
        log_and_swallow_unknown("StopScan stop advertisement watcher");
      }
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

ErrorOr<BleConnectionState>
UniversalBlePlugin::GetConnectionState(const std::string &device_id) {
  try {
    const auto device_agent =
        GetConnectedDevice(str_to_mac_address(device_id));
    if (!device_agent || !device_agent->IsActive()) {
      return BleConnectionState::kDisconnected;
    }

    if (device_agent->device.ConnectionStatus() ==
        BluetoothConnectionStatus::Connected) {
      return BleConnectionState::kConnected;
    }
    return BleConnectionState::kDisconnected;
  } catch (const hresult_error &err) {
    return create_flutter_error(UniversalBleErrorCode::kFailed,
                                to_string(err.message()),
                                std::to_string(err.code()));
  } catch (const FlutterError &err) {
    return err;
  } catch (...) {
    return create_flutter_unknown_error("Failed to get connection state");
  }
}

std::optional<FlutterError>
UniversalBlePlugin::SetLogLevel(const BleLogLevel &log_level) {
  UniversalBleLogger::SetLogLevel(log_level);
  return std::nullopt;
}

std::optional<FlutterError>
UniversalBlePlugin::Connect(const std::string &device_id,
                            const bool *auto_connect,
                            const ConnectionPlatformConfig *platform_config) {
  // Note: autoConnect is not directly supported on Windows platform
  // Note: platformConfig only carries Apple-specific options
  const auto bluetooth_address = str_to_mac_address(device_id);
  if (GetConnectedDevice(bluetooth_address)) {
    NotifyConnectionChanged(bluetooth_address, true, std::nullopt);
    return std::nullopt;
  }
  const auto connect_generation = BeginConnectAttempt(bluetooth_address);
  if (connect_generation.has_value()) {
    ConnectAsync(bluetooth_address, connect_generation.value());
  }
  return std::nullopt;
};

std::optional<FlutterError>
UniversalBlePlugin::Disconnect(const std::string &device_id) {
  const auto device_address = str_to_mac_address(device_id);
  InvalidateConnectAttempt(device_address);
  DisposeConnection(RemoveConnectedDevice(device_address));
  NotifyConnectionChanged(device_address, false, std::nullopt);
  return std::nullopt;
}

void UniversalBlePlugin::DiscoverServices(
    const std::string &device_id, bool with_descriptors,
    std::function<void(ErrorOr<flutter::EncodableList> reply)> result) {
  DiscoverServicesAsync(device_id, with_descriptors, result);
}

void UniversalBlePlugin::SetNotifiable(
    const std::string &device_id, const std::string &service,
    const std::string &characteristic,
    const BleInputProperty &ble_input_property,
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
    const auto bluetooth_agent =
        GetConnectedDevice(str_to_mac_address(device_id));
    if (!bluetooth_agent) {
      result(create_flutter_error(UniversalBleErrorCode::kDeviceNotFound,
                                  "Unknown devicesId:" + device_id));
      return;
    }

    const auto gatt_characteristic_lease =
        bluetooth_agent->FetchCharacteristicForOperation(service,
                                                         characteristic);
    const GattCharacteristic gatt_characteristic =
        gatt_characteristic_lease.characteristic.obj;

    const auto properties = gatt_characteristic.CharacteristicProperties();
    if ((properties & GattCharacteristicProperties::Read) ==
        GattCharacteristicProperties::None) {
      result(create_flutter_error(
          UniversalBleErrorCode::kCharacteristicDoesNotSupportRead,
          "Characteristic does not support read"));
      return;
    }

    gatt_characteristic.ReadValueAsync(BluetoothCacheMode::Uncached)
        .Completed([bluetooth_agent, gatt_characteristic_lease, device_id,
                    service, characteristic, result](
                       IAsyncOperation<GattReadResult> const &sender,
                       AsyncStatus const args) {
          try {
            if (!bluetooth_agent->IsActive()) {
              safe_reply(
                  "ReadValue", result,
                  create_flutter_error(UniversalBleErrorCode::kDeviceDisconnected,
                                       "Device disconnected during read"));
              return;
            }
            if (args != AsyncStatus::Completed) {
              safe_reply(
                  "ReadValue", result,
                  create_flutter_error(
                      UniversalBleErrorCode::kFailed,
                      args == AsyncStatus::Canceled ? "Read was cancelled"
                                                    : "Read failed"));
              return;
            }
            const auto read_value_result = sender.GetResults();
            const auto status = read_value_result.Status();
            if (status != GattCommunicationStatus::Success) {
              UniversalBleLogger::LogError(
                  "READ_FAILED <- " + device_id + " " + service + " " +
                  characteristic +
                  " status=" + std::to_string(static_cast<int>(status)));
              safe_reply("ReadValue", result,
                         create_flutter_error_from_gatt_communication_status(
                             status));
            } else {
              if (!bluetooth_agent->IsActive()) {
                safe_reply(
                    "ReadValue", result,
                    create_flutter_error(
                        UniversalBleErrorCode::kDeviceDisconnected,
                        "Device disconnected during read"));
                return;
              }
              safe_reply("ReadValue", result,
                         to_bytevc(read_value_result.Value()));
            }
          } catch (const hresult_error &err) {
            safe_reply("ReadValue", result,
                       create_flutter_error(UniversalBleErrorCode::kFailed,
                                            to_string(err.message()),
                                            std::to_string(err.code())));
          } catch (...) {
            UniversalBleLogger::LogError(
                "ReadValue completion unknown exception");
            safe_reply("ReadValue", result, create_flutter_unknown_error());
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
    const BleOutputProperty &ble_output_property,
    std::function<void(std::optional<FlutterError> reply)> result) {
  UniversalBleLogger::LogDebugWithTimestamp(
      "WRITE -> " + device_id + " " + service + " " + characteristic +
      " len=" + std::to_string(value.size()) +
      " property=" + std::to_string(static_cast<int>(ble_output_property)));
  try {
    const auto bluetooth_agent =
        GetConnectedDevice(str_to_mac_address(device_id));
    if (!bluetooth_agent) {
      result(create_flutter_error(UniversalBleErrorCode::kDeviceNotFound,
                                  "Unknown devicesId:" + device_id));
      return;
    }
    const auto gatt_characteristic_lease =
        bluetooth_agent->FetchCharacteristicForOperation(service,
                                                         characteristic);
    const GattCharacteristic gatt_characteristic =
        gatt_characteristic_lease.characteristic.obj;
    const auto properties = gatt_characteristic.CharacteristicProperties();

    auto write_option = GattWriteOption::WriteWithResponse;
    if (ble_output_property == BleOutputProperty::kWithoutResponse) {
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
        .Completed([bluetooth_agent, gatt_characteristic_lease, device_id,
                    service, characteristic, result](
                       IAsyncOperation<GattCommunicationStatus> const &sender,
                       AsyncStatus const args) {
          try {
            if (!bluetooth_agent->IsActive()) {
              safe_reply(
                  "WriteValue", result,
                  create_flutter_error(UniversalBleErrorCode::kDeviceDisconnected,
                                       "Device disconnected during write"));
              return;
            }
            if (args != AsyncStatus::Completed) {
              safe_reply(
                  "WriteValue", result,
                  create_flutter_error(
                      UniversalBleErrorCode::kFailed,
                      args == AsyncStatus::Canceled ? "Write was cancelled"
                                                    : "Write failed"));
              return;
            }

            const auto status = sender.GetResults();
            if (status != GattCommunicationStatus::Success) {
              UniversalBleLogger::LogError(
                  "WRITE_FAILED <- " + device_id + " " + service + " " +
                  characteristic +
                  " status=" + std::to_string(static_cast<int>(status)));
              safe_reply("WriteValue", result,
                         create_flutter_error_from_gatt_communication_status(
                             status));
            } else {
              if (!bluetooth_agent->IsActive()) {
                safe_reply(
                    "WriteValue", result,
                    create_flutter_error(
                        UniversalBleErrorCode::kDeviceDisconnected,
                        "Device disconnected during write"));
                return;
              }
              safe_reply("WriteValue", result, std::nullopt);
            }
          } catch (const hresult_error &err) {
            safe_reply("WriteValue", result,
                       create_flutter_error(UniversalBleErrorCode::kFailed,
                                            to_string(err.message()),
                                            std::to_string(err.code())));
          } catch (...) {
            UniversalBleLogger::LogError(
                "WriteValue completion unknown exception");
            safe_reply("WriteValue", result, create_flutter_unknown_error());
          }
        });
  } catch (const FlutterError &err) {
    result(err);
  } catch (...) {
    UniversalBleLogger::LogError("WriteValue: Unknown error");
    result(create_flutter_unknown_error());
  }
}

void UniversalBlePlugin::ReadDescriptorValue(
    const std::string &device_id, const std::string &service,
    const std::string &characteristic, const std::string &descriptor,
    std::function<void(ErrorOr<std::vector<uint8_t>> reply)> result) {
  UniversalBleLogger::LogDebugWithTimestamp("READ_DESCRIPTOR -> " + device_id + " " +
                                            service + " " + characteristic + " " + descriptor);
  try {
    const auto bluetooth_agent =
        GetConnectedDevice(str_to_mac_address(device_id));
    if (!bluetooth_agent) {
      result(create_flutter_error(UniversalBleErrorCode::kDeviceNotFound,
                                  "Unknown deviceId:" + device_id));
      return;
    }

    const auto gatt_characteristic_lease =
        bluetooth_agent->FetchCharacteristicForOperation(service,
                                                         characteristic);
    const GattCharacteristic gatt_characteristic =
        gatt_characteristic_lease.characteristic.obj;

    gatt_characteristic.GetDescriptorsForUuidAsync(uuid_to_guid(descriptor), BluetoothCacheMode::Uncached)
        .Completed([bluetooth_agent, gatt_characteristic_lease, device_id,
                    service, characteristic, descriptor, result](
                       IAsyncOperation<GattDescriptorsResult> const &desc_sender,
                       AsyncStatus const desc_args) {
          try {
            if (!bluetooth_agent->IsActive()) {
              safe_reply(
                  "ReadDescriptorValue", result,
                  create_flutter_error(
                      UniversalBleErrorCode::kDeviceDisconnected,
                      "Device disconnected during descriptor read"));
              return;
            }
            if (desc_args != AsyncStatus::Completed) {
              safe_reply(
                  "ReadDescriptorValue", result,
                  create_flutter_error(
                      UniversalBleErrorCode::kFailed,
                      desc_args == AsyncStatus::Canceled ? "Read descriptor was cancelled"
                                                         : "Read descriptor failed"));
              return;
            }
            const auto desc_result = desc_sender.GetResults();
            if (desc_result.Status() != GattCommunicationStatus::Success) {
              safe_reply(
                  "ReadDescriptorValue", result,
                  create_flutter_error_from_gatt_communication_status(
                      desc_result.Status()));
              return;
            }
            if (desc_result.Descriptors().Size() == 0) {
              safe_reply("ReadDescriptorValue", result,
                         create_flutter_error(UniversalBleErrorCode::kFailed,
                                             "Descriptor not found:" + descriptor));
              return;
            }
            const auto gatt_descriptor = desc_result.Descriptors().GetAt(0);
            gatt_descriptor.ReadValueAsync(BluetoothCacheMode::Uncached)
                .Completed([bluetooth_agent, gatt_characteristic_lease,
                            device_id, service, characteristic, descriptor,
                            result](
                               IAsyncOperation<GattReadResult> const &sender,
                               AsyncStatus const args) {
                  try {
                    if (!bluetooth_agent->IsActive()) {
                      safe_reply(
                          "ReadDescriptorValue", result,
                          create_flutter_error(
                              UniversalBleErrorCode::kDeviceDisconnected,
                              "Device disconnected during descriptor read"));
                      return;
                    }
                    if (args != AsyncStatus::Completed) {
                      safe_reply(
                          "ReadDescriptorValue", result,
                          create_flutter_error(
                              UniversalBleErrorCode::kFailed,
                              args == AsyncStatus::Canceled ? "Read descriptor was cancelled"
                                                            : "Read descriptor failed"));
                      return;
                    }
                    const auto read_value_result = sender.GetResults();
                    const auto status = read_value_result.Status();
                    if (status != GattCommunicationStatus::Success) {
                      safe_reply("ReadDescriptorValue", result,
                                 create_flutter_error_from_gatt_communication_status(status));
                    } else {
                      if (!bluetooth_agent->IsActive()) {
                        safe_reply(
                            "ReadDescriptorValue", result,
                            create_flutter_error(
                                UniversalBleErrorCode::kDeviceDisconnected,
                                "Device disconnected during descriptor read"));
                        return;
                      }
                      safe_reply("ReadDescriptorValue", result,
                                 to_bytevc(read_value_result.Value()));
                    }
                  } catch (const hresult_error &err) {
                    safe_reply("ReadDescriptorValue", result,
                               create_flutter_error(UniversalBleErrorCode::kFailed,
                                                    to_string(err.message()),
                                                    std::to_string(err.code())));
                  } catch (...) {
                    safe_reply("ReadDescriptorValue", result, create_flutter_unknown_error());
                  }
                });
          } catch (const hresult_error &err) {
            safe_reply("ReadDescriptorValue", result,
                       create_flutter_error(UniversalBleErrorCode::kFailed,
                                            to_string(err.message()),
                                            std::to_string(err.code())));
          } catch (...) {
            safe_reply("ReadDescriptorValue", result, create_flutter_unknown_error());
          }
        });
  } catch (const FlutterError &err) {
    return result(err);
  } catch (...) {
    return result(create_flutter_unknown_error());
  }
}

void UniversalBlePlugin::WriteDescriptorValue(
    const std::string &device_id, const std::string &service,
    const std::string &characteristic, const std::string &descriptor,
    const std::vector<uint8_t> &value,
    std::function<void(std::optional<FlutterError> reply)> result) {
  UniversalBleLogger::LogDebugWithTimestamp(
      "WRITE_DESCRIPTOR -> " + device_id + " " + service + " " + characteristic +
      " " + descriptor + " len=" + std::to_string(value.size()));
  try {
    const auto bluetooth_agent =
        GetConnectedDevice(str_to_mac_address(device_id));
    if (!bluetooth_agent) {
      result(create_flutter_error(UniversalBleErrorCode::kDeviceNotFound,
                                  "Unknown devicesId:" + device_id));
      return;
    }
    const auto gatt_characteristic_lease =
        bluetooth_agent->FetchCharacteristicForOperation(service,
                                                         characteristic);
    const GattCharacteristic gatt_characteristic =
        gatt_characteristic_lease.characteristic.obj;

    gatt_characteristic.GetDescriptorsForUuidAsync(uuid_to_guid(descriptor), BluetoothCacheMode::Uncached)
        .Completed([bluetooth_agent, gatt_characteristic_lease, device_id,
                    service, characteristic, descriptor, value, result](
                       IAsyncOperation<GattDescriptorsResult> const &desc_sender,
                       AsyncStatus const desc_args) {
          try {
            if (!bluetooth_agent->IsActive()) {
              safe_reply(
                  "WriteDescriptorValue", result,
                  create_flutter_error(
                      UniversalBleErrorCode::kDeviceDisconnected,
                      "Device disconnected during descriptor write"));
              return;
            }
            if (desc_args != AsyncStatus::Completed) {
              safe_reply(
                  "WriteDescriptorValue", result,
                  create_flutter_error(
                      UniversalBleErrorCode::kFailed,
                      desc_args == AsyncStatus::Canceled ? "Write descriptor was cancelled"
                                                         : "Write descriptor failed"));
              return;
            }
            const auto desc_result = desc_sender.GetResults();
            if (desc_result.Status() != GattCommunicationStatus::Success) {
              safe_reply(
                  "WriteDescriptorValue", result,
                  create_flutter_error_from_gatt_communication_status(
                      desc_result.Status()));
              return;
            }
            if (desc_result.Descriptors().Size() == 0) {
              safe_reply("WriteDescriptorValue", result,
                         create_flutter_error(UniversalBleErrorCode::kFailed,
                                             "Descriptor not found:" + descriptor));
              return;
            }
            const auto gatt_descriptor = desc_result.Descriptors().GetAt(0);
            gatt_descriptor.WriteValueAsync(from_bytevc(value))
                .Completed([bluetooth_agent, gatt_characteristic_lease,
                            device_id, service, characteristic, descriptor,
                            result](
                               IAsyncOperation<GattCommunicationStatus> const &sender,
                               AsyncStatus const args) {
                  try {
                    if (!bluetooth_agent->IsActive()) {
                      safe_reply(
                          "WriteDescriptorValue", result,
                          create_flutter_error(
                              UniversalBleErrorCode::kDeviceDisconnected,
                              "Device disconnected during descriptor write"));
                      return;
                    }
                    if (args != AsyncStatus::Completed) {
                      safe_reply(
                          "WriteDescriptorValue", result,
                          create_flutter_error(
                              UniversalBleErrorCode::kFailed,
                              args == AsyncStatus::Canceled ? "Write descriptor was cancelled"
                                                            : "Write descriptor failed"));
                      return;
                    }

                    const auto status = sender.GetResults();
                    if (status != GattCommunicationStatus::Success) {
                      safe_reply("WriteDescriptorValue", result,
                                 create_flutter_error_from_gatt_communication_status(status));
                    } else {
                      if (!bluetooth_agent->IsActive()) {
                        safe_reply(
                            "WriteDescriptorValue", result,
                            create_flutter_error(
                                UniversalBleErrorCode::kDeviceDisconnected,
                                "Device disconnected during descriptor write"));
                        return;
                      }
                      safe_reply("WriteDescriptorValue", result, std::nullopt);
                    }
                  } catch (const hresult_error &err) {
                    safe_reply("WriteDescriptorValue", result,
                               create_flutter_error(UniversalBleErrorCode::kFailed,
                                                    to_string(err.message()),
                                                    std::to_string(err.code())));
                  } catch (...) {
                    safe_reply("WriteDescriptorValue", result, create_flutter_unknown_error());
                  }
                });
          } catch (const hresult_error &err) {
            safe_reply("WriteDescriptorValue", result,
                       create_flutter_error(UniversalBleErrorCode::kFailed,
                                            to_string(err.message()),
                                            std::to_string(err.code())));
          } catch (...) {
            safe_reply("WriteDescriptorValue", result, create_flutter_unknown_error());
          }
        });
  } catch (const FlutterError &err) {
    return result(err);
  } catch (...) {
    return result(create_flutter_unknown_error());
  }
}

void UniversalBlePlugin::RequestMtu(
    const std::string &device_id, int64_t expected_mtu,
    std::function<void(ErrorOr<int64_t> reply)> result) {
  UniversalBleLogger::LogDebugWithTimestamp(
      "REQUEST_MTU -> " + device_id +
      " expected=" + std::to_string(expected_mtu));
  try {
    const auto bluetooth_agent =
        GetConnectedDevice(str_to_mac_address(device_id));
    if (!bluetooth_agent) {
      result(create_flutter_error(UniversalBleErrorCode::kDeviceNotFound,
                                  "Unknown devicesId:" + device_id));
      return;
    }
    GattSession::FromDeviceIdAsync(bluetooth_agent->device.BluetoothDeviceId())
        .Completed([bluetooth_agent, result](IAsyncOperation<GattSession> const &sender,
                            AsyncStatus const args) {
          try {
            if (!bluetooth_agent->IsActive()) {
              safe_reply(
                  "RequestMtu", result,
                  create_flutter_error(UniversalBleErrorCode::kDeviceDisconnected,
                                       "Device disconnected during MTU query"));
              return;
            }
            if (args != AsyncStatus::Completed) {
              safe_reply(
                  "RequestMtu", result,
                  create_flutter_error(
                      UniversalBleErrorCode::kFailed,
                      args == AsyncStatus::Canceled
                          ? "MTU request was cancelled"
                          : "MTU request failed"));
              return;
            }

            const auto mtu =
                static_cast<int64_t>(sender.GetResults().MaxPduSize());
            if (!bluetooth_agent->IsActive()) {
              safe_reply(
                  "RequestMtu", result,
                  create_flutter_error(
                      UniversalBleErrorCode::kDeviceDisconnected,
                      "Device disconnected during MTU query"));
              return;
            }
            safe_reply("RequestMtu", result, mtu);
          } catch (const hresult_error &err) {
            safe_reply("RequestMtu", result,
                       create_flutter_error(UniversalBleErrorCode::kFailed,
                                            to_string(err.message()),
                                            std::to_string(err.code())));
          } catch (...) {
            UniversalBleLogger::LogError(
                "RequestMtu completion unknown exception");
            safe_reply("RequestMtu", result, create_flutter_unknown_error());
          }
        });
  } catch (const FlutterError &err) {
    result(err);
  }
}

void UniversalBlePlugin::RequestConnectionPriority(
    const std::string &device_id, const BleConnectionPriority &priority,
    std::function<void(std::optional<FlutterError> reply)> result) {
  result(create_flutter_error(
      UniversalBleErrorCode::kNotSupported,
      "requestConnectionPriority is not supported on Windows platform"));
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
  const auto callback = callback_operations_.TryAcquire();
  if (!callback.has_value()) co_return;
  try {
    const auto radios = co_await Radio::GetRadiosAsync();
    for (auto &&radio : radios) {
      if (radio.Kind() == RadioKind::Bluetooth) {
        bluetooth_radio_ = radio;
        const auto callback_operations = callback_operations_;
        radio_state_changed_revoker_ = bluetooth_radio_.StateChanged(
            auto_revoke,
            [this, callback_operations](const auto &sender, const auto &args) {
              const auto callback = callback_operations.TryAcquire();
              if (!callback.has_value()) return;
              RadioStateChanged(sender, args);
            });
        RadioStateChanged(bluetooth_radio_, nullptr);
        break;
      }
    }
  } catch (const hresult_error &err) {
    UniversalBleLogger::LogError(
        "Bluetooth initialization hresult_error hr=" +
        std::to_string(err.code()) + " msg=" + to_string(err.message()));
  } catch (const std::exception &ex) {
    log_and_swallow("Bluetooth initialization std::exception", ex);
  } catch (...) {
    log_and_swallow_unknown("Bluetooth initialization");
  }
  if (!bluetooth_radio_) {
    UniversalBleLogger::LogError("Bluetooth is not available");
    ui_thread_handler_.Post([] {
      callback_channel->OnAvailabilityChanged(AvailabilityState::kUnsupported,
                                              SuccessCallback, ErrorCallback);
    });
  }
  initialized_ = true;
}

fire_and_forget UniversalBlePlugin::PairAsync(
    const std::string &device_id,
    const std::function<void(ErrorOr<bool> reply)> result) {
  const auto callback = callback_operations_.TryAcquire();
  if (!callback.has_value()) co_return;
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
  const auto callback = callback_operations_.TryAcquire();
  if (!callback.has_value()) co_return;
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
      const auto pairing_requested_revoker = custom_pairing.PairingRequested(
          auto_revoke,
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
  UniversalBleLogger::LogInfo("PairLog: Got PIN from user");
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
  const auto callback_operations = callback_operations_;
  device_watcher_added_token_ = device_watcher_.Added(
      [this, callback_operations](DeviceWatcher sender,
                                  const DeviceInformation &device_info) {
        const auto callback = callback_operations.TryAcquire();
        if (!callback.has_value()) return;
        try {
          const auto properties = device_info.Properties();
          if (!properties.HasKey(device_address_key)) {
            return;
          }
          const auto device_address_property_value = lookup_i_property_value(
              properties, device_address_key, "DeviceAddress",
              "DeviceWatcher.Added");
          if (!device_address_property_value) {
            return;
          }
          const auto device_address =
              to_string(device_address_property_value.GetString());
          const std::string device_info_id = to_string(device_info.Id());
          // Map Id -> MAC and MAC -> DeviceInformation
          device_watcher_id_to_mac_.insert_or_assign(device_info_id,
                                                     device_address);
          device_watcher_devices_.insert_or_assign(device_address,
                                                   device_info);
          OnDeviceInfoReceived(device_info);
        } catch (const std::exception &ex) {
          log_and_swallow("DeviceWatcher.Added std::exception", ex);
        } catch (...) {
          log_and_swallow_unknown("DeviceWatcher.Added");
        }
      });

  // Update only if device is already discovered in deviceWatcher.Added
  device_watcher_updated_token_ = device_watcher_.Updated(
      [this, callback_operations](DeviceWatcher sender,
             const DeviceInformationUpdate &device_info_update) {
        const auto callback = callback_operations.TryAcquire();
        if (!callback.has_value()) return;
        try {
          const std::string device_info_id =
              to_string(device_info_update.Id());
          // Resolve MAC from Id
          const auto mac_lookup =
              device_watcher_id_to_mac_.get(device_info_id);
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
        } catch (const std::exception &ex) {
          log_and_swallow("DeviceWatcher.Updated std::exception", ex);
        } catch (...) {
          log_and_swallow_unknown("DeviceWatcher.Updated");
        }
      });

  device_watcher_removed_token_ = device_watcher_.Removed(
      [this, callback_operations](DeviceWatcher sender,
                                  const DeviceInformationUpdate &args) {
        const auto callback = callback_operations.TryAcquire();
        if (!callback.has_value()) return;
        try {
          const std::string device_id = to_string(args.Id());
          const auto mac_lookup = device_watcher_id_to_mac_.get(device_id);
          if (mac_lookup.has_value()) {
            const std::string mac_key = mac_lookup.value();
            device_watcher_devices_.remove(mac_key);
            device_watcher_id_to_mac_.remove(device_id);
          }
        } catch (const std::exception &ex) {
          log_and_swallow("DeviceWatcher.Removed std::exception", ex);
        } catch (...) {
          log_and_swallow_unknown("DeviceWatcher.Removed");
        }
      });

  device_watcher_enumeration_completed_token_ =
      device_watcher_.EnumerationCompleted([this, callback_operations](
                                                DeviceWatcher sender,
                                                IInspectable args) {
        const auto callback = callback_operations.TryAcquire();
        if (!callback.has_value()) return;
        UniversalBleLogger::LogInfo("DeviceWatcherEvent: EnumerationCompleted");
        DisposeDeviceWatcher();
        // EnumerationCompleted
      });

  device_watcher_stopped_token_ =
      device_watcher_.Stopped([this, callback_operations](DeviceWatcher sender,
                                                          IInspectable args) {
        const auto callback = callback_operations.TryAcquire();
        if (!callback.has_value()) return;
        // std::cout << "DeviceWatcherEvent: Stopped" << std::endl;
        //  disposeDeviceWatcher();
        // DeviceWatcher Stopped
      });
}

void UniversalBlePlugin::DisposeDeviceWatcher() {
  const auto watcher = device_watcher_;
  device_watcher_ = nullptr;
  if (watcher != nullptr) {
    try {
      watcher.Added(device_watcher_added_token_);
    } catch (...) {
      log_and_swallow_unknown("DisposeDeviceWatcher Added");
    }
    try {
      watcher.Updated(device_watcher_updated_token_);
    } catch (...) {
      log_and_swallow_unknown("DisposeDeviceWatcher Updated");
    }
    try {
      watcher.Removed(device_watcher_removed_token_);
    } catch (...) {
      log_and_swallow_unknown("DisposeDeviceWatcher Removed");
    }
    try {
      watcher.EnumerationCompleted(
          device_watcher_enumeration_completed_token_);
    } catch (...) {
      log_and_swallow_unknown("DisposeDeviceWatcher EnumerationCompleted");
    }
    try {
      watcher.Stopped(device_watcher_stopped_token_);
    } catch (...) {
      log_and_swallow_unknown("DisposeDeviceWatcher Stopped");
    }
    try {
      if (watcher.Status() == DeviceWatcherStatus::Started) {
        watcher.Stop();
      }
    } catch (...) {
      log_and_swallow_unknown("DisposeDeviceWatcher Stop");
    }
  }
  device_watcher_devices_.clear();
  device_watcher_id_to_mac_.clear();
}

void UniversalBlePlugin::OnDeviceInfoReceived(
    const DeviceInformation &device_info) {
  const auto properties = device_info.Properties();

  // Avoid devices if not connectable or if deviceAddressKey is not present
  if (!properties.HasKey(is_connectable_key) || !properties.HasKey(device_address_key)) {
    return;
  }

  const auto is_connectable_property_value = lookup_i_property_value(
      properties, is_connectable_key, "IsConnectable", "OnDeviceInfoReceived");
  if (!is_connectable_property_value ||
      !is_connectable_property_value.GetBoolean()) {
    return;
  }

  const auto bluetooth_address_property_value = lookup_i_property_value(
      properties, device_address_key, "DeviceAddress", "OnDeviceInfoReceived");
  if (!bluetooth_address_property_value) {
    return;
  }

  const std::string device_address = to_string(bluetooth_address_property_value.GetString());

  // Update device info if already discovered in advertisementWatcher
  if (scan_results_.get(device_address).has_value()) {
    bool is_paired = device_info.Pairing().IsPaired();
    if (properties.HasKey(is_paired_key)) {
      const auto is_paired_property_value = lookup_i_property_value(
          properties, is_paired_key, "IsPaired", "OnDeviceInfoReceived");
      if (is_paired_property_value) {
        is_paired = is_paired_property_value.GetBoolean();
      }
    }

    UniversalBleScanResult universal_scan_result(device_address);
    universal_scan_result.set_is_paired(is_paired);

    if (!device_info.Name().empty())
      universal_scan_result.set_name(to_string(device_info.Name()));

    if (properties.HasKey(signal_strength_key)) {
      const auto rssi_property_value = lookup_i_property_value(
          properties, signal_strength_key, "SignalStrength",
          "OnDeviceInfoReceived");
      if (rssi_property_value) {
        const int16_t rssi = rssi_property_value.GetInt16();
        universal_scan_result.set_rssi(rssi);
      }
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
      if (properties.HasKey(is_paired_key)) {
        const auto is_paired_property_value = lookup_i_property_value(
            properties, is_paired_key, "IsPaired", "BluetoothLeWatcherReceived");
        if (is_paired_property_value) {
          is_paired = is_paired_property_value.GetBoolean();
        }
      }
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
  try {
    const auto radio_state = !sender ? RadioState::Disabled : sender.State();
    if (old_radio_state_ == radio_state) {
      return;
    }
    old_radio_state_ = radio_state;
    auto state = get_availability_state_from_radio(radio_state);

    ui_thread_handler_.Post([state] {
      callback_channel->OnAvailabilityChanged(state, SuccessCallback,
                                              ErrorCallback);
    });
  } catch (const hresult_error &err) {
    UniversalBleLogger::LogError(
        "RadioStateChanged hresult_error hr=" +
        std::to_string(err.code()) + " msg=" + to_string(err.message()));
  } catch (const std::exception &ex) {
    log_and_swallow("RadioStateChanged std::exception", ex);
  } catch (...) {
    log_and_swallow_unknown("RadioStateChanged");
  }
}

void UniversalBlePlugin::NotifyConnectionChanged(
    const uint64_t bluetooth_address, const bool connected,
    std::optional<std::string> error) {
  ui_thread_handler_.Post([bluetooth_address, connected,
                           error = std::move(error)] {
    const std::string *error_ptr = error.has_value() ? &error.value() : nullptr;
    callback_channel->OnConnectionChanged(mac_address_to_str(bluetooth_address),
                                          connected, error_ptr, SuccessCallback,
                                          ErrorCallback);
  });
}

void UniversalBlePlugin::NotifyConnectionException(
    const uint64_t bluetooth_address, const std::string &error_message,
    const BluetoothLEDevice *expected_device) {
  UniversalBleLogger::LogError(error_message);
  if (bluetooth_address != 0) {
    if (expected_device == nullptr) {
      CleanConnection(bluetooth_address);
      NotifyConnectionChanged(bluetooth_address, false, error_message);
    } else if (CleanConnection(bluetooth_address, expected_device)) {
      NotifyConnectionChanged(bluetooth_address, false, error_message);
    } else {
      UniversalBleLogger::LogDebug(
          "Ignoring exception from stale Bluetooth device instance");
    }
  }
}

fire_and_forget UniversalBlePlugin::ConnectAsync(
    uint64_t bluetooth_address, uint64_t connect_generation) {
  const auto callback = callback_operations_.TryAcquire();
  if (!callback.has_value()) co_return;
  BluetoothLEDevice device{nullptr};
  std::unordered_map<std::string, GattServiceObject> gatt_map;
  std::optional<event_token> connection_status_changed_token;
  std::optional<event_token> gatt_services_changed_token;
  std::shared_ptr<BluetoothDeviceAgent> device_agent;
  const auto dispose_partial_connection = [&]() noexcept {
    try {
      if (device_agent) {
        CleanConnection(bluetooth_address, &device);
        DisposeConnection(device_agent);
        return;
      }
      if (device) {
        if (connection_status_changed_token.has_value()) {
          device.ConnectionStatusChanged(
              connection_status_changed_token.value());
        }
        if (gatt_services_changed_token.has_value()) {
          device.GattServicesChanged(gatt_services_changed_token.value());
        }
      }
      DisposeGattMap(std::move(gatt_map));
      if (device) {
        device.Close();
      }
    } catch (...) {
      log_and_swallow_unknown("ConnectAsync partial cleanup");
    }
  };
  try {
    device = co_await BluetoothLEDevice::FromBluetoothAddressAsync(
        bluetooth_address);
    if (!device) {
      NotifyConnectFailureIfCurrent(bluetooth_address, connect_generation,
                                    "Failed to get device");
      co_return;
    }
    UniversalBleLogger::LogInfo("ConnectionLog: Device found");
    auto services_result =
        co_await device.GetGattServicesAsync((BluetoothCacheMode::Uncached));
    auto services_result_error =
        gatt_communication_status_to_error(services_result.Status());
    if (services_result_error.has_value()) {
      try {
        device.Close();
      } catch (...) {
        log_and_swallow_unknown("ConnectAsync failed-service-query close");
      }
      NotifyConnectFailureIfCurrent(
          bluetooth_address, connect_generation,
          "Failed to get services: " + services_result_error.value());
      co_return;
    }

    UniversalBleLogger::LogInfo("ConnectionLog: Services discovered");
    std::optional<std::string> gatt_discovery_error;
    auto gatt_services = services_result.Services();
    for (GattDeviceService &&service : gatt_services) {
      try {
        GattServiceObject gatt_service;
        gatt_service.obj = service;
        std::string service_uuid = guid_to_uuid(service.Uuid());
        auto characteristics_result = co_await service.GetCharacteristicsAsync(
            BluetoothCacheMode::Uncached);
        auto characteristics_result_error =
            gatt_communication_status_to_error(characteristics_result.Status());

        if (characteristics_result_error.has_value()) {
          gatt_discovery_error =
              "Failed to get characteristics for service " + service_uuid +
              ": " + characteristics_result_error.value();
          break;
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
      } catch (const hresult_error &err) {
        gatt_discovery_error =
            "Service discovery hresult_error hr=" +
            std::to_string(err.code()) + " msg=" + to_string(err.message());
        break;
      } catch (const std::exception &ex) {
        gatt_discovery_error =
            std::string("Service discovery exception: ") + ex.what();
        break;
      } catch (...) {
        gatt_discovery_error = "Service discovery unknown error";
        break;
      }
    }

    if (gatt_discovery_error.has_value()) {
      DisposeGattMap(std::move(gatt_map));
      try {
        device.Close();
      } catch (...) {
        log_and_swallow_unknown("ConnectAsync failed-discovery close");
      }
      NotifyConnectFailureIfCurrent(bluetooth_address, connect_generation,
                                    gatt_discovery_error.value());
      co_return;
    }

    const auto connection_callback_operations = callback_operations_;
    connection_status_changed_token = device.ConnectionStatusChanged(
        [this, connection_callback_operations](
            const BluetoothLEDevice &sender, const IInspectable &args) {
          const auto callback = connection_callback_operations.TryAcquire();
          if (!callback.has_value()) return;
          BluetoothLeDeviceConnectionStatusChanged(sender, args);
        });
    const auto services_callback_operations = callback_operations_;
    gatt_services_changed_token = device.GattServicesChanged(
        [this, services_callback_operations](
            const BluetoothLEDevice &sender, const IInspectable &args) {
          const auto callback = services_callback_operations.TryAcquire();
          if (!callback.has_value()) {
            return;
          }
          BluetoothLeDeviceGattServicesChanged(sender, args);
        });
    device_agent = std::make_shared<BluetoothDeviceAgent>(
        device, connection_status_changed_token.value(),
        gatt_services_changed_token.value(), std::move(gatt_map));
    std::shared_ptr<BluetoothDeviceAgent> previous_device_agent;
    if (!InstallConnectedDevice(bluetooth_address, connect_generation,
                                device_agent, previous_device_agent)) {
      DisposeConnection(device_agent);
      co_return;
    }
    DisposeConnection(previous_device_agent);
    if (NotifyConnectedIfCurrent(bluetooth_address, connect_generation,
                                 device)) {
      UniversalBleLogger::LogInfo("ConnectionLog: Connected");
    } else if (CleanConnection(bluetooth_address, &device)) {
      NotifyConnectionChanged(bluetooth_address, false,
                              std::string("Device disconnected while connecting"));
    }
  } catch (const hresult_error &err) {
    dispose_partial_connection();
    NotifyConnectFailureIfCurrent(
        bluetooth_address, connect_generation,
        "ConnectAsync hresult_error hr=" + std::to_string(err.code()) +
            " msg=" + to_string(err.message()));
  } catch (const std::exception &ex) {
    dispose_partial_connection();
    NotifyConnectFailureIfCurrent(
        bluetooth_address, connect_generation,
        std::string("ConnectAsync std::exception: ") + ex.what());
  } catch (...) {
    dispose_partial_connection();
    NotifyConnectFailureIfCurrent(bluetooth_address, connect_generation,
                                  "ConnectAsync unknown exception");
  }
}

fire_and_forget UniversalBlePlugin::RefreshGattServicesAsync(
    const uint64_t bluetooth_address,
    std::shared_ptr<BluetoothDeviceAgent> device_agent) {
  const auto callback = callback_operations_.TryAcquire();
  if (!callback.has_value()) {
    device_agent->FinishGattRefresh();
    co_return;
  }
  while (true) {
    bool refreshed = false;
    try {
      const auto current = GetConnectedDevice(bluetooth_address);
      if (!current || current != device_agent) {
        device_agent->FinishGattRefresh();
        co_return;
      }

      auto subscriptions = device_agent->SnapshotSubscriptions();
      while (!subscriptions.has_value()) {
        if (!device_agent->IsActive()) {
          device_agent->FinishGattRefresh();
          co_return;
        }
        // A CCC operation is changing the subscription map. Yield instead of
        // blocking its WinRT continuation, then take one coherent snapshot.
        co_await winrt::resume_after(std::chrono::milliseconds(10));
        subscriptions = device_agent->SnapshotSubscriptions();
      }

      // Characteristics returned to an in-flight read, write, or discovery
      // belong to the current service map. Do not Close that map underneath
      // the WinRT operation; refreshes are rare, so waiting here preserves
      // ordinary-operation concurrency without globally serializing GATT.
      while (!device_agent->gatt_operations.IsIdle()) {
        if (!device_agent->IsActive()) {
          device_agent->FinishGattRefresh();
          co_return;
        }
        co_await winrt::resume_after(std::chrono::milliseconds(10));
      }

      // Microsoft specifies Cached here after GattServicesChanged. Windows
      // refreshes its cache as part of processing the Service Changed
      // indication; using Uncached can race that processing and return a
      // transient or incomplete database.
      const auto services_result = co_await device_agent->device
                                       .GetGattServicesAsync(
                                           BluetoothCacheMode::Cached);
      const auto services_error =
          gatt_communication_status_to_error(services_result.Status());
      if (services_error.has_value()) {
        UniversalBleLogger::LogError(
            "GATT service refresh failed: " + services_error.value());
      } else {
        std::unordered_map<std::string, GattServiceObject> replacement;
        std::optional<std::string> discovery_error;
        for (GattDeviceService &&service : services_result.Services()) {
          GattServiceObject gatt_service;
          gatt_service.obj = service;
          const auto service_uuid = guid_to_uuid(service.Uuid());
          const auto characteristics_result =
              co_await service.GetCharacteristicsAsync(
                  BluetoothCacheMode::Cached);
          const auto characteristics_error =
              gatt_communication_status_to_error(
                  characteristics_result.Status());
          if (characteristics_error.has_value()) {
            discovery_error =
                "Failed to refresh characteristics for service " +
                service_uuid + ": " + characteristics_error.value();
            break;
          }
          for (GattCharacteristic &&characteristic :
               characteristics_result.Characteristics()) {
            GattCharacteristicObject gatt_characteristic;
            gatt_characteristic.obj = characteristic;
            gatt_service.characteristics.insert_or_assign(
                guid_to_uuid(characteristic.Uuid()),
                std::move(gatt_characteristic));
          }
          replacement.insert_or_assign(service_uuid,
                                       std::move(gatt_service));
        }

        if (discovery_error.has_value()) {
          UniversalBleLogger::LogError(discovery_error.value());
          const auto retained_services = device_agent->SnapshotGattServices();
          DisposeGattMap(std::move(replacement), &retained_services);
        } else {
          try {
            const auto device_id = mac_address_to_str(bluetooth_address);
            for (const auto &[service_id, characteristic_id] :
                 subscriptions->characteristics) {
              const auto service = replacement.find(service_id);
              if (service == replacement.end()) {
                continue;
              }
              const auto characteristic =
                  service->second.characteristics.find(characteristic_id);
              if (characteristic == service->second.characteristics.end()) {
                continue;
              }
              characteristic->second.subscription_token =
                  RegisterGattValueChangedHandler(
                      device_agent, device_id, characteristic_id,
                      characteristic->second.obj);
            }
          } catch (...) {
            const auto retained_services = device_agent->SnapshotGattServices();
            DisposeGattMap(std::move(replacement), &retained_services);
            throw;
          }

          const auto still_current = GetConnectedDevice(bluetooth_address);
          if (!still_current || still_current != device_agent) {
            const auto retained_services = device_agent->SnapshotGattServices();
            DisposeGattMap(std::move(replacement), &retained_services);
            device_agent->FinishGattRefresh();
            co_return;
          }
          std::vector<GattDeviceService> retained_services;
          retained_services.reserve(replacement.size());
          for (const auto &[service_id, service] : replacement) {
            (void)service_id;
            retained_services.push_back(service.obj);
          }
          std::unordered_map<std::string, GattServiceObject> previous;
          if (device_agent->ReplaceGattMapIfUnchanged(
                  replacement, subscriptions->revision, previous)) {
            DisposeGattMap(std::move(previous), &retained_services);
            refreshed = true;
          } else {
            // A subscribe/unsubscribe or disconnect overlapped discovery.
            // Never install a map built from stale subscription state.
            const auto current_services = device_agent->SnapshotGattServices();
            DisposeGattMap(std::move(replacement), &current_services);
            device_agent->RequestGattRefresh();
          }
        }
      }
    } catch (const hresult_error &err) {
      UniversalBleLogger::LogError(
          "RefreshGattServicesAsync hresult_error hr=" +
          std::to_string(err.code()) + " msg=" + to_string(err.message()));
    } catch (const std::exception &ex) {
      log_and_swallow("RefreshGattServicesAsync std::exception", ex);
    } catch (...) {
      log_and_swallow_unknown("RefreshGattServicesAsync");
    }

    const bool repeat = device_agent->FinishGattRefresh();
    if (!repeat) {
      if (refreshed) {
        UniversalBleLogger::LogInfo("GATT services refreshed after change");
      }
      co_return;
    }
  }
}

void UniversalBlePlugin::BluetoothLeDeviceConnectionStatusChanged(
    const BluetoothLEDevice &sender, const IInspectable &) {
  try {
    const auto bluetooth_address = sender.BluetoothAddress();
    if (sender.ConnectionStatus() == BluetoothConnectionStatus::Disconnected) {
      if (CleanConnection(bluetooth_address, &sender)) {
        NotifyConnectionChanged(bluetooth_address, false, std::nullopt);
      } else {
        UniversalBleLogger::LogDebug(
            "Ignoring stale connection status callback");
      }
    }
  } catch (const hresult_error &err) {
    UniversalBleLogger::LogError(
        "ConnectionStatusChanged hresult_error hr=" +
        std::to_string(err.code()) + " msg=" + to_string(err.message()));
  } catch (const std::exception &ex) {
    log_and_swallow("ConnectionStatusChanged std::exception", ex);
  } catch (...) {
    log_and_swallow_unknown("ConnectionStatusChanged");
  }
}

void UniversalBlePlugin::BluetoothLeDeviceGattServicesChanged(
    const BluetoothLEDevice &sender, const IInspectable &) {
  try {
    const auto bluetooth_address = sender.BluetoothAddress();
    const auto device_agent = GetConnectedDevice(bluetooth_address);
    if (!device_agent || device_agent->device != sender) {
      UniversalBleLogger::LogDebug(
          "Ignoring GATT services change from stale Bluetooth device instance");
      return;
    }
    if (device_agent->BeginGattRefresh()) {
      RefreshGattServicesAsync(bluetooth_address, device_agent);
    }
  } catch (const hresult_error &err) {
    UniversalBleLogger::LogError(
        "GattServicesChanged hresult_error hr=" +
        std::to_string(err.code()) + " msg=" + to_string(err.message()));
  } catch (const std::exception &ex) {
    log_and_swallow("GattServicesChanged std::exception", ex);
  } catch (...) {
    log_and_swallow_unknown("GattServicesChanged");
  }
}

std::shared_ptr<BluetoothDeviceAgent>
UniversalBlePlugin::GetConnectedDevice(const uint64_t bluetooth_address) {
  std::lock_guard<std::mutex> lock(connected_devices_mutex_);
  const auto it = connected_devices_.find(bluetooth_address);
  return it == connected_devices_.end() ? nullptr : it->second;
}

std::optional<uint64_t>
UniversalBlePlugin::BeginConnectAttempt(const uint64_t bluetooth_address) {
  std::lock_guard<std::mutex> lock(connected_devices_mutex_);
  if (pending_connects_.find(bluetooth_address) != pending_connects_.end()) {
    return std::nullopt;
  }
  const auto generation = ++next_connect_generation_;
  connect_generations_.insert_or_assign(bluetooth_address, generation);
  pending_connects_.insert(bluetooth_address);
  return generation;
}

void UniversalBlePlugin::InvalidateConnectAttempt(
  const uint64_t bluetooth_address) {
  std::lock_guard<std::mutex> lock(connected_devices_mutex_);
  pending_connects_.erase(bluetooth_address);
  connect_generations_.insert_or_assign(bluetooth_address,
                                        ++next_connect_generation_);
}

std::shared_ptr<BluetoothDeviceAgent>
UniversalBlePlugin::RemoveConnectedDevice(
    const uint64_t bluetooth_address,
    const BluetoothLEDevice *expected_device) {
  std::lock_guard<std::mutex> lock(connected_devices_mutex_);
  const auto it = connected_devices_.find(bluetooth_address);
  if (it == connected_devices_.end() ||
      (expected_device != nullptr && it->second->device != *expected_device)) {
    return nullptr;
  }
  const auto device_agent = it->second;
  connected_devices_.erase(it);
  return device_agent;
}

bool
UniversalBlePlugin::InstallConnectedDevice(
    const uint64_t bluetooth_address,
    const uint64_t connect_generation,
    std::shared_ptr<BluetoothDeviceAgent> device_agent,
    std::shared_ptr<BluetoothDeviceAgent> &previous_device_agent) {
  std::lock_guard<std::mutex> lock(connected_devices_mutex_);
  const auto generation = connect_generations_.find(bluetooth_address);
  if (generation == connect_generations_.end() ||
      generation->second != connect_generation) {
    return false;
  }
  pending_connects_.erase(bluetooth_address);
  const auto it = connected_devices_.find(bluetooth_address);
  if (it != connected_devices_.end()) {
    previous_device_agent = it->second;
  }
  connected_devices_.insert_or_assign(bluetooth_address,
                                      std::move(device_agent));
  return true;
}

bool UniversalBlePlugin::NotifyConnectedIfCurrent(
    const uint64_t bluetooth_address, const uint64_t connect_generation,
    const BluetoothLEDevice &expected_device) {
  std::lock_guard<std::mutex> lock(connected_devices_mutex_);
  const auto generation = connect_generations_.find(bluetooth_address);
  const auto device_agent = connected_devices_.find(bluetooth_address);
  if (generation == connect_generations_.end() ||
      generation->second != connect_generation ||
      device_agent == connected_devices_.end() ||
      device_agent->second->device != expected_device ||
      expected_device.ConnectionStatus() !=
          BluetoothConnectionStatus::Connected) {
    return false;
  }
  NotifyConnectionChanged(bluetooth_address, true, std::nullopt);
  return true;
}

void UniversalBlePlugin::NotifyConnectFailureIfCurrent(
    const uint64_t bluetooth_address, const uint64_t connect_generation,
    const std::string &error_message) noexcept {
  try {
    UniversalBleLogger::LogError(error_message);
    std::lock_guard<std::mutex> lock(connected_devices_mutex_);
    const auto generation = connect_generations_.find(bluetooth_address);
    if (generation != connect_generations_.end() &&
        generation->second == connect_generation) {
      pending_connects_.erase(bluetooth_address);
      NotifyConnectionChanged(bluetooth_address, false, error_message);
    } else {
      UniversalBleLogger::LogDebug(
          "Ignoring failure from stale connection attempt");
    }
  } catch (...) {
    try {
      UniversalBleLogger::LogError(
          "Failed to publish connection-attempt failure");
    } catch (...) {
    }
  }
}

bool UniversalBlePlugin::CleanConnection(
    const uint64_t bluetooth_address,
    const BluetoothLEDevice *expected_device) {
  try {
    const auto device_agent =
        RemoveConnectedDevice(bluetooth_address, expected_device);
    if (!device_agent) {
      return false;
    }
    DisposeConnection(device_agent);
    return true;
  } catch (const hresult_error &err) {
    UniversalBleLogger::LogError("CleanConnection outer hresult_error: " +
                                 to_string(err.message()));
  } catch (const std::exception &ex) {
    log_and_swallow("CleanConnection std::exception", ex);
  } catch (...) {
    log_and_swallow_unknown("CleanConnection");
  }
  return false;
}

void UniversalBlePlugin::DisposeConnection(
    const std::shared_ptr<BluetoothDeviceAgent> &device_agent) {
  if (!device_agent || !device_agent->Deactivate()) {
    return;
  }
  try {
    device_agent->device.ConnectionStatusChanged(
        device_agent->connection_status_changed_token);
  } catch (const hresult_error &err) {
    UniversalBleLogger::LogError("DisposeConnection hresult_error: " +
                                 to_string(err.message()));
  } catch (...) {
    UniversalBleLogger::LogWarning(
        "DisposeConnection: failed to remove connection status handler");
  }
  try {
    device_agent->device.GattServicesChanged(
        device_agent->gatt_services_changed_token);
  } catch (const hresult_error &err) {
    UniversalBleLogger::LogError(
        "DisposeConnection GattServicesChanged hresult_error: " +
        to_string(err.message()));
  } catch (...) {
    UniversalBleLogger::LogWarning(
        "DisposeConnection: failed to remove GATT services handler");
  }
  DisposeServices(device_agent);
  try {
    device_agent->device.Close();
  } catch (const hresult_error &err) {
    UniversalBleLogger::LogError("DisposeConnection close hresult_error: " +
                                 to_string(err.message()));
  } catch (...) {
    UniversalBleLogger::LogWarning(
        "DisposeConnection: failed to close Bluetooth device");
  }
}

void UniversalBlePlugin::DisposeServices(
    const std::shared_ptr<BluetoothDeviceAgent> &device_agent) {
  DisposeGattMap(device_agent->TakeGattMap());
}

void UniversalBlePlugin::DisposeGattMap(
    std::unordered_map<std::string, GattServiceObject> gatt_map,
    const std::vector<GattDeviceService> *retained_services) {
  for (auto &[service_id, service] : gatt_map) {
    for (auto &[char_id, characteristic] : service.characteristics) {
      if (characteristic.subscription_token.has_value() &&
          !characteristic.notification_operation_in_progress) {
        try {
          characteristic.obj.ValueChanged(
              characteristic.subscription_token.value());
        } catch (const hresult_error &err) {
          UniversalBleLogger::LogError("DisposeServices hresult_error unsub " +
                                       to_string(err.message()));
        } catch (const std::exception &ex) {
          log_and_swallow("DisposeServices unsub std::exception", ex);
        } catch (...) {
          log_and_swallow_unknown("DisposeServices unsub");
        }
        characteristic.subscription_token = std::nullopt;
      }
    }
    const bool is_retained =
        retained_services != nullptr &&
        std::find(retained_services->begin(), retained_services->end(),
                  service.obj) != retained_services->end();
    if (!is_retained) {
      try {
        service.obj.Close();
      } catch (const hresult_error &err) {
        UniversalBleLogger::LogError("DisposeServices hresult_error close " +
                                     service_id + ": " +
                                     to_string(err.message()));
      } catch (const std::exception &ex) {
        log_and_swallow("DisposeServices close std::exception", ex);
      } catch (...) {
        log_and_swallow_unknown("DisposeServices close");
      }
    }
  }
}

/**
 * @brief In some cases, it helps to reset the whole Bluetooth state to get
 * rid of any dangling connections, before scanning or connecting.
 */
void UniversalBlePlugin::ResetState() {
  try {
    // Stop and detach advertisement watcher
    if (bluetooth_le_watcher_ != nullptr) {
      try {
        bluetooth_le_watcher_.Stop();
      } catch (...) {
        UniversalBleLogger::LogWarning("ResetState: failed to stop LE watcher");
      }
      try {
        bluetooth_le_watcher_.Received(bluetooth_le_watcher_received_token_);
      } catch (...) {
        log_and_swallow_unknown(
            "ResetState: failed to unregister LE watcher received handler");
      }
      bluetooth_le_watcher_ = nullptr;
    }

    // Dispose device watcher and caches
    DisposeDeviceWatcher();
    scan_results_.clear();
    device_watcher_devices_.clear();
    device_watcher_id_to_mac_.clear();

    // Close all connected devices and clear map
    std::vector<std::shared_ptr<BluetoothDeviceAgent>> device_agents;
    {
      std::lock_guard<std::mutex> lock(connected_devices_mutex_);
      device_agents.reserve(connected_devices_.size());
      for (const auto &entry : connected_devices_) {
        device_agents.push_back(entry.second);
      }
      connected_devices_.clear();
      connect_generations_.clear();
      pending_connects_.clear();
    }
    for (const auto &device_agent : device_agents) {
      DisposeConnection(device_agent);
    }

    UniversalBleLogger::LogInfo("ResetState: completed clean slate");
  } catch (const hresult_error &err) {
    UniversalBleLogger::LogError("ResetState hresult_error: " +
                                 to_string(err.message()));
  } catch (const std::exception &ex) {
    log_and_swallow("ResetState std::exception", ex);
  } catch (...) {
    log_and_swallow_unknown("ResetState");
  }
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
        bool include_device = true;
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
              }
            }
            include_device = has_service;
          } else {
            include_device = false;
          }
        }
        if (include_device) {
          // Add to results, if pass all filters
          auto universal_scan_result = UniversalBleScanResult(device_id);
          universal_scan_result.set_name(to_string(device_info.Name()));
          universal_scan_result.set_is_paired(device_info.Pairing().IsPaired());
          results.push_back(
              flutter::CustomEncodableValue(universal_scan_result));
        }
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
  const auto callback = callback_operations_.TryAcquire();
  if (!callback.has_value()) co_return;
  try {
    const auto device_agent =
        GetConnectedDevice(str_to_mac_address(device_id));
    if (!device_agent) {
      result(create_flutter_error(UniversalBleErrorCode::kDeviceNotFound,
                                  "Unknown devicesId:" + device_id));
      co_return;
    }

    const auto gatt_map_lease = device_agent->SnapshotGattMapForOperation();
    const auto &gatt_map = gatt_map_lease.map;
    auto universal_services = flutter::EncodableList();
    for (const auto &[service_id, service] : gatt_map) {
      flutter::EncodableList universal_characteristics;
      for (const auto &[char_id, characteristic] :
           service.characteristics) {
        const auto c = characteristic.obj;
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
    if (!device_agent->IsActive()) {
      result(create_flutter_error(UniversalBleErrorCode::kDeviceDisconnected,
                                  "Device disconnected during discovery"));
      co_return;
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
    std::string device_id, std::string service,
    std::string characteristic,
    BleInputProperty ble_input_property,
    const std::function<void(std::optional<FlutterError> reply)> result) {
  const auto callback = callback_operations_.TryAcquire();
  if (!callback.has_value()) co_return;
  const char *stage = "entry";
  const auto reply = [&result, &stage](
                         std::optional<FlutterError> response) noexcept {
    try {
      result(std::move(response));
    } catch (const hresult_error &err) {
      try {
        UniversalBleLogger::LogError(
            "SET_NOTIFY reply failed at stage=" + std::string(stage) +
            " hr=" + std::to_string(err.code()) +
            " msg=" + to_string(err.message()));
      } catch (...) {
      }
    } catch (const std::exception &err) {
      try {
        UniversalBleLogger::LogError(
            "SET_NOTIFY reply failed at stage=" + std::string(stage) +
            " exception=" + err.what());
      } catch (...) {
      }
    } catch (...) {
      try {
        UniversalBleLogger::LogError(
            "SET_NOTIFY reply failed at stage=" + std::string(stage) +
            " with unknown exception");
      } catch (...) {
      }
    }
  };
  bool notification_operation_started = false;
  std::optional<event_token> provisional_subscription_token;
  std::optional<event_token> previous_subscription_token;
  GattCharacteristic subscription_characteristic{nullptr};
  std::shared_ptr<BluetoothDeviceAgent> device_agent;
  try {
    UniversalBleLogger::LogDebugWithTimestamp(
        "SET_NOTIFY -> " + device_id + " " + service + " " +
        characteristic + " input=" +
        std::to_string(static_cast<int>(ble_input_property)));
    stage = "lookup-device";
    const auto device_address = str_to_mac_address(device_id);
    device_agent = GetConnectedDevice(device_address);
    if (!device_agent) {
      reply(create_flutter_error(UniversalBleErrorCode::kDeviceNotFound,
                                 "Unknown devicesId:" + device_id));
      co_return;
    }

    stage = "lookup-characteristic";
    auto gatt_char =
        device_agent->FetchCharacteristic(service, characteristic);

    const auto properties = gatt_char.obj.CharacteristicProperties();
    auto descriptor_value =
        GattClientCharacteristicConfigurationDescriptorValue::None;
    if (ble_input_property == BleInputProperty::kNotification) {
      descriptor_value =
          GattClientCharacteristicConfigurationDescriptorValue::Notify;
      if ((properties & GattCharacteristicProperties::Notify) ==
          GattCharacteristicProperties::None) {
        reply(create_flutter_error(
            UniversalBleErrorCode::kCharacteristicDoesNotSupportNotify,
            "Characteristic does not support notify"));
        co_return;
      }
    } else if (ble_input_property == BleInputProperty::kIndication) {
      descriptor_value =
          GattClientCharacteristicConfigurationDescriptorValue::Indicate;
      if ((properties & GattCharacteristicProperties::Indicate) ==
          GattCharacteristicProperties::None) {
        reply(create_flutter_error(
            UniversalBleErrorCode::kCharacteristicDoesNotSupportIndicate,
            "Characteristic does not support indicate"));
        co_return;
      }
    }

    if (!device_agent->BeginNotificationOperation(service, characteristic,
                                                   gatt_char)) {
      reply(create_flutter_error(
          UniversalBleErrorCode::kFailed,
          "Another notification operation is already running or the device "
          "was disconnected"));
      co_return;
    }
    notification_operation_started = true;

    const auto gatt_characteristic = gatt_char.obj;
    subscription_characteristic = gatt_characteristic;
    previous_subscription_token = gatt_char.subscription_token;

    // Install the native handler before enabling the CCC descriptor. A
    // peripheral is allowed to notify as soon as it processes the CCC write,
    // before the WinRT async operation completes. Registering afterwards loses
    // that first value.
    if (descriptor_value !=
            GattClientCharacteristicConfigurationDescriptorValue::None &&
        !previous_subscription_token.has_value()) {
      stage = "register-handler";
      provisional_subscription_token = std::make_optional(
          RegisterGattValueChangedHandler(device_agent, device_id,
                                          characteristic,
                                          gatt_characteristic));
      if (!device_agent->UpdateNotificationOperationToken(
              service, characteristic, provisional_subscription_token)) {
        gatt_characteristic.ValueChanged(
            provisional_subscription_token.value());
        provisional_subscription_token = std::nullopt;
        notification_operation_started = false;
        reply(create_flutter_error(UniversalBleErrorCode::kDeviceDisconnected,
                                   "Device disconnected while subscribing"));
        co_return;
      }
    }

    // Write to the descriptor.
    GattCommunicationStatus status{};
    try {
      stage = "write-descriptor";
      status = co_await gatt_characteristic
                   .WriteClientCharacteristicConfigurationDescriptorAsync(
                       descriptor_value);
    } catch (const hresult_error &err) {
      UniversalBleLogger::LogError(
          "SET_NOTIFY exception hr=" + std::to_string(err.code()) +
          " msg=" + to_string(err.message()) + " device=" + device_id +
          " service=" + service + " char=" + characteristic);
      if (provisional_subscription_token.has_value()) {
        try {
          gatt_characteristic.ValueChanged(
              provisional_subscription_token.value());
        } catch (...) {
        }
      }
      device_agent->FinishNotificationOperation(
          service, characteristic, previous_subscription_token);
      notification_operation_started = false;
      reply(create_flutter_error(UniversalBleErrorCode::kFailed,
                                 "SetNotifiable exception: " +
                                     to_string(err.message()),
                                 "hr=" + std::to_string(err.code())));
      co_return;
    }
    stage = "descriptor-completed";
    if (status != GattCommunicationStatus::Success) {
      UniversalBleLogger::LogError("SET_NOTIFY_FAILED <- " + device_id + " " +
                                   service + " " + characteristic + " status=" +
                                   std::to_string(static_cast<int>(status)));
      if (provisional_subscription_token.has_value()) {
        try {
          gatt_characteristic.ValueChanged(
              provisional_subscription_token.value());
        } catch (...) {
        }
      }
      device_agent->FinishNotificationOperation(
          service, characteristic, previous_subscription_token);
      notification_operation_started = false;
      reply(create_flutter_error_from_gatt_communication_status(status));
      co_return;
    }

    // Register/unregister the ValueChanged handler without retaining a
    // reference into the agent's GATT map across the co_await above.
    if (descriptor_value ==
        GattClientCharacteristicConfigurationDescriptorValue::None) {
      if (previous_subscription_token.has_value()) {
        stage = "remove-handler";
        gatt_characteristic.ValueChanged(previous_subscription_token.value());
        UniversalBleLogger::LogInfo("Unsubscribed " +
                                    to_uuidstr(gatt_characteristic.Uuid()));
      }
      stage = "store-unsubscribe-token";
      if (!device_agent->FinishNotificationOperation(
              service, characteristic, std::nullopt)) {
        reply(create_flutter_error(UniversalBleErrorCode::kDeviceDisconnected,
                                   "Device disconnected while unsubscribing"));
        notification_operation_started = false;
        co_return;
      }
      notification_operation_started = false;
    } else {
      const auto active_token = provisional_subscription_token.has_value()
                                    ? provisional_subscription_token
                                    : previous_subscription_token;
      if (!device_agent->FinishNotificationOperation(
              service, characteristic, active_token)) {
        stage = "rollback-handler";
        if (provisional_subscription_token.has_value()) {
          try {
            gatt_characteristic.ValueChanged(
                provisional_subscription_token.value());
          } catch (const hresult_error &err) {
            UniversalBleLogger::LogError(
                "SET_NOTIFY rollback failed hr=" +
                std::to_string(err.code()) + " msg=" +
                to_string(err.message()));
          } catch (...) {
            UniversalBleLogger::LogError(
                "SET_NOTIFY rollback failed with unknown exception");
          }
        }
        reply(create_flutter_error(UniversalBleErrorCode::kDeviceDisconnected,
                                   "Device disconnected while subscribing"));
        notification_operation_started = false;
        co_return;
      }
      notification_operation_started = false;
    }

    stage = "reply-success";
    reply(std::nullopt);
  } catch (const FlutterError &err) {
    if (notification_operation_started && device_agent) {
      if (provisional_subscription_token.has_value() &&
          subscription_characteristic) {
        try {
          subscription_characteristic.ValueChanged(
              provisional_subscription_token.value());
        } catch (...) {
        }
      }
      device_agent->FinishNotificationOperation(
          service, characteristic, previous_subscription_token);
    }
    reply(err);
  } catch (const hresult_error &err) {
    if (notification_operation_started && device_agent) {
      if (provisional_subscription_token.has_value() &&
          subscription_characteristic) {
        try {
          subscription_characteristic.ValueChanged(
              provisional_subscription_token.value());
        } catch (...) {
        }
      }
      device_agent->FinishNotificationOperation(
          service, characteristic, previous_subscription_token);
    }
    UniversalBleLogger::LogError(
        "SetNotifiableLog hresult_error stage=" + std::string(stage) +
        " hr=" + std::to_string(err.code()) +
        " msg=" + to_string(err.message()) + " device=" + device_id +
        " service=" + service + " char=" + characteristic);
    reply(create_flutter_error(UniversalBleErrorCode::kFailed,
                               to_string(err.message()),
                               std::to_string(err.code())));
  } catch (const std::exception &err) {
    if (notification_operation_started && device_agent) {
      if (provisional_subscription_token.has_value() &&
          subscription_characteristic) {
        try {
          subscription_characteristic.ValueChanged(
              provisional_subscription_token.value());
        } catch (...) {
        }
      }
      device_agent->FinishNotificationOperation(
          service, characteristic, previous_subscription_token);
    }
    UniversalBleLogger::LogError(
        "SetNotifiableLog std::exception stage=" + std::string(stage) +
        " msg=" + err.what() + " device=" + device_id +
        " service=" + service + " char=" + characteristic);
    reply(create_flutter_error(UniversalBleErrorCode::kUnknownError,
                               err.what()));
  } catch (...) {
    if (notification_operation_started && device_agent) {
      if (provisional_subscription_token.has_value() &&
          subscription_characteristic) {
        try {
          subscription_characteristic.ValueChanged(
              provisional_subscription_token.value());
        } catch (...) {
        }
      }
      device_agent->FinishNotificationOperation(
          service, characteristic, previous_subscription_token);
    }
    UniversalBleLogger::LogError(
        "SetNotifiableLog unknown exception stage=" + std::string(stage) +
        " device=" + device_id + " service=" + service +
        " char=" + characteristic);
    reply(create_flutter_unknown_error());
  }
}

event_token UniversalBlePlugin::RegisterGattValueChangedHandler(
    const std::shared_ptr<BluetoothDeviceAgent> &device_agent,
    const std::string &device_id, const std::string &characteristic_id,
    const GattCharacteristic &characteristic) {
  const auto notification_callback_operations = callback_operations_;
  return characteristic.ValueChanged(
      [this, notification_callback_operations,
       weak_device_agent = std::weak_ptr(device_agent), device_id,
       characteristic_id](const GattCharacteristic &,
                           const GattValueChangedEventArgs &args) {
        const auto callback = notification_callback_operations.TryAcquire();
        if (!callback.has_value()) {
          return;
        }
        GattCharacteristicValueChanged(weak_device_agent, device_id,
                                       characteristic_id, args);
      });
}

void UniversalBlePlugin::GattCharacteristicValueChanged(
    const std::weak_ptr<BluetoothDeviceAgent> &weak_device_agent,
    const std::string &device_id, const std::string &characteristic_id,
    const GattValueChangedEventArgs &args) {
  try {
    const auto device_agent = weak_device_agent.lock();
    if (!device_agent || !device_agent->IsActive()) {
      UniversalBleLogger::LogDebug(
          "Ignoring notification from stale Bluetooth device instance");
      return;
    }
    const auto bytes = to_bytevc(args.CharacteristicValue());

    UniversalBleLogger::LogVerboseWithTimestamp(
        "NOTIFY <- " + device_id + " " + characteristic_id +
        " len=" + std::to_string(bytes.size()));

    const auto timestamp = GetCurrentTimestampMillis();
    ui_thread_handler_.Post([weak_device_agent, device_id, characteristic_id,
                             bytes, timestamp] {
      const auto current_device_agent = weak_device_agent.lock();
      if (!current_device_agent || !current_device_agent->IsActive()) {
        return;
      }
      callback_channel->OnValueChanged(device_id, characteristic_id, bytes,
                                       &timestamp, SuccessCallback,
                                       ErrorCallback);
    });
  } catch (const hresult_error &err) {
    UniversalBleLogger::LogError(
        "GattCharacteristicValueChanged hresult_error hr=" +
        std::to_string(err.code()) + " msg=" + to_string(err.message()));
  } catch (const std::exception &ex) {
    log_and_swallow("GattCharacteristicValueChanged std::exception", ex);
  } catch (...) {
    log_and_swallow_unknown("GattCharacteristicValueChanged");
  }
}

ErrorOr<PeripheralAdvertisingState> UniversalBlePlugin::GetAdvertisingState() {
  std::lock_guard<std::mutex> lock(peripheral_mutex_);
  if (peripheral_service_provider_map_.empty()) {
    return PeripheralAdvertisingState::kIdle;
  }
  return ArePeripheralAdvertisingTargetsStarted()
             ? PeripheralAdvertisingState::kAdvertising
             : PeripheralAdvertisingState::kIdle;
}

ErrorOr<PeripheralReadinessState> UniversalBlePlugin::GetReadinessState() {
  if (!bluetooth_radio_) {
    return PeripheralReadinessState::kUnsupported;
  }
  return PeripheralReadinessState::kReady;
}

std::optional<FlutterError> UniversalBlePlugin::StopAdvertising() {
  std::lock_guard<std::mutex> lock(peripheral_mutex_);
  peripheral_advertising_targets_lc_.clear();
  for (auto const &[key, provider] : peripheral_service_provider_map_) {
    try {
      provider->obj.StopAdvertising();
    } catch (...) {
    }
  }
  ui_thread_handler_.Post([this] {
    peripheral_callback_channel_->OnAdvertisingStateChange(
        PeripheralAdvertisingState::kIdle, nullptr, SuccessCallback,
        ErrorCallback);
  });
  return std::nullopt;
}

std::optional<FlutterError>
UniversalBlePlugin::AddService(const PeripheralService &service) {
  PeripheralAddServiceAsync(service);
  return std::nullopt;
}

std::optional<FlutterError>
UniversalBlePlugin::RemoveService(const std::string &service_id) {
  std::lock_guard<std::mutex> lock(peripheral_mutex_);
  const std::string service_id_lc = to_lower_case(service_id);
  peripheral_advertising_targets_lc_.erase(
      std::remove(peripheral_advertising_targets_lc_.begin(),
                  peripheral_advertising_targets_lc_.end(), service_id_lc),
      peripheral_advertising_targets_lc_.end());

  const auto it = peripheral_service_provider_map_.find(service_id_lc);
  if (it == peripheral_service_provider_map_.end()) {
    return FlutterError("not-found", "Service not found", nullptr);
  }

  DisposePeripheralServiceProvider(it->second);
  peripheral_service_provider_map_.erase(it);
  return std::nullopt;
}

std::optional<FlutterError> UniversalBlePlugin::ClearServices() {
  std::lock_guard<std::mutex> lock(peripheral_mutex_);
  for (auto const &[_, gatt_service_object] : peripheral_service_provider_map_) {
    DisposePeripheralServiceProvider(gatt_service_object);
  }
  peripheral_service_provider_map_.clear();
  peripheral_advertising_targets_lc_.clear();
  return std::nullopt;
}

ErrorOr<flutter::EncodableList> UniversalBlePlugin::GetServices() {
  std::lock_guard<std::mutex> lock(peripheral_mutex_);
  flutter::EncodableList services;
  for (auto const &[key, _] : peripheral_service_provider_map_) {
    services.emplace_back(key);
  }
  return services;
}

ErrorOr<flutter::EncodableList>
UniversalBlePlugin::GetSubscribedClients(const std::string &characteristic_id) {
  std::lock_guard<std::mutex> lock(peripheral_mutex_);
  flutter::EncodableList out;
  auto *char_obj = FindPeripheralGattCharacteristicObject(characteristic_id);
  if (char_obj == nullptr || char_obj->obj == nullptr) {
    return out;
  }
  try {
    auto clients = char_obj->obj.SubscribedClients();
    for (uint32_t i = 0; i < clients.Size(); ++i) {
      auto client = clients.GetAt(i);
      out.push_back(flutter::EncodableValue(
          ParsePeripheralBluetoothClientId(client.Session().DeviceId().Id())));
    }
  } catch (...) {
  }
  return out;
}

ErrorOr<std::optional<int64_t>>
UniversalBlePlugin::GetMaximumNotifyLength(const std::string &device_id) {
  std::lock_guard<std::mutex> lock(peripheral_mutex_);
  for (auto const &[service_id, service_provider] :
       peripheral_service_provider_map_) {
    (void)service_id;
    for (auto const &[characteristic_id, characteristic_object] :
         service_provider->characteristics) {
      (void)characteristic_id;
      try {
        auto clients = characteristic_object->obj.SubscribedClients();
        for (uint32_t i = 0; i < clients.Size(); ++i) {
          auto client = clients.GetAt(i);
          auto id = ParsePeripheralBluetoothClientId(
              client.Session().DeviceId().Id());
          if (to_lower_case(id) != to_lower_case(device_id)) {
            continue;
          }
          const int64_t pdu_size =
              static_cast<int64_t>(client.Session().MaxPduSize());
          return std::optional<int64_t>(std::max<int64_t>(0, pdu_size - 3));
        }
      } catch (...) {
      }
    }
  }
  return std::optional<int64_t>{};
}

std::optional<FlutterError> UniversalBlePlugin::StartAdvertising(
    const flutter::EncodableList &services, const std::string *local_name,
    const int64_t *timeout, const UniversalManufacturerData *manufacturer_data,
    const PeripheralPlatformConfig *platform_config) {
  std::lock_guard<std::mutex> lock(peripheral_mutex_);
  if (peripheral_service_provider_map_.empty()) {
    return FlutterError("failed", "No services added to advertise");
  }
  if (local_name != nullptr) {
    UniversalBleLogger::LogDebug("Windows GattServiceProvider advertising does "
                                 "not support overriding local name");
  }
  if (manufacturer_data != nullptr) {
    UniversalBleLogger::LogDebug("Windows GattServiceProvider advertising does "
                                 "not support manufacturer data");
  }
  if (timeout != nullptr && *timeout > 0) {
    UniversalBleLogger::LogDebug(
        "Windows GattServiceProvider advertising timeout is not supported");
  }
  try {
    std::vector<std::string> selected_services_lc;
    selected_services_lc.reserve(services.size());
    for (const auto &service_encoded : services) {
      const auto &service_id = std::get<std::string>(service_encoded);
      const auto service_id_lc = to_lower_case(service_id);
      selected_services_lc.push_back(service_id_lc);
      if (peripheral_service_provider_map_.count(service_id_lc) == 0) {
        return FlutterError("not-found", "Service not found for advertising: " + service_id);
      }
      if (peripheral_service_provider_map_[service_id_lc] == nullptr) {
        return FlutterError("failed", "Service provider is null: " + service_id);
      }
    }

    auto params = GattServiceProviderAdvertisingParameters();
    params.IsDiscoverable(true);
    params.IsConnectable(true);
    // TODO: migrate to BluetoothLEAdvertisementPublisher to support richer
    // payload customization (local name, manufacturer data, scan response).
    for (auto const &[key, provider] : peripheral_service_provider_map_) {
      const bool should_start =
          selected_services_lc.empty() ||
          std::find(selected_services_lc.begin(), selected_services_lc.end(),
                    key) != selected_services_lc.end();
      if (!should_start) {
        continue;
      }
      if (provider == nullptr) {
        return FlutterError("failed", "Service provider is null: " + key);
      }
      if (provider->obj.AdvertisementStatus() !=
          GattServiceProviderAdvertisementStatus::Started) {
        provider->obj.StartAdvertising(params);
      }
    }
    peripheral_advertising_targets_lc_ = std::move(selected_services_lc);
    return std::nullopt;
  } catch (const hresult_error &err) {
    return FlutterError(
        "failed",
        "Failed to start advertising (hr=" + std::to_string(err.code()) +
            "): " + to_string(err.message()));
  } catch (...) {
    return FlutterError("failed", "Failed to start advertising");
  }
}

std::optional<FlutterError>
UniversalBlePlugin::UpdateCharacteristic(const std::string &characteristic_id,
                                         const std::vector<uint8_t> &value,
                                         const std::string *device_id) {
  GattLocalCharacteristic local_char = nullptr;
  IBuffer buffer = nullptr;
  {
    std::lock_guard<std::mutex> lock(peripheral_mutex_);
    if (device_id != nullptr) {
      return FlutterError("not-supported",
                          "Windows does not support targeting a specific "
                          "device for notifications",
                          nullptr);
    }
    bool ambiguous_match = false;
    auto *characteristic_object = FindPeripheralGattCharacteristicObject(
        characteristic_id, &ambiguous_match);
    if (ambiguous_match) {
      return FlutterError("ambiguous-characteristic",
                          "Characteristic UUID exists in multiple services; "
                          "cannot update uniquely",
                          nullptr);
    }
    if (characteristic_object == nullptr) {
      return FlutterError("not-found", "Characteristic not found", nullptr);
    }
    IBuffer bytes = from_bytevc(value);
    DataWriter writer;
    writer.ByteOrder(ByteOrder::LittleEndian);
    writer.WriteBuffer(bytes);
    local_char = characteristic_object->obj;
    buffer = writer.DetachBuffer();
  }

  try {
    std::future<bool> notify_future =
        std::async(std::launch::async, [local_char, buffer]() {
          auto op = local_char.NotifyValueAsync(buffer);
          op.get();
          return true;
        });
    const bool notify_result = notify_future.get();
    if (!notify_result) {
      return FlutterError(
          "failed",
          "Failed to notify subscribed clients for characteristic update",
          nullptr);
    }
  } catch (...) {
    return FlutterError(
        "failed",
        "Failed to notify subscribed clients for characteristic update",
        nullptr);
  }
  return std::nullopt;
}

fire_and_forget UniversalBlePlugin::PeripheralAddServiceAsync(const PeripheralService &service)
{
  const auto callback = callback_operations_.TryAcquire();
  if (!callback.has_value()) co_return;
  auto serviceUuid = service.uuid();
  try
  {
    // Build Service
    auto characteristics = service.characteristics();
    auto gattCharacteristicObjList = std::map<std::string, PeripheralGattCharacteristicObject *>();

    auto serviceProviderResult = co_await GattServiceProvider::CreateAsync(uuid_to_guid(serviceUuid));
    if (serviceProviderResult.Error() != BluetoothError::Success)
    {
      std::string bleError = ParsePeripheralBluetoothError(serviceProviderResult.Error());
      std::string err = "Failed to create service provider: " + serviceUuid + ", errorCode: " + bleError;
      std::cout << err << std::endl;
      peripheral_callback_channel_->OnServiceAdded(serviceUuid, &err, SuccessCallback, ErrorCallback);
      co_return;
    }

    GattServiceProvider serviceProvider = serviceProviderResult.ServiceProvider();

    // Build Characteristic
    for (auto characteristicEncoded : characteristics)
    {
      PeripheralCharacteristic characteristic = std::any_cast<PeripheralCharacteristic>(std::get<flutter::CustomEncodableValue>(characteristicEncoded));
      flutter::EncodableList descriptors = characteristic.descriptors() == nullptr ? flutter::EncodableList() : *characteristic.descriptors();

      auto charParameters = GattLocalCharacteristicParameters();
      auto characteristicUuid = characteristic.uuid();

      // Add characteristic properties
      auto charProperties = characteristic.properties();
      for (flutter::EncodableValue propertyEncoded : charProperties)
      {
        auto property = std::any_cast<CharacteristicProperty>(std::get<flutter::CustomEncodableValue>(propertyEncoded));
        charParameters.CharacteristicProperties(charParameters.CharacteristicProperties() | ToPeripheralGattCharacteristicProperties(property));
      }

      // Add characteristic permissions
      auto charPermissions = characteristic.permissions();
      for (flutter::EncodableValue permissionEncoded : charPermissions)
      {
        auto blePermission = std::any_cast<PeripheralAttributePermission>(std::get<flutter::CustomEncodableValue>(permissionEncoded));
        switch (blePermission)
        {
        case PeripheralAttributePermission::kReadable:
          charParameters.ReadProtectionLevel(GattProtectionLevel::Plain);
          break;
        case PeripheralAttributePermission::kWriteable:
          charParameters.WriteProtectionLevel(GattProtectionLevel::Plain);
          break;
        case PeripheralAttributePermission::kReadEncryptionRequired:
          charParameters.ReadProtectionLevel(GattProtectionLevel::EncryptionRequired);
          break;
        case PeripheralAttributePermission::kWriteEncryptionRequired:
          charParameters.WriteProtectionLevel(GattProtectionLevel::EncryptionRequired);
          break;
        }
      }

      const std::vector<uint8_t> *characteristicValue = characteristic.value();
      if (characteristicValue != nullptr)
      {
        auto characteristicBytes = from_bytevc(*characteristicValue);
        charParameters.StaticValue(characteristicBytes);
      }

      auto characteristicResult = co_await serviceProvider.Service().CreateCharacteristicAsync(uuid_to_guid(characteristicUuid), charParameters);
      if (characteristicResult.Error() != BluetoothError::Success)
      {
        std::wcerr << "Failed to create Char Provider: " << std::endl;
        co_return;
      }
      auto gattCharacteristic = characteristicResult.Characteristic();

      auto gattCharacteristicObject = new PeripheralGattCharacteristicObject();
      gattCharacteristicObject->obj = gattCharacteristic;
      gattCharacteristicObject->stored_clients = gattCharacteristic.SubscribedClients();

      const auto callback_operations = callback_operations_;
      gattCharacteristicObject->read_requested_token =
          gattCharacteristic.ReadRequested(
              [this, callback_operations](const auto &sender,
                                           const auto &args) {
                const auto callback = callback_operations.TryAcquire();
                if (!callback.has_value()) return;
                PeripheralReadRequestedAsync(sender, args);
              });
      gattCharacteristicObject->write_requested_token =
          gattCharacteristic.WriteRequested(
              [this, callback_operations](const auto &sender,
                                           const auto &args) {
                const auto callback = callback_operations.TryAcquire();
                if (!callback.has_value()) return;
                PeripheralWriteRequestedAsync(sender, args);
              });
      gattCharacteristicObject->value_changed_token =
          gattCharacteristic.SubscribedClientsChanged(
              [this, callback_operations](const auto &sender,
                                           const auto &args) {
                const auto callback = callback_operations.TryAcquire();
                if (!callback.has_value()) return;
                PeripheralSubscribedClientsChanged(sender, args);
              });

      // Build Descriptors
      for (flutter::EncodableValue descriptorEncoded : descriptors)
      {
        PeripheralDescriptor descriptor = std::any_cast<PeripheralDescriptor>(std::get<flutter::CustomEncodableValue>(descriptorEncoded));
        auto descriptorUuid = descriptor.uuid();
        auto descriptorParameters = GattLocalDescriptorParameters();

        // Add descriptor permissions
        flutter::EncodableList descriptorPermissions = descriptor.permissions() == nullptr ? flutter::EncodableList() : *descriptor.permissions();
        for (flutter::EncodableValue permissionsEncoded : descriptorPermissions)
        {
          auto blePermission = std::any_cast<PeripheralAttributePermission>(std::get<flutter::CustomEncodableValue>(permissionsEncoded));
          switch (blePermission)
          {
          case PeripheralAttributePermission::kReadable:
            descriptorParameters.ReadProtectionLevel(GattProtectionLevel::Plain);
            break;
          case PeripheralAttributePermission::kWriteable:
            descriptorParameters.WriteProtectionLevel(GattProtectionLevel::Plain);
            break;
          case PeripheralAttributePermission::kReadEncryptionRequired:
            descriptorParameters.ReadProtectionLevel(GattProtectionLevel::EncryptionRequired);
            break;
          case PeripheralAttributePermission::kWriteEncryptionRequired:
            descriptorParameters.WriteProtectionLevel(GattProtectionLevel::EncryptionRequired);
            break;
          }
        }
        const std::vector<uint8_t> *descriptorValue = descriptor.value();
        if (descriptorValue != nullptr)
        {
          auto descriptorBytes = from_bytevc(*descriptorValue);
          descriptorParameters.StaticValue(descriptorBytes);
        }
        auto descriptorResult = co_await gattCharacteristic.CreateDescriptorAsync(uuid_to_guid(descriptorUuid), descriptorParameters);
        if (descriptorResult.Error() != BluetoothError::Success)
        {
          std::wcerr << "Failed to create Descriptor Provider: " << std::endl;
          co_return;
        }
        GattLocalDescriptor gattDescriptor = descriptorResult.Descriptor();
      }

      gattCharacteristicObjList.insert_or_assign(guid_to_uuid(gattCharacteristic.Uuid()), gattCharacteristicObject);
    }

    PeripheralGattServiceProviderObject *gattServiceProviderObject = new PeripheralGattServiceProviderObject();
    gattServiceProviderObject->obj = serviceProvider;
    gattServiceProviderObject->characteristics = gattCharacteristicObjList;
    const auto callback_operations = callback_operations_;
    gattServiceProviderObject->advertisement_status_changed_token =
        serviceProvider.AdvertisementStatusChanged(
            [this, callback_operations](const auto &sender, const auto &args) {
              const auto callback = callback_operations.TryAcquire();
              if (!callback.has_value()) return;
              PeripheralAdvertisementStatusChanged(sender, args);
            });
    peripheral_service_provider_map_.insert_or_assign(guid_to_uuid(serviceProvider.Service().Uuid()), gattServiceProviderObject);

    ui_thread_handler_.Post([serviceUuid]
                          { peripheral_callback_channel_->OnServiceAdded(serviceUuid, nullptr, SuccessCallback, ErrorCallback); });
  }
  catch (const winrt::hresult_error &e)
  {
    std::wcerr << "Failed with error: Code: " << e.code() << "Message: " << e.message().c_str() << std::endl;
    std::string errorMessage = winrt::to_string(e.message());

    ui_thread_handler_.Post([serviceUuid, errorMessage]
                          { peripheral_callback_channel_->OnServiceAdded(serviceUuid, &errorMessage, SuccessCallback, ErrorCallback); });
  }
  catch (const std::exception &e)
  {
    std::cout << "Error: " << e.what() << std::endl;
    std::wstring errorMessage = winrt::to_hstring(e.what()).c_str();
    std::string *err = new std::string(winrt::to_string(errorMessage));
    ui_thread_handler_.Post([serviceUuid, err]
                          { peripheral_callback_channel_->OnServiceAdded(serviceUuid, err, SuccessCallback, ErrorCallback); });
  }
  catch (...)
  {
    std::cout << "Error: Unknown error" << std::endl;
    std::string *err = new std::string(winrt::to_string(L"Unknown error"));
    ui_thread_handler_.Post([serviceUuid, err]
                          { peripheral_callback_channel_->OnServiceAdded(serviceUuid, err, SuccessCallback, ErrorCallback); });
  }
}

fire_and_forget UniversalBlePlugin::PeripheralSubscribedClientsChanged(
    GattLocalCharacteristic const &local_char, IInspectable const &) {
  const auto callback = callback_operations_.TryAcquire();
  if (!callback.has_value()) co_return;
  const auto characteristic_id = guid_to_uuid(local_char.Uuid());
  IVectorView<GattSubscribedClient> current_clients = nullptr;
  IVectorView<GattSubscribedClient> old_clients = nullptr;
  {
    std::lock_guard<std::mutex> lock(peripheral_mutex_);
    auto *characteristic_object =
        FindPeripheralGattCharacteristicObject(characteristic_id);
    if (characteristic_object == nullptr) {
      co_return;
    }
    current_clients = local_char.SubscribedClients();
    old_clients = characteristic_object->stored_clients;
    characteristic_object->stored_clients = current_clients;
  }

  for (uint32_t i = 0; i < current_clients.Size(); ++i) {
    auto client = current_clients.GetAt(i);
    bool found = false;
    for (uint32_t j = 0; j < old_clients.Size(); ++j) {
      if (old_clients.GetAt(j) == client) {
        found = true;
        break;
      }
    }
    if (!found) {
      const auto device_id =
          ParsePeripheralBluetoothClientId(client.Session().DeviceId().Id());
      std::string device_name;
      try {
        auto device_info = co_await DeviceInformation::CreateFromIdAsync(
            client.Session().DeviceId().Id());
        device_name = winrt::to_string(device_info.Name());
      } catch (...) {
      }
      ui_thread_handler_.Post(
          [this, device_id, characteristic_id, device_name] {
            const std::string *name_ptr =
                device_name.empty() ? nullptr : &device_name;
            peripheral_callback_channel_->OnCharacteristicSubscriptionChange(
                device_id, characteristic_id, true, name_ptr, SuccessCallback,
                ErrorCallback);
          });
      const int64_t mtu = client.Session().MaxPduSize();
      ui_thread_handler_.Post([this, device_id, mtu] {
        peripheral_callback_channel_->OnMtuChange(
            device_id, mtu, SuccessCallback, ErrorCallback);
      });
    }
  }

  for (uint32_t i = 0; i < old_clients.Size(); ++i) {
    auto client = old_clients.GetAt(i);
    bool found = false;
    for (uint32_t j = 0; j < current_clients.Size(); ++j) {
      if (current_clients.GetAt(j) == client) {
        found = true;
        break;
      }
    }
    if (!found) {
      const auto device_id =
          ParsePeripheralBluetoothClientId(client.Session().DeviceId().Id());
      ui_thread_handler_.Post([this, device_id, characteristic_id] {
        peripheral_callback_channel_->OnCharacteristicSubscriptionChange(
            device_id, characteristic_id, false, nullptr, SuccessCallback,
            ErrorCallback);
      });
    }
  }
}

fire_and_forget UniversalBlePlugin::PeripheralReadRequestedAsync(GattLocalCharacteristic const &local_char, GattReadRequestedEventArgs args) {
  const auto callback = callback_operations_.TryAcquire();
  if (!callback.has_value()) co_return;
  auto deferral = args.GetDeferral();
  try {
    std::string characteristicId = to_uuidstr(local_char.Uuid());
    auto value_holder = std::make_shared<std::vector<uint8_t>>();
    std::vector<uint8_t> *value_arg = nullptr;
    IBuffer charValue = local_char.StaticValue();
    if (charValue != nullptr) {
      *value_holder = to_bytevc(charValue);
      value_arg = value_holder.get();
    }
    auto request = co_await args.GetRequestAsync();
    if (request == nullptr) {
      // No access allowed to the device.  Application should indicate this to the user.
      std::cout << "No access allowed to the device" << std::endl;
      deferral.Complete();
      co_return;
    }
    const auto device_id =
        ParsePeripheralBluetoothClientId(args.Session().DeviceId().Id());
    const int64_t offset = request.Offset();
    ui_thread_handler_.Post([this, device_id, characteristicId, offset, value_arg,
                             value_holder, deferral, request] {
      peripheral_callback_channel_->OnReadRequest(
          device_id, characteristicId, offset, value_arg,
          // SuccessCallback
          [request, deferral](const PeripheralReadRequestResult *result) {
            if (result != nullptr) {
              if (result->status() != nullptr) {
                request.RespondWithProtocolError(
                    ToGattProtocolError(*result->status()));
                deferral.Complete();
                return;
              }
              DataWriter writer;
              writer.ByteOrder(ByteOrder::LittleEndian);
              writer.WriteBuffer(from_bytevc(result->value()));
              request.RespondWithValue(writer.DetachBuffer());
            } else {
              request.RespondWithProtocolError(0x01);
            }
            deferral.Complete();
          },
          // ErrorCallback
          [request, deferral](const FlutterError &error) {
            request.RespondWithProtocolError(0x0E);
            deferral.Complete();
          });
    });
  } catch (...) {
    deferral.Complete();
  }
}

fire_and_forget UniversalBlePlugin::PeripheralWriteRequestedAsync(
    GattLocalCharacteristic const &localChar, GattWriteRequestedEventArgs args) {
  const auto callback = callback_operations_.TryAcquire();
  if (!callback.has_value()) co_return;
  auto deferral = args.GetDeferral();
  try {
    std::string characteristicId = to_uuidstr(localChar.Uuid());

    GattWriteRequest request = co_await args.GetRequestAsync();
    if (request == nullptr) {
      deferral.Complete();
      co_return;
    }

    std::string deviceId = ParsePeripheralBluetoothClientId(args.Session().DeviceId().Id());
    
    int64_t offset = 0;
    try {
      offset = request.Offset();
    } catch (const hresult_error &err) {
      UniversalBleLogger::LogError(
          "PERIPHERAL_WRITE_REQ failed offset hr=" +
          std::to_string(err.code()) + " msg=" + to_string(err.message()));
    } catch (...) {
      UniversalBleLogger::LogError("PERIPHERAL_WRITE_REQ failed offset unknown");
    }

    bool with_response = false;
    try {
      with_response = request.Option() == GattWriteOption::WriteWithResponse;
    } catch (const hresult_error &err) {
      UniversalBleLogger::LogError(
          "PERIPHERAL_WRITE_REQ failed option hr=" +
          std::to_string(err.code()) + " msg=" + to_string(err.message()));
    } catch (...) {
      UniversalBleLogger::LogError("PERIPHERAL_WRITE_REQ failed option unknown");
    }

    auto value_holder = std::make_shared<std::vector<uint8_t>>();
    try {
      if (request.Value() != nullptr) {
        *value_holder = to_bytevc(request.Value());
      }
    } catch (const hresult_error &err) {
      UniversalBleLogger::LogError(
          "PERIPHERAL_WRITE_REQ failed value extraction hr=" +
          std::to_string(err.code()) + " msg=" + to_string(err.message()));
    } catch (...) {
      UniversalBleLogger::LogError(
          "PERIPHERAL_WRITE_REQ failed value extraction unknown");
    }

    ui_thread_handler_.Post([this, characteristicId, offset, value_holder, request,
                             deferral, deviceId, with_response] {
      peripheral_callback_channel_->OnWriteRequest(
          deviceId, characteristicId, offset, value_holder.get(),
          [deferral, request, deviceId, characteristicId,
           with_response](const PeripheralWriteRequestResult *writeResult) {
            try {
              if (with_response) {
                if (writeResult != nullptr && writeResult->status() != nullptr) {
                  request.RespondWithProtocolError(ToGattProtocolError(*writeResult->status()));
                } else {
                  request.Respond();
                }
              }
            } catch (const hresult_error &err) {
              UniversalBleLogger::LogError(
                  "PERIPHERAL_WRITE_REQ response hresult_error hr=" +
                  std::to_string(err.code()) + " msg=" +
                  to_string(err.message()));
            } catch (...) {
              UniversalBleLogger::LogError(
                  "PERIPHERAL_WRITE_REQ response unknown exception");
            }
            deferral.Complete();
          },
          [deferral, request, with_response](const FlutterError &error) {
            try {
              if (with_response) {
                request.RespondWithProtocolError(0x0E);
              }
            } catch (const hresult_error &err) {
              UniversalBleLogger::LogError(
                  "PERIPHERAL_WRITE_REQ error-response hresult_error hr=" +
                  std::to_string(err.code()) + " msg=" +
                  to_string(err.message()));
            } catch (...) {
              UniversalBleLogger::LogError(
                  "PERIPHERAL_WRITE_REQ error-response unknown exception");
            }
            deferral.Complete();
          });
    });
  } catch (const hresult_error &err) {
    UniversalBleLogger::LogError(
        "PERIPHERAL_WRITE_REQ outer hresult_error hr=" +
        std::to_string(err.code()) + " msg=" + to_string(err.message()));
    deferral.Complete();
  } catch (...) {
    UniversalBleLogger::LogError(
        "PERIPHERAL_WRITE_REQ outer unknown exception");
    deferral.Complete();
  }
}

void UniversalBlePlugin::PeripheralAdvertisementStatusChanged(
    GattServiceProvider const &sender,
    GattServiceProviderAdvertisementStatusChangedEventArgs const &args) {
  if (args.Error() != BluetoothError::Success) {
    auto error_str = ParsePeripheralBluetoothError(args.Error());
    ui_thread_handler_.Post([this, error_str] {
      peripheral_callback_channel_->OnAdvertisingStateChange(
          PeripheralAdvertisingState::kError, &error_str, SuccessCallback,
          ErrorCallback);
    });
    return;
  }
  std::lock_guard<std::mutex> lock(peripheral_mutex_);
  if (ArePeripheralAdvertisingTargetsStarted()) {
    ui_thread_handler_.Post([this] {
      peripheral_callback_channel_->OnAdvertisingStateChange(
          PeripheralAdvertisingState::kAdvertising, nullptr, SuccessCallback,
          ErrorCallback);
    });
  }
}

void UniversalBlePlugin::DisposePeripheralServiceProvider(
    PeripheralGattServiceProviderObject *service_provider_object) {
  if (service_provider_object == nullptr) {
    return;
  }
  try {
    if (service_provider_object->obj.AdvertisementStatus() ==
        GattServiceProviderAdvertisementStatus::Started) {
      service_provider_object->obj.StopAdvertising();
    }
  } catch (...) {
  }
  try {
    service_provider_object->obj.AdvertisementStatusChanged(
        service_provider_object->advertisement_status_changed_token);
  } catch (...) {
  }
  for (auto const &[_, characteristic_object] :
       service_provider_object->characteristics) {
    try {
      characteristic_object->obj.ReadRequested(characteristic_object->read_requested_token);
      characteristic_object->obj.WriteRequested(characteristic_object->write_requested_token);
      characteristic_object->obj.SubscribedClientsChanged(characteristic_object->value_changed_token);
    } catch (...) {
    }
  }
}

//PeripheralGattCharacteristicObject *
//UniversalBlePlugin::FindPeripheralGattCharacteristicObject(
//    const std::string &characteristic_id, bool *ambiguous_match) {
//  const auto characteristic_id_lc = to_lower_case(characteristic_id);
//  PeripheralGattCharacteristicObject *first_match = nullptr;
//  for (auto const &[_, service_provider] : peripheral_service_provider_map_) {
//    for (auto const &[char_key, characteristic_object] : service_provider->characteristics) {
//      if (to_lower_case(char_key) == characteristic_id_lc) {
//        if (first_match == nullptr) {
//          first_match = characteristic_object.get();
//        } else {
//          if (ambiguous_match != nullptr) {
//            *ambiguous_match = true;
//          }
//          return nullptr;
//        }
//      }
//    }
//  }
//  return first_match;
//}

PeripheralGattCharacteristicObject*
UniversalBlePlugin::FindPeripheralGattCharacteristicObject(
    const std::string& characteristic_id, bool* ambiguous_match) {
    // This might return wrong result if multiple services have same characteristic Id
    std::string loweCaseCharId = to_lower_case(characteristic_id);
    for (auto const& [key, gattServiceObject] : peripheral_service_provider_map_) {
        for (auto const& [charKey, gattChar] : gattServiceObject->characteristics) {
            if (charKey == loweCaseCharId)
                return gattChar;
        }
    }
    return nullptr;
}

bool UniversalBlePlugin::ArePeripheralAdvertisingTargetsStarted() const {
  if (peripheral_service_provider_map_.empty()) {
    return false;
  }
  if (peripheral_advertising_targets_lc_.empty()) {
    for (auto const &[_, service_provider] : peripheral_service_provider_map_) {
      if (service_provider->obj.AdvertisementStatus() !=
          GattServiceProviderAdvertisementStatus::Started) {
        return false;
      }
    }
    return true;
  }
  for (const auto &target_id : peripheral_advertising_targets_lc_) {
    const auto it = peripheral_service_provider_map_.find(target_id);
    if (it == peripheral_service_provider_map_.end()) {
      return false;
    }
    if (it->second->obj.AdvertisementStatus() !=
        GattServiceProviderAdvertisementStatus::Started) {
      return false;
    }
  }
  return true;
}

GattCharacteristicProperties
UniversalBlePlugin::ToPeripheralGattCharacteristicProperties(CharacteristicProperty property) {
  switch (property) {
  case CharacteristicProperty::kBroadcast:
    return GattCharacteristicProperties::Broadcast;
  case CharacteristicProperty::kRead:
    return GattCharacteristicProperties::Read;
  case CharacteristicProperty::kWriteWithoutResponse:
    return GattCharacteristicProperties::WriteWithoutResponse;
  case CharacteristicProperty::kWrite:
    return GattCharacteristicProperties::Write;
  case CharacteristicProperty::kNotify:
    return GattCharacteristicProperties::Notify;
  case CharacteristicProperty::kIndicate:
    return GattCharacteristicProperties::Indicate;
  case CharacteristicProperty::kAuthenticatedSignedWrites:
    return GattCharacteristicProperties::AuthenticatedSignedWrites;
  case CharacteristicProperty::kExtendedProperties:
    return GattCharacteristicProperties::ExtendedProperties;
  default:
    return GattCharacteristicProperties::None;
  }
}

std::string UniversalBlePlugin::PeripheralAdvertisementStatusToString(
    GattServiceProviderAdvertisementStatus status) {
  switch (status) {
  case GattServiceProviderAdvertisementStatus::Created:
    return "Created";
  case GattServiceProviderAdvertisementStatus::Started:
    return "Started";
  case GattServiceProviderAdvertisementStatus::Stopped:
    return "Stopped";
  case GattServiceProviderAdvertisementStatus::Aborted:
    return "Aborted";
  case GattServiceProviderAdvertisementStatus::
      StartedWithoutAllAdvertisementData:
    return "StartedWithoutAllAdvertisementData";
  default:
    return "Unknown";
  }
}

std::string
UniversalBlePlugin::ParsePeripheralBluetoothClientId(hstring client_id) {
  auto id = winrt::to_string(client_id);
  const auto pos = id.find_last_of('-');
  if (pos != std::string::npos) {
    return id.substr(pos + 1);
  }
  return id;
}

std::string
UniversalBlePlugin::ParsePeripheralBluetoothError(BluetoothError error) {
  switch (error) {
  case BluetoothError::Success:
    return "Success";
  case BluetoothError::RadioNotAvailable:
    return "RadioNotAvailable";
  case BluetoothError::ResourceInUse:
    return "ResourceInUse";
  case BluetoothError::DeviceNotConnected:
    return "DeviceNotConnected";
  case BluetoothError::OtherError:
    return "OtherError";
  case BluetoothError::DisabledByPolicy:
    return "DisabledByPolicy";
  case BluetoothError::NotSupported:
    return "NotSupported";
  case BluetoothError::DisabledByUser:
    return "DisabledByUser";
  case BluetoothError::ConsentRequired:
    return "ConsentRequired";
  case BluetoothError::TransportNotSupported:
    return "TransportNotSupported";
  default:
    return "Unknown";
  }
}

uint8_t UniversalBlePlugin::ToGattProtocolError(int64_t status_code) {
  if (status_code < 0) {
    return 0x01;
  }
  if (status_code > 0xFF) {
    return 0xFF;
  }
  return static_cast<uint8_t>(status_code);
}

} // namespace universal_ble
