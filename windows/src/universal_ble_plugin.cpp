#include "universal_ble_plugin.h"
#include <windows.h>

#include <flutter/plugin_registrar_windows.h>

#include <map>
#include <memory>
#include <sstream>
#include <algorithm>
#include <iomanip>
#include <thread>
#include <regex>

#include "helper/utils.h"
#include "helper/universal_enum.h"
#include "generated/universal_ble.g.h"

namespace universal_ble
{
  using universal_ble::ErrorOr;
  using universal_ble::UniversalBleCallbackChannel;
  using universal_ble::UniversalBlePlatformChannel;
  using universal_ble::UniversalBleScanResult;

  const auto isConnectableKey = L"System.Devices.Aep.Bluetooth.Le.IsConnectable";
  const auto isConnectedKey = L"System.Devices.Aep.IsConnected";
  const auto isPairedKey = L"System.Devices.Aep.IsPaired";
  const auto isPresentKey = L"System.Devices.Aep.IsPresent";
  const auto deviceAddressKey = L"System.Devices.Aep.DeviceAddress";
  const auto signalStrengthKey = L"System.Devices.Aep.SignalStrength";

  std::unique_ptr<UniversalBleCallbackChannel> callbackChannel;
  std::unordered_map<std::string, winrt::event_token> characteristicsTokens{}; // TODO: Remove the map and store the token inside the characteristic object object

  union uint16_t_union
  {
    uint16_t uint16;
    byte bytes[sizeof(uint16_t)];
  };

  void UniversalBlePlugin::RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar)
  {
    auto plugin = std::make_unique<UniversalBlePlugin>(registrar);
    UniversalBlePlatformChannel::SetUp(registrar->messenger(), plugin.get());
    callbackChannel = std::make_unique<UniversalBleCallbackChannel>(registrar->messenger());
    registrar->AddPlugin(std::move(plugin));
  }

  UniversalBlePlugin::UniversalBlePlugin(flutter::PluginRegistrarWindows *registrar)
      : uiThreadHandler_(registrar)
  {
    InitializeAsync();
  }

  UniversalBlePlugin::~UniversalBlePlugin()
  {
  }

  // UniversalBlePlatformChannel implementation.
  void UniversalBlePlugin::GetBluetoothAvailabilityState(std::function<void(ErrorOr<int64_t> reply)> result)
  {
    if (!bluetoothRadio)
      result(static_cast<int>(AvailabilityState::unsupported));
    else
      result(static_cast<int>(getAvailabilityStateFromRadio(bluetoothRadio.State())));
  };

  void UniversalBlePlugin::EnableBluetooth(std::function<void(ErrorOr<bool> reply)> result)
  {
    if (!bluetoothRadio)
    {
      result(FlutterError("Bluetooth is not available"));
      return;
    }
    if (bluetoothRadio.State() == RadioState::On)
    {
      result(true);
      return;
    }
    auto async_c = bluetoothRadio.SetStateAsync(RadioState::On);
    async_c.Completed([&, result](IAsyncOperation<RadioAccessStatus> const &sender, AsyncStatus const args)
                      {
                        auto radioAccessStatus = sender.GetResults();
                        if (radioAccessStatus == RadioAccessStatus::Allowed)
                        {
                          result(true);
                        }
                        else
                        {
                          result(FlutterError("Failed to enable bluetooth"));
                        } });
  }

  std::optional<FlutterError> UniversalBlePlugin::StartScan(const UniversalScanFilter *filter)
  {
    if (bluetoothRadio && bluetoothRadio.State() == RadioState::On)
    {
      if (!bluetoothLEWatcher)
      {
        bluetoothLEWatcher = BluetoothLEAdvertisementWatcher();
        bluetoothLEWatcher.ScanningMode(BluetoothLEScanningMode::Active);
        if (filter != nullptr)
          ApplyScanFilter(filter, bluetoothLEWatcher);
        bluetoothLEWatcherReceivedToken = bluetoothLEWatcher.Received({this, &UniversalBlePlugin::BluetoothLEWatcher_Received});
      }
      bluetoothLEWatcher.Start();
      setupDeviceWatcher();
      DeviceWatcherStatus status = deviceWatcher.Status();
      if (status != DeviceWatcherStatus::Started)
        deviceWatcher.Start();
      else
        return FlutterError("Already scanning");
      return std::nullopt;
    }
    else
    {
      return FlutterError("Bluetooth is not available");
    }
  };

  void UniversalBlePlugin::ApplyScanFilter(const UniversalScanFilter *filter, BluetoothLEAdvertisementWatcher &bluetoothWatcher)
  {
    // Apply Services filter
    const auto &services = filter->with_services();
    if (!services.empty())
    {
      for (const auto &uuid : services)
      {
        std::string uuid_str = std::get<std::string>(uuid);
        bluetoothWatcher.AdvertisementFilter().Advertisement().ServiceUuids().Append(uuid_to_guid(uuid_str));
      }
    }
  }

  std::optional<FlutterError> UniversalBlePlugin::StopScan()
  {

    if (bluetoothRadio && bluetoothRadio.State() == RadioState::On)
    {
      if (bluetoothLEWatcher)
      {
        bluetoothLEWatcher.Stop();
        bluetoothLEWatcher.Received(bluetoothLEWatcherReceivedToken);
      }
      bluetoothLEWatcher = nullptr;
      disposeDeviceWatcher();
      return std::nullopt;
    }
    else
    {
      return FlutterError("Bluetooth is not available");
    }
  };

  std::optional<FlutterError> UniversalBlePlugin::Connect(const std::string &device_id)
  {
    ConnectAsync(_str_to_mac_address(device_id));
    return std::nullopt;
  };

  std::optional<FlutterError> UniversalBlePlugin::Disconnect(const std::string &device_id)
  {
    auto deviceAddress = _str_to_mac_address(device_id);
    CleanConnection(deviceAddress);
    // TODO: send disconnect event only after disconnect is complete
    uiThreadHandler_.Post([deviceAddress]
                          { callbackChannel->OnConnectionChanged(_mac_address_to_str(deviceAddress), static_cast<int>(ConnectionState::disconnected), SuccessCallback, ErrorCallback); });

    return std::nullopt;
  };

  void UniversalBlePlugin::DiscoverServices(
      const std::string &device_id,
      std::function<void(ErrorOr<flutter::EncodableList> reply)> result)
  {
    try
    {
      auto it = connectedDevices.find(_str_to_mac_address(device_id));
      if (it == connectedDevices.end())
      {
        result(FlutterError("IllegalArgument", "Unknown devicesId:" + device_id));
        return;
      }
      auto deviceAgent = *it->second;
      DiscoverServicesAsync(deviceAgent, result);
    }
    catch (const FlutterError &err)
    {
      return result(err);
    }
    catch (...)
    {
      std::cout << "DiscoverServicesLog: Unknown error" << std::endl;
      return result(FlutterError("Unknown error"));
    }
  }

  std::optional<FlutterError> UniversalBlePlugin::SetNotifiable(
      const std::string &device_id,
      const std::string &service,
      const std::string &characteristic,
      int64_t ble_input_property)
  {
    try
    {
      auto it = connectedDevices.find(_str_to_mac_address(device_id));
      if (it == connectedDevices.end())
        return FlutterError("IllegalArgument", "Unknown devicesId:" + device_id);
      auto bluetoothAgent = *it->second;
      GattCharacteristicObject &gatt_characteristic_holder = bluetoothAgent._fetch_characteristic(service, characteristic);
      GattCharacteristic gattCharacteristic = gatt_characteristic_holder.obj;
      auto descriptorValue = GattClientCharacteristicConfigurationDescriptorValue::None;
      auto properties = gattCharacteristic.CharacteristicProperties();

      if (ble_input_property == static_cast<int>(BleInputProperty::notification))
      {
        descriptorValue = GattClientCharacteristicConfigurationDescriptorValue::Notify;
        if ((properties & GattCharacteristicProperties::Notify) == GattCharacteristicProperties::None)
        {
          return FlutterError("Characteristic does not support notify");
        }
      }
      else if (ble_input_property == static_cast<int>(BleInputProperty::indication))
      {
        descriptorValue = GattClientCharacteristicConfigurationDescriptorValue::Indicate;
        if ((properties & GattCharacteristicProperties::Indicate) == GattCharacteristicProperties::None)
        {
          return FlutterError("Characteristic does not support indicate");
        }
      }

      SetNotifiableAsync(bluetoothAgent, service, characteristic, descriptorValue);
      return std::nullopt;
    }
    catch (const FlutterError &err)
    {
      return err;
    }
    catch (...)
    {
      std::cout << "SetNotifiableLog: Unknown error" << std::endl;
      return FlutterError("Unknown error");
    }
  };

  void UniversalBlePlugin::ReadValue(
      const std::string &device_id,
      const std::string &service,
      const std::string &characteristic,
      std::function<void(ErrorOr<std::vector<uint8_t>> reply)> result)
  {
    try
    {
      auto it = connectedDevices.find(_str_to_mac_address(device_id));
      if (it == connectedDevices.end())
      {
        result(FlutterError("IllegalArgument", "Unknown devicesId:" + device_id));
        return;
      }
      auto bluetoothAgent = *it->second;
      GattCharacteristicObject &gatt_characteristic_holder = bluetoothAgent._fetch_characteristic(service, characteristic);
      GattCharacteristic gattCharacteristic = gatt_characteristic_holder.obj;
      auto properties = gattCharacteristic.CharacteristicProperties();
      if ((properties & GattCharacteristicProperties::Read) == GattCharacteristicProperties::None)
      {
        result(FlutterError("Characteristic does not support read"));
        return;
      }
      auto async_c = gattCharacteristic.ReadValueAsync(Devices::Bluetooth::BluetoothCacheMode::Uncached);
      async_c.Completed([&, result](IAsyncOperation<GattReadResult> const &sender, AsyncStatus const args)
                        {
                          auto readValueResult = sender.GetResults();
                          switch (readValueResult.Status())
                          {
                          case GenericAttributeProfile::GattCommunicationStatus::Success:
                            result(to_bytevc(readValueResult.Value()));
                            return;
                          case GenericAttributeProfile::GattCommunicationStatus::Unreachable:
                            result(FlutterError("Unreachable","Failed to read value"));
                            return;
                          case GenericAttributeProfile::GattCommunicationStatus::ProtocolError:
                            result(FlutterError("ProtocolError","Failed to read value"));
                            return;
                          case GenericAttributeProfile::GattCommunicationStatus::AccessDenied:
                            result(FlutterError("AccessDenied","Failed to read value"));
                            return;
                          default:
                            result(FlutterError("Failed","Failed to read value"));
                            return;
                          } });
    }
    catch (const FlutterError &err)
    {
      return result(err);
    }
    catch (...)
    {
      std::cout << "ReadValueLog: Unknown error" << std::endl;
      return result(FlutterError("Unknown error"));
    }
  }

  void UniversalBlePlugin::WriteValue(
      const std::string &device_id,
      const std::string &service,
      const std::string &characteristic,
      const std::vector<uint8_t> &value,
      int64_t ble_output_property,
      std::function<void(std::optional<FlutterError> reply)> result)
  {
    try
    {
      auto it = connectedDevices.find(_str_to_mac_address(device_id));
      if (it == connectedDevices.end())
      {
        result(FlutterError("IllegalArgument", "Unknown devicesId:" + device_id));
        return;
      }
      auto bluetoothAgent = *it->second;
      GattCharacteristicObject &gatt_characteristic_holder = bluetoothAgent._fetch_characteristic(service, characteristic);
      GattCharacteristic gattCharacteristic = gatt_characteristic_holder.obj;
      auto properties = gattCharacteristic.CharacteristicProperties();
      auto writeOption = GattWriteOption::WriteWithResponse;
      if (ble_output_property == static_cast<int>(BleOutputProperty::withoutResponse))
      {
        writeOption = GattWriteOption::WriteWithoutResponse;
        if ((properties & GattCharacteristicProperties::WriteWithoutResponse) == GattCharacteristicProperties::None)
        {
          result(FlutterError("Characteristic does not support WriteWithoutResponse"));
          return;
        }
      }
      else
      {
        if ((properties & GattCharacteristicProperties::Write) == GattCharacteristicProperties::None)
        {
          result(FlutterError("Characteristic does not support Write"));
          return;
        }
      }

      WriteAsync(gatt_characteristic_holder.obj, writeOption, value, result);
    }
    catch (const FlutterError &err)
    {
      result(err);
    }
    catch (...)
    {
      std::cout << "WriteValue: Unknown error" << std::endl;
      result(FlutterError("Unknown error"));
    }
  }

  void UniversalBlePlugin::RequestMtu(
      const std::string &device_id,
      int64_t expected_mtu,
      std::function<void(ErrorOr<int64_t> reply)> result)
  {
    try
    {
      auto it = connectedDevices.find(_str_to_mac_address(device_id));
      if (it == connectedDevices.end())
      {
        result(FlutterError("IllegalArgument", "Unknown devicesId:" + device_id));
        return;
      }
      auto bluetoothAgent = *it->second;
      auto async_c = GattSession::FromDeviceIdAsync(bluetoothAgent.device.BluetoothDeviceId());
      async_c.Completed([&, result](IAsyncOperation<GattSession> const &sender, AsyncStatus const args)
                        {
                          auto gattSession = sender.GetResults();
                           result((int64_t)gattSession.MaxPduSize()); });
    }
    catch (const FlutterError &err)
    {
      result(err);
    }
  }

  void UniversalBlePlugin::IsPaired(
      const std::string &device_id,
      std::function<void(ErrorOr<bool> reply)> result)
  {
    IsPairedAsync(device_id, result);
  };

  std::optional<FlutterError> UniversalBlePlugin::Pair(const std::string &device_id)
  {
    try
    {
      auto device = async_get(BluetoothLEDevice::FromBluetoothAddressAsync(_str_to_mac_address(device_id)));
      std::cout << "PairLog: Device to be paired was found" << std::endl;
      auto deviceInformation = device.DeviceInformation();
      bool isPaired = deviceInformation.Pairing().IsPaired();
      if (isPaired)
        return FlutterError("PairLog: Device is already paired");
      bool canPair = deviceInformation.Pairing().CanPair();
      if (!canPair)
        return FlutterError("PairLog: Device is not pairable");

      auto customPairing = deviceInformation.Pairing().Custom();
      winrt::event_token token = customPairing.PairingRequested([this](const Enumeration::DeviceInformationCustomPairing &sender, const Enumeration::DevicePairingRequestedEventArgs &eventArgs)
                                                                {
                                                                // eventArgs.AcceptWithPasswordCredential(nullptr, nullptr);
                                                                // eventArgs.Pin();
                                                                // Accept all pairing request
                                                                eventArgs.Accept(); });
      // DevicePairingKinds => None, ConfirmOnly, DisplayPin, ProvidePin, ConfirmPinMatch, ProvidePasswordCredential
      // DevicePairingProtectionLevel =>  Default, None, Encryption, EncryptionAndAuthentication
      std::cout << "PairLog: Trying to pair" << std::endl;
      auto async_c = customPairing.PairAsync(
          Enumeration::DevicePairingKinds::ConfirmOnly,
          Enumeration::DevicePairingProtectionLevel::None);
      async_c.Completed([this, customPairing, token, device_id](IAsyncOperation<DevicePairingResult> const &sender, AsyncStatus const args)
                        {
                          auto result = sender.GetResults();
                          std::cout << "PairLog: Received pairing status" << std::endl;
                          customPairing.PairingRequested(token);
                          auto isPaired = result.Status() == Enumeration::DevicePairingResultStatus::Paired;

                          // Post to main thread
                          std::string errorStr = parsePairingFailError(result);
                          uiThreadHandler_.Post([device_id, isPaired, errorStr]
                                                { callbackChannel->OnPairStateChange(device_id, isPaired, &errorStr, SuccessCallback, ErrorCallback); }); });
      return std::nullopt;
    }
    catch (const FlutterError &err)
    {
      return err;
    }
  };

  std::optional<FlutterError> UniversalBlePlugin::UnPair(const std::string &device_id)
  {
    try
    {
      auto device = async_get(BluetoothLEDevice::FromBluetoothAddressAsync(_str_to_mac_address(device_id)));
      auto deviceInformation = device.DeviceInformation();
      bool isPaired = deviceInformation.Pairing().IsPaired();
      if (!isPaired)
        return FlutterError("Device is not paired");

      auto deviceUnpairingResult = async_get(deviceInformation.Pairing().UnpairAsync());
      auto unpairingStatus = deviceUnpairingResult.Status();
      if (unpairingStatus == Enumeration::DeviceUnpairingResultStatus::Failed)
        return FlutterError("Failed to unpair device");
      if (unpairingStatus == Enumeration::DeviceUnpairingResultStatus::AccessDenied)
        return FlutterError("Access denied");
      if (unpairingStatus == Enumeration::DeviceUnpairingResultStatus::AlreadyUnpaired)
        return FlutterError("Device is already unpaired");
      if (unpairingStatus == Enumeration::DeviceUnpairingResultStatus::OperationAlreadyInProgress)
        return FlutterError("OperationAlreadyInProgress");
      return std::nullopt;
    }
    catch (const FlutterError &err)
    {
      return err;
    }
  };

  void UniversalBlePlugin::GetConnectedDevices(
      const flutter::EncodableList &with_services,
      std::function<void(ErrorOr<flutter::EncodableList> reply)> result)
  {
    std::vector<std::string> with_services_str = std::vector<std::string>();
    for (const auto &item : with_services)
    {
      auto serviceId = std::get<std::string>(item);
      with_services_str.push_back(serviceId);
    }
    GetConnectedDevicesAsync(with_services_str, result);
  }

  /// Helper Methods

  std::vector<uint8_t> parseManufacturerDataHead(BluetoothLEAdvertisement advertisement, std::string deviceId)
  {
    try
    {
      if (advertisement.ManufacturerData().Size() == 0)
      {
        return std::vector<uint8_t>();
      }
      auto manufacturerData = advertisement.ManufacturerData().GetAt(0);
      // FIXME Compat with REG_DWORD_BIG_ENDIAN
      uint8_t *prefix = uint16_t_union{manufacturerData.CompanyId()}.bytes;
      auto result = std::vector<uint8_t>{prefix, prefix + sizeof(uint16_t_union)};

      auto data = to_bytevc(manufacturerData.Data());
      result.insert(result.end(), data.begin(), data.end());
      return result;
    }
    catch (...)
    {
      std::cout << "Error in parsing manufacturer data: " << deviceId << std::endl;
      return std::vector<uint8_t>();
    }
  }

  winrt::fire_and_forget UniversalBlePlugin::InitializeAsync()
  {
    auto radios = co_await Radio::GetRadiosAsync();
    for (auto &&radio : radios)
    {
      if (radio.Kind() == RadioKind::Bluetooth)
      {
        bluetoothRadio = radio;
        radioStateChangedRevoker = bluetoothRadio.StateChanged(winrt::auto_revoke, {this, &UniversalBlePlugin::Radio_StateChanged});
        break;
      }
    }
    if (!bluetoothRadio)
    {
      std::cout << "Bluetooth is not available" << std::endl;
    }
  }

  // Send device to callback channel
  // if device is already discovered in deviceWatcher then merge the scan result
  void UniversalBlePlugin::pushUniversalScanResult(UniversalBleScanResult scanResult)
  {
    auto it = scanResults.find(scanResult.device_id());
    if (it != scanResults.end())
    {
      UniversalBleScanResult &existingScanResult = it->second;
      bool shouldUpdate = false;
      if ((scanResult.name() == nullptr || scanResult.name()->empty()) && (existingScanResult.name() != nullptr && !existingScanResult.name()->empty()))
      {
        scanResult.set_name(*existingScanResult.name());
        shouldUpdate = true;
      }
      if (scanResult.is_paired() == nullptr && existingScanResult.is_paired() != nullptr)
      {
        scanResult.set_is_paired(existingScanResult.is_paired());
        shouldUpdate = true;
      }
      if (scanResult.manufacturer_data_head() == nullptr && existingScanResult.manufacturer_data_head() != nullptr)
      {
        scanResult.set_manufacturer_data_head(existingScanResult.manufacturer_data_head());
        shouldUpdate = true;
      }
      if (scanResult.services() == nullptr && existingScanResult.services() != nullptr)
      {
        scanResult.set_services(existingScanResult.services());
        shouldUpdate = true;
      }

      // if nothing to update then return
      if (!shouldUpdate)
        return;

      // update the existing scan result
      existingScanResult = scanResult;
    }
    else
    {
      // if not present, insert the new scan result
      scanResults.insert(std::make_pair(scanResult.device_id(), scanResult));
    }

    uiThreadHandler_.Post([scanResult]
                          { callbackChannel->OnScanResult(scanResult, SuccessCallback, ErrorCallback); });
  }

  void UniversalBlePlugin::setupDeviceWatcher()
  {
    if (deviceWatcher != nullptr)
      return;

    deviceWatcher = DeviceInformation::CreateWatcher(
        L"(System.Devices.Aep.ProtocolId:=\"{bb7bb05e-5972-42b5-94fc-76eaa7084d49}\")",
        {
            deviceAddressKey,
            isConnectedKey,
            isPairedKey,
            isPresentKey,
            isConnectableKey,
            signalStrengthKey,
        },
        DeviceInformationKind::AssociationEndpoint);

    /// Device Added from DeviceWatcher
    deviceWatcherAddedToken = deviceWatcher.Added([this](DeviceWatcher sender, DeviceInformation deviceInfo)
                                                  {
                                                    std::string deviceId = winrt::to_string(deviceInfo.Id());
                                                    deviceWatcherDevices.insert_or_assign(deviceId, deviceInfo);
                                                    onDeviceInfoReceived(deviceInfo);
                                                    // On Device Added
                                                  });

    // Update only if device is already discovered in deviceWatcher.Added
    deviceWatcherUpdatedToken = deviceWatcher.Updated([this](DeviceWatcher sender, DeviceInformationUpdate deviceInfoUpdate)
                                                      {
                                                        std::string deviceId = winrt::to_string(deviceInfoUpdate.Id());
                                                        auto it = deviceWatcherDevices.find(deviceId);
                                                        if (it != deviceWatcherDevices.end())
                                                        {
                                                          it->second.Update(deviceInfoUpdate);
                                                          onDeviceInfoReceived(it->second);
                                                        }
                                                        // On Device Updated
                                                      });

    deviceWatcherRemovedToken = deviceWatcher.Removed([this](DeviceWatcher sender, DeviceInformationUpdate args)
                                                      {
                                                        std::string deviceId = winrt::to_string(args.Id());
                                                        deviceWatcherDevices.erase(deviceId);
                                                        // On Device Removed
                                                      });
  }

  void UniversalBlePlugin::disposeDeviceWatcher()
  {
    if (deviceWatcher != nullptr)
    {
      if (deviceWatcher.Status() == DeviceWatcherStatus::Started)
        deviceWatcher.Stop();
      deviceWatcher.Added(deviceWatcherAddedToken);
      deviceWatcher.Updated(deviceWatcherUpdatedToken);
      deviceWatcher.Removed(deviceWatcherRemovedToken);
      deviceWatcher = nullptr;
      // Dispose tokens
      deviceWatcherDevices.clear();
    }
  }

  void UniversalBlePlugin::onDeviceInfoReceived(DeviceInformation deviceInfo)
  {
    auto properties = deviceInfo.Properties();

    // Avoid devices if not connectable or if deviceAddressKey is not present
    if (!(properties.HasKey(isConnectableKey) && (properties.Lookup(isConnectableKey).as<IPropertyValue>()).GetBoolean()) || !properties.HasKey(deviceAddressKey))
      return;

    auto bluetoothAddressPropertyValue = properties.Lookup(deviceAddressKey).as<IPropertyValue>();
    std::string deviceAddress = winrt::to_string(bluetoothAddressPropertyValue.GetString());

    // Update device info if already discovered in advertisementWatcher
    if (scanResults.count(deviceAddress) > 0)
    {
      bool isPaired = deviceInfo.Pairing().IsPaired();
      if (properties.HasKey(isPairedKey))
      {
        auto isPairedPropertyValue = properties.Lookup(isPairedKey).as<IPropertyValue>();
        isPaired = isPairedPropertyValue.GetBoolean();
      }

      UniversalBleScanResult universalScanResult(deviceAddress);
      universalScanResult.set_is_paired(isPaired);

      if (!deviceInfo.Name().empty())
        universalScanResult.set_name(winrt::to_string(deviceInfo.Name()));

      if (properties.HasKey(signalStrengthKey))
      {
        auto rssiPropertyValue = properties.Lookup(signalStrengthKey).as<IPropertyValue>();
        int16_t rssi = rssiPropertyValue.GetInt16();
        universalScanResult.set_rssi(rssi);
      }

      pushUniversalScanResult(universalScanResult);
    }
  }

  /// Advertisement received from advertisementWatcher
  void UniversalBlePlugin::BluetoothLEWatcher_Received(BluetoothLEAdvertisementWatcher sender, BluetoothLEAdvertisementReceivedEventArgs args)
  {
    try
    {
      // Avoid devices if they are not connectable
      if (!args.IsConnectable())
        return;

      auto deviceId = _mac_address_to_str(args.BluetoothAddress());
      auto universalScanResult = UniversalBleScanResult(deviceId);
      std::string name = winrt::to_string(args.Advertisement().LocalName());

      // Use CompleteName from dataType if localName is empty
      if (name.empty())
      {
        auto dataSection = args.Advertisement().DataSections();
        for (auto &&data : dataSection)
        {
          auto dataBytes = to_bytevc(data.Data());
          if (data.DataType() == 0x09)
          {
            name = std::string(dataBytes.begin(), dataBytes.end());
            break;
          }
        }
      }

      if (!name.empty())
        universalScanResult.set_name(name);

      auto manufacturerData = parseManufacturerDataHead(args.Advertisement(), deviceId);
      universalScanResult.set_manufacturer_data_head(manufacturerData);
      universalScanResult.set_rssi(args.RawSignalStrengthInDBm());

      // Add services
      flutter::EncodableList services = flutter::EncodableList();
      for (auto &&uuid : args.Advertisement().ServiceUuids())
        services.push_back(guid_to_uuid(uuid));
      universalScanResult.set_services(services);

      // check if this device already discovered in deviceWatcher
      auto it = deviceWatcherDevices.find(deviceId);
      if (it != deviceWatcherDevices.end())
      {
        auto &deviceInfo = it->second;
        auto properties = deviceInfo.Properties();

        // Update Paired Status
        bool isPaired = deviceInfo.Pairing().IsPaired();
        if (properties.HasKey(isPairedKey))
          isPaired = (properties.Lookup(isPairedKey).as<IPropertyValue>()).GetBoolean();
        universalScanResult.set_is_paired(isPaired);

        // Update Name
        if (name.empty() && !deviceInfo.Name().empty())
          universalScanResult.set_name(winrt::to_string(deviceInfo.Name()));
      }

      pushUniversalScanResult(universalScanResult);
    }
    catch (...)
    {
      std::cout << "ScanResultErrorInParsing" << std::endl;
    }
  }

  AvailabilityState UniversalBlePlugin::getAvailabilityStateFromRadio(RadioState radioState)
  {
    auto state = [=]() -> AvailabilityState
    {
      if (radioState == RadioState::Unknown)
      {
        return AvailabilityState::unknown;
      }
      else if (radioState == RadioState::Off)
      {
        return AvailabilityState::poweredOff;
      }
      else if (radioState == RadioState::On)
      {
        return AvailabilityState::poweredOn;
      }
      else if (radioState == RadioState::Disabled)
      {
        return AvailabilityState::unsupported;
      }
      else
      {
        return AvailabilityState::unknown;
      }
    }();
    return state;
  }

  void UniversalBlePlugin::Radio_StateChanged(Radio radio, IInspectable args)
  {
    auto radioState = !radio ? RadioState::Disabled : radio.State();
    if (oldRadioState == radioState)
    {
      return;
    }
    oldRadioState = radioState;
    auto state = getAvailabilityStateFromRadio(radioState);

    uiThreadHandler_.Post([state]
                          { callbackChannel->OnAvailabilityChanged(static_cast<int>(state), SuccessCallback, ErrorCallback); });
  }

  std::string UniversalBlePlugin::GattCommunicationStatusToString(GattCommunicationStatus status)
  {
    switch (status)
    {
    case GattCommunicationStatus::Success:
      return "Success";
    case GattCommunicationStatus::Unreachable:
      return "Unreachable";
    case GattCommunicationStatus::ProtocolError:
      return "ProtocolError";
    case GattCommunicationStatus::AccessDenied:
      return "AccessDenied";
    default:
      return "Unknown";
    }
  }

  winrt::fire_and_forget UniversalBlePlugin::WriteAsync(GattCharacteristic characteristic, GattWriteOption writeOption,
                                                        const std::vector<uint8_t> &value, std::function<void(std::optional<FlutterError> reply)> result)
  {
    try
    {
      auto writeResult = co_await characteristic.WriteValueAsync(from_bytevc(value), writeOption);
      switch (writeResult)
      {
      case GenericAttributeProfile::GattCommunicationStatus::Success:
        result(std::nullopt);
        co_return;
      case GenericAttributeProfile::GattCommunicationStatus::Unreachable:
        result(FlutterError("Unreachable", "Failed to write value"));
        co_return;
      case GenericAttributeProfile::GattCommunicationStatus::ProtocolError:
        result(FlutterError("ProtocolError", "Failed to write value"));
        co_return;
      case GenericAttributeProfile::GattCommunicationStatus::AccessDenied:
        result(FlutterError("AccessDenied", "Failed to write value"));
        co_return;
      default:
        result(FlutterError("Failed", "Failed to write value"));
        co_return;
      }
    }
    catch (const winrt::hresult_error &err)
    {
      int errorCode = err.code();
      std::cout << "WriteValueLog: " << winrt::to_string(err.message()) << " ErrorCode: " << std::to_string(errorCode) << std::endl;
      result(FlutterError(std::to_string(errorCode), winrt::to_string(err.message())));
    }
    catch (...)
    {
      result(FlutterError("WriteFailed", "Unknown error"));
    }
  }

  winrt::fire_and_forget UniversalBlePlugin::ConnectAsync(uint64_t bluetoothAddress)
  {
    BluetoothLEDevice device = co_await BluetoothLEDevice::FromBluetoothAddressAsync(bluetoothAddress);
    std::cout << "ConnectionLog: Device found" << std::endl;
    if (!device)
    {
      std::cout << "ConnectionLog: ConnectionFailed: Failed to get device" << std::endl;
      uiThreadHandler_.Post([bluetoothAddress]
                            { callbackChannel->OnConnectionChanged(_mac_address_to_str(bluetoothAddress), static_cast<int>(ConnectionState::disconnected), SuccessCallback, ErrorCallback); });

      co_return;
    }
    auto servicesResult = co_await device.GetGattServicesAsync((BluetoothCacheMode::Uncached));
    auto status = servicesResult.Status();
    if (status != GattCommunicationStatus::Success)
    {
      std::cout << "ConnectionFailed: Failed to get services: " << GattCommunicationStatusToString(status) << std::endl;
      uiThreadHandler_.Post([bluetoothAddress]
                            { callbackChannel->OnConnectionChanged(_mac_address_to_str(bluetoothAddress), static_cast<int>(ConnectionState::disconnected), SuccessCallback, ErrorCallback); });

      co_return;
    }
    std::cout << "ConnectionLog: Services discovered" << std::endl;
    std::unordered_map<std::string, GattServiceObject> gatt_map_;
    auto gatt_services = servicesResult.Services();
    for (GattDeviceService &&service : gatt_services)
    {
      GattServiceObject gatt_service;
      gatt_service.obj = service;
      std::string service_uuid = guid_to_uuid(service.Uuid());
      auto characteristics_result = co_await service.GetCharacteristicsAsync(BluetoothCacheMode::Uncached);
      if (characteristics_result.Status() != GattCommunicationStatus::Success)
      {
        std::cout << "Failed to get characteristics for service: " << service_uuid << ", With Status: " << GattCommunicationStatusToString(characteristics_result.Status()) << std::endl;
        continue;
        // PostConnectionUpdate(bluetoothAddress, ConnectionState::disconnected);
        // co_return;
      }
      auto gatt_characteristics = characteristics_result.Characteristics();
      for (GattCharacteristic &&characteristic : gatt_characteristics)
      {
        GattCharacteristicObject gatt_characteristic;
        gatt_characteristic.obj = characteristic;
        std::string characteristic_uuid = guid_to_uuid(characteristic.Uuid());
        gatt_service.characteristics.insert_or_assign(characteristic_uuid, std::move(gatt_characteristic));
      }
      gatt_map_.insert_or_assign(service_uuid, std::move(gatt_service));
    }

    winrt::event_token connnectionStatusChangedToken = device.ConnectionStatusChanged({this, &UniversalBlePlugin::BluetoothLEDevice_ConnectionStatusChanged});
    auto deviceAgent = std::make_unique<BluetoothDeviceAgent>(device, connnectionStatusChangedToken, gatt_map_);
    auto pair = std::make_pair(bluetoothAddress, std::move(deviceAgent));
    connectedDevices.insert(std::move(pair));
    std::cout << "ConnectionLog: Connected" << std::endl;
    uiThreadHandler_.Post([bluetoothAddress]
                          { callbackChannel->OnConnectionChanged(_mac_address_to_str(bluetoothAddress), static_cast<int>(ConnectionState::connected), SuccessCallback, ErrorCallback); });
  }

  void UniversalBlePlugin::BluetoothLEDevice_ConnectionStatusChanged(BluetoothLEDevice sender, IInspectable args)
  {
    if (sender.ConnectionStatus() == BluetoothConnectionStatus::Disconnected)
    {
      CleanConnection(sender.BluetoothAddress());
      auto bluetoothAddress = sender.BluetoothAddress();
      uiThreadHandler_.Post([bluetoothAddress]
                            { callbackChannel->OnConnectionChanged(_mac_address_to_str(bluetoothAddress), static_cast<int>(ConnectionState::disconnected), SuccessCallback, ErrorCallback); });
    }
  }

  void UniversalBlePlugin::CleanConnection(uint64_t bluetoothAddress)
  {
    auto node = connectedDevices.extract(bluetoothAddress);
    if (!node.empty())
    {
      auto deviceAgent = std::move(node.mapped());
      deviceAgent->device.ConnectionStatusChanged(deviceAgent->connnectionStatusChangedToken);
      // Clean up all characteristics tokens
      for (auto &servicePair : deviceAgent->gatt_map_)
      {
        auto &service = servicePair.second;
        for (auto &characteristicPair : service.characteristics)
        {
          GattCharacteristicObject &characteristic = characteristicPair.second;
          auto gattCharacteristic = characteristic.obj;
          std::stringstream uniqTokenKeyStream;
          uniqTokenKeyStream << to_uuidstr(gattCharacteristic.Uuid()) << _mac_address_to_str(gattCharacteristic.Service().Device().BluetoothAddress());
          std::string uniqTokenKey = uniqTokenKeyStream.str();
          if (characteristicsTokens.count(uniqTokenKey) != 0)
          {
            characteristic.obj.ValueChanged(characteristicsTokens[uniqTokenKey]);
            characteristicsTokens[uniqTokenKey] = {0};
          }
        }
      }
      deviceAgent->gatt_map_.clear();
    }
  }

  winrt::fire_and_forget UniversalBlePlugin::GetConnectedDevicesAsync(
      std::vector<std::string> with_services,
      std::function<void(ErrorOr<flutter::EncodableList> reply)> result)
  {
    try
    {
      auto selector = BluetoothLEDevice::GetDeviceSelectorFromConnectionStatus(BluetoothConnectionStatus::Connected);
      Enumeration::DeviceInformationCollection devices = co_await Enumeration::DeviceInformation::FindAllAsync(selector);
      flutter::EncodableList results = flutter::EncodableList();
      for (auto &&deviceInfo : devices)
      {
        try
        {
          BluetoothLEDevice device = co_await BluetoothLEDevice::FromIdAsync(deviceInfo.Id());
          auto deviceId = _mac_address_to_str(device.BluetoothAddress());
          // Filter by services
          if (!with_services.empty())
          {
            auto serviceResult = co_await device.GetGattServicesAsync(BluetoothCacheMode::Cached);
            if (serviceResult.Status() == GattCommunicationStatus::Success)
            {
              bool hasService = false;
              for (auto service : serviceResult.Services())
              {
                std::string serviceUUID = to_uuidstr(service.Uuid());
                if (std::find(with_services.begin(), with_services.end(), serviceUUID) != with_services.end())
                {
                  hasService = true;
                  break;
                }
              }
              if (!hasService)
                continue;
            }
          }
          // Add to results, if pass all filters
          auto universalScanResult = UniversalBleScanResult(deviceId);
          universalScanResult.set_name(winrt::to_string(deviceInfo.Name()));
          universalScanResult.set_is_paired(deviceInfo.Pairing().IsPaired());
          results.push_back(flutter::CustomEncodableValue(universalScanResult));
        }
        catch (...)
        {
        }
      }
      result(results);
    }
    catch (const winrt::hresult_error &err)
    {
      int errorCode = err.code();
      std::cout << "GetConnectedDeviceLog: " << winrt::to_string(err.message()) << " ErrorCode: " << std::to_string(errorCode) << std::endl;
      result(FlutterError(std::to_string(errorCode), winrt::to_string(err.message())));
    }
    catch (...)
    {
      std::cout << "Unknown error GetConnectedDevicesAsync" << std::endl;
      result(FlutterError("Unknown error"));
    }
  }

  winrt::fire_and_forget UniversalBlePlugin::DiscoverServicesAsync(BluetoothDeviceAgent &bluetoothDeviceAgent, std::function<void(ErrorOr<flutter::EncodableList> reply)> result)
  {
    try
    {
      auto deviceId = _mac_address_to_str(bluetoothDeviceAgent.device.BluetoothAddress());
      auto serviceResult = co_await bluetoothDeviceAgent.device.GetGattServicesAsync();
      if (serviceResult.Status() != GattCommunicationStatus::Success)
      {
        result(FlutterError("DiscoverServiceError: No services found for device"));
        co_return;
      }
      auto services = serviceResult.Services();
      auto universalServices = flutter::EncodableList();
      for (auto service : serviceResult.Services())
      {
        auto characteristicResult = co_await service.GetCharacteristicsAsync();
        flutter::EncodableList universalCharacteristics;
        if (characteristicResult.Status() == GattCommunicationStatus::Success)
        {
          for (auto c : characteristicResult.Characteristics())
          {
            flutter::EncodableList properties = flutter::EncodableList();
            auto propertiesValue = c.CharacteristicProperties();
            if ((propertiesValue & GattCharacteristicProperties::Broadcast) != GattCharacteristicProperties::None)
            {
              properties.push_back(static_cast<int>(CharacteristicProperty::broadcast));
            }
            if ((propertiesValue & GattCharacteristicProperties::Read) != GattCharacteristicProperties::None)
            {
              properties.push_back(static_cast<int>(CharacteristicProperty::read));
            }
            if ((propertiesValue & GattCharacteristicProperties::Write) != GattCharacteristicProperties::None)
            {
              properties.push_back(static_cast<int>(CharacteristicProperty::write));
            }
            if ((propertiesValue & GattCharacteristicProperties::WriteWithoutResponse) != GattCharacteristicProperties::None)
            {
              properties.push_back(static_cast<int>(CharacteristicProperty::writeWithoutResponse));
            }
            if ((propertiesValue & GattCharacteristicProperties::Notify) != GattCharacteristicProperties::None)
            {
              properties.push_back(static_cast<int>(CharacteristicProperty::notify));
            }
            if ((propertiesValue & GattCharacteristicProperties::Indicate) != GattCharacteristicProperties::None)
            {
              properties.push_back(static_cast<int>(CharacteristicProperty::indicate));
            }
            if ((propertiesValue & GattCharacteristicProperties::AuthenticatedSignedWrites) != GattCharacteristicProperties::None)
            {
              properties.push_back(static_cast<int>(CharacteristicProperty::authenticatedSignedWrites));
            }
            if ((propertiesValue & GattCharacteristicProperties::ExtendedProperties) != GattCharacteristicProperties::None)
            {
              properties.push_back(static_cast<int>(CharacteristicProperty::extendedProperties));
            }
            universalCharacteristics.push_back(
                flutter::CustomEncodableValue(UniversalBleCharacteristic(to_uuidstr(c.Uuid()), properties)));
          }
        }
        else
        {
          std::cout << "Failed to get characteristics for service: " << to_uuidstr(service.Uuid()) << ", With Status: " << GattCommunicationStatusToString(characteristicResult.Status()) << std::endl;
        }
        auto universalBleService = UniversalBleService(to_uuidstr(service.Uuid()));
        universalBleService.set_characteristics(universalCharacteristics);
        universalServices.push_back(flutter::CustomEncodableValue(universalBleService));
      }
      result(universalServices);
    }
    catch (...)
    {
      result(FlutterError("DiscoverServiceError: Unknown error"));
      std::cout << "DiscoverServiceError: Unknown error" << '\n';
    }
  }

  winrt::fire_and_forget UniversalBlePlugin::IsPairedAsync(
      std::string device_id,
      std::function<void(ErrorOr<bool> reply)> result)
  {
    try
    {
      auto device = co_await BluetoothLEDevice::FromBluetoothAddressAsync(_str_to_mac_address(device_id));
      bool isPaired = device.DeviceInformation().Pairing().IsPaired();
      result(isPaired);
    }
    catch (...)
    {
      std::cout << "IsPairedAsync: Error " << std::endl;
      result(FlutterError("Unknown error"));
    }
  };

  winrt::fire_and_forget UniversalBlePlugin::SetNotifiableAsync(BluetoothDeviceAgent &bluetoothDeviceAgent, const std::string &service,
                                                                const std::string &characteristic, GattClientCharacteristicConfigurationDescriptorValue descriptorValue)
  {
    GattCharacteristicObject &gatt_characteristic_holder = bluetoothDeviceAgent._fetch_characteristic(service, characteristic);
    GattCharacteristic gattCharacteristic = gatt_characteristic_holder.obj;

    auto uuid = to_uuidstr(gattCharacteristic.Uuid());
    // Write to the descriptor.
    try
    {
      auto status = co_await gattCharacteristic.WriteClientCharacteristicConfigurationDescriptorAsync(descriptorValue);
      switch (status)
      {
      case GattCommunicationStatus::Success:
        break;
      case GattCommunicationStatus::Unreachable:
        std::cout << "FailedToSubscribe: Unreachable" << to_uuidstr(gattCharacteristic.Uuid()) << std::endl;
        break;
      case GattCommunicationStatus::ProtocolError:
        std::cout << "FailedToSubscribe: ProtocolError" << to_uuidstr(gattCharacteristic.Uuid()) << std::endl;
        break;
      case GattCommunicationStatus::AccessDenied:
        std::cout << "FailedToSubscribe: AccessDenied" << to_uuidstr(gattCharacteristic.Uuid()) << std::endl;
        break;
      default:
        std::cout << "FailedToSubscribe: Unknown" << to_uuidstr(gattCharacteristic.Uuid()) << std::endl;
      }
      if (status != GattCommunicationStatus::Success)
        co_return;
    }
    catch (...)
    {
      std::cout << "FailedToPerformThisOperationOn: " << to_uuidstr(gattCharacteristic.Uuid()) << std::endl;
      co_return;
    }
    // create uniqKey with uuid and deviceId
    // TODO: store token key in gatt_characteristic_t struct instead of using map
    std::stringstream uniqTokenKeyStream;
    uniqTokenKeyStream << uuid << _mac_address_to_str(gattCharacteristic.Service().Device().BluetoothAddress());
    auto uniqTokenKey = uniqTokenKeyStream.str();

    // Register/UnRegister handler for the ValueChanged event.
    if (descriptorValue == GattClientCharacteristicConfigurationDescriptorValue::None)
    {
      if (characteristicsTokens.count(uniqTokenKey) != 0)
      {
        gattCharacteristic.ValueChanged(characteristicsTokens[uniqTokenKey]);
        characteristicsTokens[uuid] = {0};
        std::cout << "Unsubscribed " << to_uuidstr(gattCharacteristic.Uuid()) << std::endl;
      }
    }
    else
    {
      // If a notification for the given characteristic is already in progress, swap the callbacks.
      if (characteristicsTokens.count(uniqTokenKey) != 0)
      {
        std::cout << "A notification for the given characteristic is already in progress. Swapping callbacks." << std::endl;
        gattCharacteristic.ValueChanged(characteristicsTokens[uniqTokenKey]);
        characteristicsTokens[uniqTokenKey] = {0};
      }
      characteristicsTokens[uniqTokenKey] = gattCharacteristic.ValueChanged({this, &UniversalBlePlugin::GattCharacteristic_ValueChanged});
    }
  }

  void UniversalBlePlugin::GattCharacteristic_ValueChanged(GattCharacteristic sender, GattValueChangedEventArgs args)
  {
    auto uuid = to_uuidstr(sender.Uuid());
    auto bytes = to_bytevc(args.CharacteristicValue());
    uiThreadHandler_.Post([sender, uuid, bytes]
                          { callbackChannel->OnValueChanged(_mac_address_to_str(sender.Service().Device().BluetoothAddress()), uuid, bytes, SuccessCallback, ErrorCallback); });
  }

  std::string UniversalBlePlugin::parsePairingFailError(Enumeration::DevicePairingResult result)
  {
    switch (result.Status())
    {
    case Enumeration::DevicePairingResultStatus::Paired:
      return "";
    case Enumeration::DevicePairingResultStatus::AlreadyPaired:
      return "AlreadyPaired";

    case Enumeration::DevicePairingResultStatus::ConnectionRejected:
      return "ConnectionRejected";

    case Enumeration::DevicePairingResultStatus::NotPaired:
      return "NotPaired";

    case Enumeration::DevicePairingResultStatus::NotReadyToPair:
      return "NotReadyToPair";

    case Enumeration::DevicePairingResultStatus::TooManyConnections:
      return "TooManyConnections";

    case Enumeration::DevicePairingResultStatus::HardwareFailure:
      return "HardwareFailure";

    case Enumeration::DevicePairingResultStatus::AuthenticationTimeout:
      return "AuthenticationTimeout";

    case Enumeration::DevicePairingResultStatus::AuthenticationNotAllowed:
      return "AuthenticationNotAllowed";

    case Enumeration::DevicePairingResultStatus::AuthenticationFailure:
      return "AuthenticationFailure";

    case Enumeration::DevicePairingResultStatus::NoSupportedProfiles:
      return "NoSupportedProfiles";

    case Enumeration::DevicePairingResultStatus::ProtectionLevelCouldNotBeMet:
      return "ProtectionLevelCouldNotBeMet";

    case Enumeration::DevicePairingResultStatus::AccessDenied:
      return "AccessDenied";

    case Enumeration::DevicePairingResultStatus::InvalidCeremonyData:
      return "InvalidCeremonyData";

    case Enumeration::DevicePairingResultStatus::PairingCanceled:
      return "PairingCanceled";

    case Enumeration::DevicePairingResultStatus::OperationAlreadyInProgress:
      return "OperationAlreadyInProgress";

    case Enumeration::DevicePairingResultStatus::RequiredHandlerNotRegistered:
      return "RequiredHandlerNotRegistered";

    case Enumeration::DevicePairingResultStatus::RejectedByHandler:
      return "RejectedByHandler";

    case Enumeration::DevicePairingResultStatus::RemoteDeviceHasAssociation:
      return "RemoteDeviceHasAssociation";

    case Enumeration::DevicePairingResultStatus::Failed:
      return "Failed to pair";

    default:
      return "Failed to pair";
    }
  }

} // namespace universal_ble