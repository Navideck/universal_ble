#include "universal_ble_plugin.h"
#include <windows.h>

#include <flutter/plugin_registrar_windows.h>

#include <map>
#include <memory>
#include <sstream>
#include <algorithm>
#include <iomanip>
#include <thread>
#include "UniversalBle.g.h"
#include "Utils.h"
#include "universal_enum.h"
#include <regex>

#define WM_AVAILABILITY_CHANGE WM_USER + 101
#define WM_PAIR_CHANGE WM_USER + 102
#define WM_SCAN_RESULT WM_USER + 103
#define WM_VALUE_CHANGE WM_USER + 104
#define WM_CONNECTION_CHANGE WM_USER + 105

namespace universal_ble
{
  using universal_ble::ErrorOr;
  using universal_ble::UniversalBleCallbackChannel;
  using universal_ble::UniversalBlePlatformChannel;
  using universal_ble::UniversalBleScanResult;

  auto isConnectableKey = L"System.Devices.Aep.Bluetooth.Le.IsConnectable";
  auto isConnectedKey = L"System.Devices.Aep.IsConnected";
  auto isPairedKey = L"System.Devices.Aep.IsPaired";
  auto isPresentKey = L"System.Devices.Aep.IsPresent";
  auto deviceAddressKey = L"System.Devices.Aep.DeviceAddress";
  auto signalStrengthKey = L"System.Devices.Aep.SignalStrength";

  std::unique_ptr<UniversalBleCallbackChannel> callbackChannel;
  std::map<std::string, winrt::event_token> characteristicsTokens{};

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

  UniversalBlePlugin::UniversalBlePlugin(flutter::PluginRegistrarWindows *registrar) : registrar_(registrar)
  {
    if (window_proc_delegate_id_ == -1)
    {
      window_proc_delegate_id_ = registrar_->RegisterTopLevelWindowProcDelegate(
          std::bind(
              &UniversalBlePlugin::WindowProcDelegate, this,
              std::placeholders::_1, std::placeholders::_2,
              std::placeholders::_3, std::placeholders::_4)

      );
    }
    InitializeAsync();
  }

  UniversalBlePlugin::~UniversalBlePlugin()
  {
    if (window_proc_delegate_id_ != -1)
    {
      registrar_->UnregisterTopLevelWindowProcDelegate(
          static_cast<int32_t>(window_proc_delegate_id_));
    }
  }

  HWND UniversalBlePlugin::GetWindow()
  {
    return ::GetAncestor(registrar_->GetView()->GetNativeWindow(), GA_ROOT);
  }

  /// Background Messages Handler
  std::optional<LRESULT> UniversalBlePlugin::WindowProcDelegate(HWND hwnd, UINT message, WPARAM wp, LPARAM lp)
  {
    switch (message)
    {
    case WM_SCAN_RESULT:
    {
      UniversalBleScanResult *scanResult = reinterpret_cast<UniversalBleScanResult *>(wp);
      callbackChannel->OnScanResult(*scanResult, SuccessCallback, ErrorCallback);
      delete scanResult;
      return 0;
    }
    case WM_AVAILABILITY_CHANGE:
    {
      callbackChannel->OnAvailabilityChanged(static_cast<int>(wp), SuccessCallback, ErrorCallback);
      return 0;
    }
    case WM_CONNECTION_CHANGE:
    {
      ConnectionStateStruct *connectionStateStruct = reinterpret_cast<ConnectionStateStruct *>(wp);
      callbackChannel->OnConnectionChanged(connectionStateStruct->deviceId, connectionStateStruct->connectionState, SuccessCallback, ErrorCallback);
      delete connectionStateStruct;
      return 0;
    }
    case WM_VALUE_CHANGE:
    {
      ValueChangeStruct *valueChangeStruct = reinterpret_cast<ValueChangeStruct *>(wp);
      callbackChannel->OnValueChanged(valueChangeStruct->deviceId, valueChangeStruct->characteristicId, valueChangeStruct->value, SuccessCallback, ErrorCallback);
      delete valueChangeStruct;
      return 0;
    }
    case WM_PAIR_CHANGE:
    {
      PairStateStruct *pairStateStruct = reinterpret_cast<PairStateStruct *>(wp);
      callbackChannel->OnPairStateChange(pairStateStruct->deviceId, pairStateStruct->isPaired, &pairStateStruct->errorMessage, SuccessCallback, ErrorCallback);
      delete pairStateStruct;
      return 0;
    }
    }
    return std::nullopt;
  }

  void UniversalBlePlugin::PostConnectionUpdate(uint64_t bluetoothAddress, ConnectionState connectionState)
  {
    ConnectionStateStruct *connectionStateStruct = new ConnectionStateStruct(_mac_address_to_str(bluetoothAddress), static_cast<int>(connectionState));
    ::PostMessage(GetWindow(), WM_CONNECTION_CHANGE, reinterpret_cast<WPARAM>(connectionStateStruct), 0);
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

  std::optional<FlutterError> UniversalBlePlugin::StartScan()
  {
    if (bluetoothRadio && bluetoothRadio.State() == RadioState::On)
    {
      if (!bluetoothLEWatcher)
      {
        bluetoothLEWatcher = BluetoothLEAdvertisementWatcher();
        bluetoothLEWatcher.ScanningMode(BluetoothLEScanningMode::Active);
        bluetoothLEWatcherReceivedToken = bluetoothLEWatcher.Received({this, &UniversalBlePlugin::BluetoothLEWatcher_Received});
        // auto filter = BluetoothLEAdvertisementFilter();
        // auto serviceUuid = uuid_to_guid("00001101-0000-1000-8000-00805F9B34FB");
        // filter.Advertisement().ServiceUuids().Append(serviceUuid);
        // filter.Advertisement().ManufacturerData().Append(Bluetooth::Advertisement::BluetoothLEManufacturerData{0x004C});
        // bluetoothLEWatcher.AdvertisementFilter(filter);
        // bluetoothLEWatcher.Stopped([this](BluetoothLEAdvertisementWatcher sender, BluetoothLEAdvertisementWatcherStoppedEventArgs args)
        //                            {
        //                              std::cout << "BluetoothLEAdvertisementWatcher Stopped" << std::endl;
        //                              bluetoothLEWatcher.Received(bluetoothLEWatcherReceivedToken);
        //                              bluetoothLEWatcher = nullptr; });
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
    PostConnectionUpdate(deviceAddress, ConnectionState::disconnected);
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
      gatt_characteristic_t &gatt_characteristic_holder = bluetoothAgent._fetch_characteristic(service, characteristic);
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
      gatt_characteristic_t &gatt_characteristic_holder = bluetoothAgent._fetch_characteristic(service, characteristic);
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
      gatt_characteristic_t &gatt_characteristic_holder = bluetoothAgent._fetch_characteristic(service, characteristic);
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
      auto async_c = gatt_characteristic_holder.obj.WriteValueAsync(from_bytevc(value), writeOption);
      async_c.Completed([&, result](IAsyncOperation<GattCommunicationStatus> const &sender, AsyncStatus const args)
                        {
                          auto writeResult = sender.GetResults();
                          switch (writeResult)
                          {
                          case GenericAttributeProfile::GattCommunicationStatus::Success:
                            result(std::nullopt);
                            return;
                          case GenericAttributeProfile::GattCommunicationStatus::Unreachable:
                            result(FlutterError("Unreachable", "Failed to write value"));
                            return;
                          case GenericAttributeProfile::GattCommunicationStatus::ProtocolError:
                            result(FlutterError("ProtocolError", "Failed to write value"));
                            return;
                          case GenericAttributeProfile::GattCommunicationStatus::AccessDenied:
                            result(FlutterError("AccessDenied", "Failed to write value"));
                            return;
                          default:
                            result(FlutterError("Failed", "Failed to write value"));
                            return;
                          } });
    }
    catch (const FlutterError &err)
    {
      result(err);
    }
    catch (...)
    {
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
      auto deviceInformation = device.DeviceInformation();
      bool isPaired = deviceInformation.Pairing().IsPaired();
      if (isPaired)
        return FlutterError("Device is already paired");
      bool canPair = deviceInformation.Pairing().CanPair();
      if (!canPair)
        return FlutterError("Device is not pairable");

      auto customPairing = deviceInformation.Pairing().Custom();
      winrt::event_token token = customPairing.PairingRequested([this](const Enumeration::DeviceInformationCustomPairing &sender, const Enumeration::DevicePairingRequestedEventArgs &eventArgs)
                                                                {
                                                                // eventArgs.AcceptWithPasswordCredential(nullptr, nullptr);
                                                                // eventArgs.Pin();
                                                                // Accept all pairing request
                                                                eventArgs.Accept(); });
      // DevicePairingKinds => None, ConfirmOnly, DisplayPin, ProvidePin, ConfirmPinMatch, ProvidePasswordCredential
      // DevicePairingProtectionLevel =>  Default, None, Encryption, EncryptionAndAuthentication
      auto async_c = customPairing.PairAsync(
          Enumeration::DevicePairingKinds::ConfirmOnly,
          Enumeration::DevicePairingProtectionLevel::None);
      async_c.Completed([this, customPairing, token, device_id](IAsyncOperation<DevicePairingResult> const &sender, AsyncStatus const args)
                        {
                          auto result = sender.GetResults();
                          customPairing.PairingRequested(token);
                          auto isPaired = result.Status() == Enumeration::DevicePairingResultStatus::Paired;
                          // Post to main thread
                          PairStateStruct *pairStateStruct = new PairStateStruct(device_id, isPaired, parsePairingFailError(result)); 
                          ::PostMessage(GetWindow(), WM_PAIR_CHANGE, reinterpret_cast<WPARAM>(pairStateStruct), 0); });

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

  hstring parseBluetoothDeviceId(hstring deviceId)
  {
    auto deviceIdString = winrt::to_string(deviceId);
    std::regex macAddressRegex("-([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})");
    std::smatch match;
    if (std::regex_search(deviceIdString, match, macAddressRegex))
    {
      auto formattedDeviceId = match.str();
      if (formattedDeviceId[0] == '-')
        formattedDeviceId.erase(0, 1);
      return winrt::to_hstring(formattedDeviceId);
    }
    return hstring(L"");
  }

  winrt::fire_and_forget UniversalBlePlugin::InitializeAsync()
  {
    auto bluetoothAdapter = co_await BluetoothAdapter::GetDefaultAsync();
    bluetoothRadio = co_await bluetoothAdapter.GetRadioAsync();
    if (bluetoothRadio)
    {
      radioStateChangedRevoker = bluetoothRadio.StateChanged(winrt::auto_revoke, {this, &UniversalBlePlugin::Radio_StateChanged});
    }
  }

  void UniversalBlePlugin::pushUniversalScanResult(UniversalBleScanResult scanResult)
  {
    // first check if present in scanResults, if yes then merge the scan result
    if (scanResults.count(scanResult.device_id()) > 0)
    {
      auto _scanResult = scanResults.at(scanResult.device_id());
      auto _rssi = _scanResult.rssi();
      auto _name = _scanResult.name();
      auto _isPaired = _scanResult.is_paired();
      auto _manufacturerData = _scanResult.manufacturer_data_head();

      bool shouldUpdate = false;
      if (scanResult.rssi() == nullptr && _rssi != nullptr)
      {
        scanResult.set_rssi(_rssi);
        shouldUpdate = true;
      }
      if ((scanResult.name() == nullptr || scanResult.name()->empty()) && (_name != nullptr && !_name->empty()))
      {
        scanResult.set_name(*_name);
        shouldUpdate = true;
      }
      if (scanResult.is_paired() == nullptr && _isPaired != nullptr)
      {
        scanResult.set_is_paired(_isPaired);
        shouldUpdate = true;
      }
      if (scanResult.manufacturer_data_head() == nullptr && _manufacturerData != nullptr)
      {
        scanResult.set_manufacturer_data_head(_manufacturerData);
        shouldUpdate = true;
      }

      // if nothing to update then return
      // if (!shouldUpdate)
      // {
      //   return;
      // }

      // remove old scan result
      scanResults.erase(scanResult.device_id());
    }

    scanResults.insert(std::make_pair(scanResult.device_id(), scanResult));
    UniversalBleScanResult *scanResultPtr = new UniversalBleScanResult(scanResult);
    ::PostMessage(GetWindow(), WM_SCAN_RESULT, reinterpret_cast<WPARAM>(scanResultPtr), 0);
  }

  void UniversalBlePlugin::setupDeviceWatcher()
  {
    if (deviceWatcher != nullptr)
    {
      return;
    }
    auto BTLEDeviceWatcherAQSString = L"(System.Devices.Aep.ProtocolId:=\"{bb7bb05e-5972-42b5-94fc-76eaa7084d49}\")";
    std::vector<hstring> requestedProperties = {
        deviceAddressKey,
        isConnectedKey,
        isPairedKey,
        isPresentKey,
        isConnectableKey,
        signalStrengthKey,
    };
    deviceWatcher = DeviceInformation::CreateWatcher(
        BTLEDeviceWatcherAQSString,
        requestedProperties,
        DeviceInformationKind::AssociationEndpoint);
    // deviceWatcher = DeviceInformation::CreateWatcher(BluetoothLEDevice::GetDeviceSelector());
    deviceWatcherAddedToken = deviceWatcher.Added({this, &UniversalBlePlugin::onDeviceAdded});
    deviceWatcherUpdatedToken = deviceWatcher.Updated({this, &UniversalBlePlugin::onDeviceUpdated});
    deviceWatcherRemovedToken = deviceWatcher.Removed({this, &UniversalBlePlugin::onDeviceRemoved});
    deviceWatcherEnumerationCompletedToken = deviceWatcher.EnumerationCompleted([this](DeviceWatcher sender, IInspectable args)
                                                                                {
                                                                                  std::cout << "DeviceWatcher EnumerationCompleted" << std::endl;
                                                                                  // disposeDeviceWatcher();
                                                                                  // keep deviceWatcher running
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
      // scanResults.clear();
    }
  }

  void UniversalBlePlugin::onDeviceInfoRecieved(DeviceInformation deviceInfo)
  {
    auto properties = deviceInfo.Properties();
    auto IsConnectable = properties.HasKey(isConnectableKey) && (properties.Lookup(isConnectableKey).as<IPropertyValue>()).GetBoolean();
    // auto IsPresent = properties.HasKey(isPresentKey) && (properties.Lookup(isPresentKey).as<IPropertyValue>()).GetBoolean();
    // Avoid devices if not connectable
    if (!IsConnectable || !properties.HasKey(deviceAddressKey))
    {
      return;
    }
    auto bluetoothAddressPropertyValue = properties.Lookup(deviceAddressKey).as<IPropertyValue>();
    std::string deviceAddress = winrt::to_string(bluetoothAddressPropertyValue.GetString());
    bool isPaired = deviceInfo.Pairing().IsPaired();
    if (properties.HasKey(isPairedKey))
    {
      auto isPairedPropertyValue = properties.Lookup(isPairedKey).as<IPropertyValue>();
      isPaired = isPairedPropertyValue.GetBoolean();
    }
    auto universalScanResult = UniversalBleScanResult(deviceAddress);
    universalScanResult.set_is_paired(isPaired);
    if (!deviceInfo.Name().empty())
      universalScanResult.set_name(winrt::to_string(deviceInfo.Name()));
    if (properties.HasKey(signalStrengthKey))
    {
      auto rssiPropertyValue = properties.Lookup(signalStrengthKey).as<IPropertyValue>();
      int16_t rssi = rssiPropertyValue.GetInt16();
      universalScanResult.set_rssi(rssi);
    }

    // Avoid devices if not reported by advertisement watcher
    if (scanResults.count(deviceAddress) == 0)
    {
      return;
    }

    // deviceConnectableStatus[_str_to_mac_address(deviceAddress)] = IsConnectable;
    pushUniversalScanResult(universalScanResult);
  }

  /// Device Added from DeviceWatcher
  void UniversalBlePlugin::onDeviceAdded(DeviceWatcher sender, DeviceInformation deviceInfo)
  {
    std::string deviceId = winrt::to_string(deviceInfo.Id());
    if (deviceWatcherDevices.count(deviceId) > 0)
      deviceWatcherDevices.erase(deviceId);
    deviceWatcherDevices.insert(std::make_pair(deviceId, deviceInfo));
    onDeviceInfoRecieved(deviceInfo);
  }

  void UniversalBlePlugin::onDeviceUpdated(DeviceWatcher sender, DeviceInformationUpdate deviceInfoUpdate)
  {
    std::string deviceId = winrt::to_string(deviceInfoUpdate.Id());
    // Update only if device is already discovered in deviceWatcher.Added
    if (deviceWatcherDevices.count(deviceId) > 0)
    {
      DeviceInformation deviceInfo = deviceWatcherDevices.at(deviceId);
      deviceInfo.Update(deviceInfoUpdate);
      onDeviceInfoRecieved(deviceInfo);
    }
  }

  void UniversalBlePlugin::onDeviceRemoved(DeviceWatcher sender, DeviceInformationUpdate args)
  {
    std::string deviceId = winrt::to_string(args.Id());
    if (deviceWatcherDevices.count(deviceId) > 0)
      deviceWatcherDevices.erase(deviceId);
  }

  /// Advertisement received from advertisementWatcher
  void UniversalBlePlugin::BluetoothLEWatcher_Received(BluetoothLEAdvertisementWatcher sender, BluetoothLEAdvertisementReceivedEventArgs args)
  {
    try
    {
      // Avoid devices if they are not connectable
      if (args.IsConnectable())
      {
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
        {
          universalScanResult.set_name(name);
        }
        auto manufacturerData = parseManufacturerDataHead(args.Advertisement(), deviceId);
        universalScanResult.set_manufacturer_data_head(manufacturerData);
        universalScanResult.set_rssi(args.RawSignalStrengthInDBm());

        // std::cout << "Received: " << deviceId << " Manf: " << std::endl;
        std::copy(manufacturerData.begin(), manufacturerData.end(), std::ostream_iterator<int>(std::cout, " "));
        std::cout << std::endl;

        // check if this device already discovered in deviceWatcher
        if (deviceWatcherDevices.count(deviceId) > 0)
        {
          auto deviceInfo = deviceWatcherDevices.at(deviceId);
          auto properties = deviceInfo.Properties();
          // Update Paired Status
          if (properties.HasKey(isPairedKey))
          {
            auto IsPaired = (properties.Lookup(isPairedKey).as<IPropertyValue>()).GetBoolean();
            universalScanResult.set_is_paired(IsPaired);
          }
          else
          {
            universalScanResult.set_is_paired(deviceInfo.Pairing().IsPaired());
          }

          // Update Name
          if (name.empty() && !deviceInfo.Name().empty())
          {
            universalScanResult.set_name(winrt::to_string(deviceInfo.Name()));
          }
        }

        // Cache connectable status
        // deviceConnectableStatus[_str_to_mac_address(deviceId)] = args.IsConnectable();
        pushUniversalScanResult(universalScanResult);
      }
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
    ::PostMessage(GetWindow(), WM_AVAILABILITY_CHANGE, static_cast<int>(state), 0);
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

  winrt::fire_and_forget UniversalBlePlugin::ConnectAsync(uint64_t bluetoothAddress)
  {
    BluetoothLEDevice device = co_await BluetoothLEDevice::FromBluetoothAddressAsync(bluetoothAddress);
    if (!device)
    {
      std::cout << "ConnectionFailed: Failed to get device" << std::endl;
      PostConnectionUpdate(bluetoothAddress, ConnectionState::disconnected);
      co_return;
    }
    auto servicesResult = co_await device.GetGattServicesAsync((BluetoothCacheMode::Uncached));
    auto status = servicesResult.Status();
    if (status != GattCommunicationStatus::Success)
    {
      std::cout << "ConnectionFailed: Failed to get services: " << GattCommunicationStatusToString(status) << std::endl;
      PostConnectionUpdate(bluetoothAddress, ConnectionState::disconnected);
      co_return;
    }

    std::map<std::string, gatt_service_t> gatt_map_;
    auto gatt_services = servicesResult.Services();
    for (GattDeviceService &&service : gatt_services)
    {
      gatt_service_t gatt_service;
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
        gatt_characteristic_t gatt_characteristic;
        gatt_characteristic.obj = characteristic;
        std::string characteristic_uuid = guid_to_uuid(characteristic.Uuid());
        gatt_service.characteristics.emplace(characteristic_uuid, std::move(gatt_characteristic));
      }
      gatt_map_.emplace(service_uuid, std::move(gatt_service));
    }

    winrt::event_token connnectionStatusChangedToken = device.ConnectionStatusChanged({this, &UniversalBlePlugin::BluetoothLEDevice_ConnectionStatusChanged});
    auto deviceAgent = std::make_unique<BluetoothDeviceAgent>(device, connnectionStatusChangedToken, gatt_map_);
    auto pair = std::make_pair(bluetoothAddress, std::move(deviceAgent));
    connectedDevices.insert(std::move(pair));
    PostConnectionUpdate(bluetoothAddress, ConnectionState::connected);
  }

  void UniversalBlePlugin::BluetoothLEDevice_ConnectionStatusChanged(BluetoothLEDevice sender, IInspectable args)
  {
    if (sender.ConnectionStatus() == BluetoothConnectionStatus::Disconnected)
    {
      CleanConnection(sender.BluetoothAddress());
      PostConnectionUpdate(sender.BluetoothAddress(), ConnectionState::disconnected);
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
          gatt_characteristic_t &characteristic = characteristicPair.second;
          auto gattCharacteristic = characteristic.obj;
          auto uniqTokenKey = to_uuidstr(gattCharacteristic.Uuid()) + _mac_address_to_str(gattCharacteristic.Service().Device().BluetoothAddress());
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
        // deviceConnectableStatus[_str_to_mac_address(deviceId)] = true;
      }
      result(results);
    }
    catch (...)
    {
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
      std::cerr << "DiscoverServiceError: Unknown error" << '\n';
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
    gatt_characteristic_t &gatt_characteristic_holder = bluetoothDeviceAgent._fetch_characteristic(service, characteristic);
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
    auto uniqTokenKey = uuid + _mac_address_to_str(gattCharacteristic.Service().Device().BluetoothAddress());

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
    ValueChangeStruct *valueChangeStruct = new ValueChangeStruct(_mac_address_to_str(sender.Service().Device().BluetoothAddress()), uuid, bytes);
    ::PostMessage(GetWindow(), WM_VALUE_CHANGE, reinterpret_cast<WPARAM>(valueChangeStruct), 0);
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