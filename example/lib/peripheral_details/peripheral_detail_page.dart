import 'dart:async';

import 'package:convert/convert.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:universal_ble_example/peripheral_details/widgets/result_widget.dart';
import 'package:universal_ble_example/peripheral_details/widgets/services_list_widget.dart';
import 'package:universal_ble_example/widgets/platform_button.dart';
import 'package:universal_ble_example/widgets/responsive_buttons_grid.dart';
import 'package:universal_ble_example/widgets/responsive_view.dart';

class PeripheralDetailPage extends StatefulWidget {
  final BleDevice bleDevice;
  const PeripheralDetailPage(this.bleDevice, {super.key});

  @override
  State<StatefulWidget> createState() {
    return _PeripheralDetailPageState();
  }
}

class _PeripheralDetailPageState extends State<PeripheralDetailPage> {
  late final bleDevice = widget.bleDevice;
  bool isConnected = false;
  GlobalKey<FormState> valueFormKey = GlobalKey<FormState>();
  List<BleService> discoveredServices = [];
  final List<String> _logs = [];
  final binaryCode = TextEditingController();
  final Set<String> _favoriteServices = {};
  bool _isLoading = false;
  final Map<String, bool> _subscribedCharacteristics = {};

  StreamSubscription? connectionStreamSubscription;
  StreamSubscription? pairingStateSubscription;
  BleService? selectedService;
  BleCharacteristic? selectedCharacteristic;

  @override
  void initState() {
    super.initState();

    connectionStreamSubscription = bleDevice.connectionStream.listen(
      _handleConnectionChange,
    );
    pairingStateSubscription = bleDevice.pairingStateStream.listen(
      _handlePairingStateChange,
    );
    UniversalBle.onValueChange = _handleValueChange;
    _asyncInits();
  }

  void _asyncInits() {
    bleDevice.connectionState.then((state) {
      if (state == BleConnectionState.connected) {
        setState(() {
          isConnected = true;
        });
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
    connectionStreamSubscription?.cancel();
    pairingStateSubscription?.cancel();
    UniversalBle.onValueChange = null;
  }

  void _addLog(String type, dynamic data) {
    setState(() {
      _logs.add('$type: ${data.toString()}');
    });
  }

  void _handleConnectionChange(bool isConnected) {
    debugPrint('_handleConnectionChange $isConnected');
    setState(() {
      this.isConnected = isConnected;
    });
    _addLog('Connection', isConnected ? "Connected" : "Disconnected");
    // Auto Discover Services
    if (this.isConnected) {
      _discoverServices();
    }
  }

  void _handleValueChange(
    String deviceId,
    String characteristicId,
    Uint8List value,
  ) {
    String s = String.fromCharCodes(value);
    String data = '$s\nraw :  ${value.toString()}';
    debugPrint('_handleValueChange $characteristicId, $s');
    _addLog("Value", data);
  }

  void _handlePairingStateChange(bool isPaired) {
    debugPrint('isPaired $isPaired');
    _addLog("PairingStateChange - isPaired", isPaired);
  }

  Future<void> _discoverServices() async {
    const webWarning =
        "Note: Only services added in ScanFilter or WebOptions will be discovered";
    await _executeWithLoading(
      () async {
        var services = await bleDevice.discoverServices();
        debugPrint('${services.length} services discovered');
        debugPrint(services.toString());
        setState(() {
          discoveredServices = services;
        });

        if (kIsWeb) {
          _addLog(
            "DiscoverServices",
            '${services.length} services discovered,\n$webWarning',
          );
        }
      },
      onError: (error) {
        _addLog("DiscoverServicesError", '$error\n${kIsWeb ? webWarning : ""}');
      },
    );
  }

  Future<void> _readValue() async {
    BleCharacteristic? selectedCharacteristic = this.selectedCharacteristic;
    if (selectedCharacteristic == null) return;
    await _executeWithLoading(
      () async {
        Uint8List value = await selectedCharacteristic.read();
        String s = String.fromCharCodes(value);
        String data = '$s\nraw :  ${value.toString()}';
        _addLog('Read', data);
      },
      onError: (error) {
        _addLog('ReadError', '$error');
      },
    );
  }

  Future<void> _writeValue() async {
    BleCharacteristic? selectedCharacteristic = this.selectedCharacteristic;
    if (selectedCharacteristic == null ||
        !valueFormKey.currentState!.validate() ||
        binaryCode.text.isEmpty) {
      return;
    }

    Uint8List value;
    try {
      value = Uint8List.fromList(hex.decode(binaryCode.text));
    } catch (e) {
      _addLog('WriteError', "Error parsing hex $e");
      return;
    }

    bool writeWithResponse = true;
    if (!selectedCharacteristic.properties.contains(
      CharacteristicProperty.write,
    )) {
      writeWithResponse = false;
    }

    await _executeWithLoading(
      () async {
        await selectedCharacteristic.write(
          value,
          withResponse: writeWithResponse,
        );
        _addLog('Write${writeWithResponse ? "" : "WithoutResponse"}', value);
      },
      onError: (error) {
        _addLog('WriteError', '$error');
      },
    );
  }

  Future<void> _subscribeChar() async {
    BleCharacteristic? selectedCharacteristic = this.selectedCharacteristic;
    if (selectedCharacteristic == null) return;
    await _executeWithLoading(
      () async {
        var subscription = _getCharacteristicSubscription(
          selectedCharacteristic,
        );
        if (subscription == null) throw 'No notify or indicate property';
        await subscription.subscribe();
        setState(() {
          _subscribedCharacteristics[selectedCharacteristic.uuid] = true;
        });
        _addLog('BleCharSubscription', 'Subscribed');
      },
      onError: (error) {
        _addLog('NotifyError', error);
      },
    );
  }

  Future<void> _unsubscribeChar() async {
    if (selectedCharacteristic == null) return;
    await _executeWithLoading(
      () async {
        await selectedCharacteristic?.unsubscribe();
        setState(() {
          _subscribedCharacteristics.remove(selectedCharacteristic?.uuid);
        });
        _addLog('BleCharSubscription', 'UnSubscribed');
      },
      onError: (error) {
        _addLog('NotifyError', error);
      },
    );
  }

  Future<void> _subscribeToAllCharacteristics() async {
    if (!isConnected) return;
    await _executeWithLoading(
      () async {
        int successCount = 0;
        int errorCount = 0;
        for (var service in discoveredServices) {
          for (var characteristic in service.characteristics) {
            var subscription = _getCharacteristicSubscription(characteristic);
            if (subscription != null) {
              try {
                await subscription.subscribe();
                setState(() {
                  _subscribedCharacteristics[characteristic.uuid] = true;
                });
                successCount++;
              } catch (e) {
                errorCount++;
                debugPrint('Failed to subscribe to ${characteristic.uuid}: $e');
              }
            }
          }
        }
        _addLog(
          'BleCharSubscription',
          'Subscribed to $successCount characteristics${errorCount > 0 ? ', $errorCount failed' : ''}',
        );
      },
      onError: (error) {
        _addLog('SubscribeToAllCharacteristicsError', error);
      },
    );
  }

  bool _isSystemService(String uuid) {
    final normalized = uuid.toUpperCase().replaceAll('-', '');
    return normalized == '00001800' ||
        normalized == '00001801' ||
        normalized == '0000180A' ||
        normalized.startsWith('000018');
  }

  CharacteristicSubscription? _getCharacteristicSubscription(
    BleCharacteristic characteristic,
  ) {
    var properties = characteristic.properties;
    if (properties.contains(CharacteristicProperty.notify)) {
      return characteristic.notifications;
    } else if (properties.contains(CharacteristicProperty.indicate)) {
      return characteristic.indications;
    }
    return null;
  }

  String _manufacturerDataToHex(ManufacturerData data) {
    final fullData = data.toUint8List();
    return hex.encode(fullData);
  }

  Future<T> _executeWithLoading<T>(
    Future<T> Function() action, {
    Function(dynamic error)? onError,
  }) async {
    setState(() {
      _isLoading = true;
    });
    try {
      return await action();
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void setState(VoidCallback fn) {
    if (mounted) super.setState(fn);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: SelectableText(bleDevice.name ?? "Unknown"),
        centerTitle: false,
        elevation: 4,
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator.adaptive(strokeWidth: 2),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Icon(
              isConnected
                  ? Icons.bluetooth_connected
                  : Icons.bluetooth_disabled,
              color: isConnected ? Colors.greenAccent : Colors.red,
              size: 20,
            ),
          ),
        ],
      ),
      body: ResponsiveView(
        builder: (_, DeviceType deviceType) {
          // Split layout: services on left, details on right (or stacked on mobile)
          return Row(
            children: [
              // Services list (left side on desktop, hidden on mobile - shown below)
              if (deviceType == DeviceType.desktop)
                Expanded(
                  flex: 1,
                  child: Container(
                    color: Theme.of(context).secondaryHeaderColor,
                    child: Column(
                      children: [
                        // Selected service/char always visible at top
                        if (selectedService != null &&
                            selectedCharacteristic != null)
                          Container(
                            color: Theme.of(
                              context,
                            ).primaryColor.withValues(alpha: 0.1),
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.info_outline, size: 16),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: SelectableText(
                                        'Selected: ${selectedCharacteristic!.uuid}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                SelectableText(
                                  'Service: ${selectedService!.uuid}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                SelectableText(
                                  'Properties: ${selectedCharacteristic!.properties.map((e) => e.name).join(", ")}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        Expanded(
                          child: discoveredServices.isEmpty
                              ? const Center(
                                  child: SelectableText(
                                    'No Services Discovered',
                                  ),
                                )
                              : ServicesListWidget(
                                  discoveredServices: discoveredServices,
                                  selectedService: selectedService,
                                  selectedCharacteristic:
                                      selectedCharacteristic,
                                  favoriteServices: _favoriteServices,
                                  subscribedCharacteristics:
                                      _subscribedCharacteristics,
                                  scrollable: true,
                                  onTap: (service, characteristic) {
                                    setState(() {
                                      selectedService = service;
                                      selectedCharacteristic = characteristic;
                                    });
                                  },
                                  onFavoriteToggle: (serviceUuid) {
                                    setState(() {
                                      if (_favoriteServices.contains(
                                        serviceUuid,
                                      )) {
                                        _favoriteServices.remove(serviceUuid);
                                      } else {
                                        _favoriteServices.add(serviceUuid);
                                      }
                                    });
                                  },
                                  isSystemService: _isSystemService,
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              // Main content area
              Expanded(
                flex: deviceType == DeviceType.desktop ? 3 : 1,
                child: Column(
                  children: [
                    // Selected service/char always visible at top (mobile/tablet)
                    if (deviceType != DeviceType.desktop &&
                        selectedService != null &&
                        selectedCharacteristic != null)
                      Container(
                        color: Theme.of(
                          context,
                        ).primaryColor.withValues(alpha: 0.1),
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.info_outline, size: 16),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: SelectableText(
                                    'Selected: ${selectedCharacteristic!.uuid}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SelectableText(
                              'Service: ${selectedService!.uuid}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            SelectableText(
                              'Properties: ${selectedCharacteristic!.properties.map((e) => e.name).join(", ")}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            // Device info with manufacturer data and advertised services
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Card(
                                child: SizedBox(
                                  width: double.infinity,
                                  child: Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const SelectableText(
                                          'Device Information',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        SelectableText(
                                          'Device ID: ${bleDevice.deviceId}',
                                        ),
                                        SelectableText(
                                          'Name: ${bleDevice.name ?? "Unknown"}',
                                        ),
                                        // Manufacturer data
                                        if (bleDevice
                                            .manufacturerDataList
                                            .isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          const SelectableText(
                                            'Manufacturer Data:',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          ...bleDevice.manufacturerDataList.map(
                                            (data) => Padding(
                                              padding: const EdgeInsets.only(
                                                top: 4.0,
                                              ),
                                              child: SelectableText(
                                                'Company ID: ${data.companyId} (0x${data.companyId.toRadixString(16).toUpperCase().padLeft(4, '0')})\nHex: ${_manufacturerDataToHex(data)}',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontFamily: 'monospace',
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                        // Advertised services
                                        if (bleDevice.services.isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          const SelectableText(
                                            'Advertised Services:',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          ...bleDevice.services.map(
                                            (service) => Padding(
                                              padding: const EdgeInsets.only(
                                                left: 8.0,
                                                top: 2.0,
                                              ),
                                              child: SelectableText(
                                                '• $service${_isSystemService(service) ? " (System)" : ""}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color:
                                                      _isSystemService(service)
                                                      ? Colors.blue
                                                      : null,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // Connect/Disconnect buttons
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: <Widget>[
                                  PlatformButton(
                                    text: 'Connect',
                                    enabled: !isConnected,
                                    onPressed: () async {
                                      await _executeWithLoading(
                                        () async {
                                          await bleDevice.connect();
                                          _addLog("ConnectionResult", true);
                                        },
                                        onError: (error) {
                                          _addLog(
                                            'ConnectError (${error.runtimeType})',
                                            error,
                                          );
                                        },
                                      );
                                    },
                                  ),
                                  PlatformButton(
                                    text: 'Disconnect',
                                    enabled: isConnected,
                                    onPressed: () {
                                      bleDevice.disconnect();
                                    },
                                  ),
                                ],
                              ),
                            ),
                            // Selected characteristic info
                            if (selectedCharacteristic == null)
                              Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: SelectableText(
                                  discoveredServices.isEmpty
                                      ? "Please discover services"
                                      : "Please select a characteristic to read/write",
                                  style: const TextStyle(
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              )
                            else
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8.0,
                                ),
                                child: Card(
                                  color: Colors.blue.withValues(alpha: 0.1),
                                  child: Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.check_circle,
                                              color: Colors.green,
                                              size: 20,
                                            ),
                                            const SizedBox(width: 8),
                                            const Expanded(
                                              child: Text(
                                                'Ready to communicate',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.green,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        SelectableText(
                                          "Characteristic: ${selectedCharacteristic!.uuid}",
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        SelectableText(
                                          "Service: ${selectedService?.uuid ?? "Unknown"}",
                                        ),
                                        SelectableText(
                                          "Properties: ${selectedCharacteristic!.properties.map((e) => e.name).join(", ")}",
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8.0,
                              ),
                              child: Form(
                                key: valueFormKey,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: binaryCode,
                                        enabled:
                                            isConnected &&
                                            _hasSelectedCharacteristicProperty([
                                              CharacteristicProperty.write,
                                              CharacteristicProperty
                                                  .writeWithoutResponse,
                                            ]),
                                        validator: (value) {
                                          if (value == null || value.isEmpty) {
                                            return 'Please enter a value';
                                          }
                                          try {
                                            hex.decode(binaryCode.text);
                                            return null;
                                          } catch (e) {
                                            return 'Please enter a valid hex value ( without spaces or 0x (e.g. F0BB) )';
                                          }
                                        },
                                        decoration: const InputDecoration(
                                          hintText:
                                              "Enter Hex values without spaces or 0x (e.g. F0BB)",
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    PlatformButton(
                                      text: 'Write',
                                      enabled:
                                          isConnected &&
                                          _hasSelectedCharacteristicProperty([
                                            CharacteristicProperty.write,
                                            CharacteristicProperty
                                                .writeWithoutResponse,
                                          ]),
                                      onPressed: _writeValue,
                                    ),
                                    const SizedBox(width: 8),
                                    PlatformButton(
                                      text: 'Read',
                                      enabled:
                                          isConnected &&
                                          _hasSelectedCharacteristicProperty([
                                            CharacteristicProperty.read,
                                          ]),
                                      onPressed: _readValue,
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const Divider(),
                            // Action buttons
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: ResponsiveButtonsGrid(
                                children: [
                                  PlatformButton(
                                    onPressed: () async {
                                      _discoverServices();
                                    },
                                    enabled: isConnected,
                                    text: 'Discover Services',
                                  ),
                                  PlatformButton(
                                    onPressed: () async {
                                      _addLog(
                                        'ConnectionState',
                                        await bleDevice.connectionState,
                                      );
                                    },
                                    text: 'Connection State',
                                  ),
                                  if (BleCapabilities.supportsRequestMtuApi)
                                    PlatformButton(
                                      enabled: isConnected,
                                      onPressed: () async {
                                        await _executeWithLoading(
                                          () async {
                                            int mtu = await bleDevice
                                                .requestMtu(247);
                                            _addLog('MTU', mtu);
                                          },
                                          onError: (error) {
                                            _addLog('RequestMtuError', error);
                                          },
                                        );
                                      },
                                      text: 'Request Mtu',
                                    ),
                                  PlatformButton(
                                    enabled:
                                        isConnected &&
                                        discoveredServices.isNotEmpty,
                                    onPressed: _subscribeChar,
                                    text: 'Subscribe',
                                  ),
                                  PlatformButton(
                                    enabled:
                                        isConnected &&
                                        discoveredServices.isNotEmpty,
                                    onPressed: _unsubscribeChar,
                                    text: 'Unsubscribe',
                                  ),
                                  PlatformButton(
                                    enabled:
                                        isConnected &&
                                        discoveredServices.isNotEmpty,
                                    onPressed: _subscribeToAllCharacteristics,
                                    text: 'Subscribe to All',
                                  ),
                                  PlatformButton(
                                    enabled:
                                        BleCapabilities.supportsAllPairingKinds,
                                    onPressed: () async {
                                      await _executeWithLoading(
                                        () async {
                                          await bleDevice.pair();
                                          _addLog("Pairing Result", true);
                                        },
                                        onError: (error) {
                                          _addLog('PairError', error);
                                        },
                                      );
                                    },
                                    text: 'Pair',
                                  ),
                                  PlatformButton(
                                    onPressed: () async {
                                      await _executeWithLoading(
                                        () async {
                                          bool? isPaired = await bleDevice
                                              .isPaired();
                                          _addLog('isPaired', isPaired);
                                        },
                                        onError: (error) {
                                          _addLog('isPairedError', error);
                                        },
                                      );
                                    },
                                    text: 'isPaired',
                                  ),
                                  PlatformButton(
                                    onPressed: () async {
                                      await bleDevice.unpair();
                                    },
                                    text: 'Unpair',
                                  ),
                                ],
                              ),
                            ),
                            // Services list (mobile/tablet)
                            if (deviceType != DeviceType.desktop)
                              ServicesListWidget(
                                discoveredServices: discoveredServices,
                                selectedService: selectedService,
                                selectedCharacteristic: selectedCharacteristic,
                                favoriteServices: _favoriteServices,
                                subscribedCharacteristics:
                                    _subscribedCharacteristics,
                                onTap: (service, characteristic) {
                                  setState(() {
                                    selectedService = service;
                                    selectedCharacteristic = characteristic;
                                  });
                                },
                                onFavoriteToggle: (serviceUuid) {
                                  setState(() {
                                    if (_favoriteServices.contains(
                                      serviceUuid,
                                    )) {
                                      _favoriteServices.remove(serviceUuid);
                                    } else {
                                      _favoriteServices.add(serviceUuid);
                                    }
                                  });
                                },
                                isSystemService: _isSystemService,
                              ),
                            const Divider(),
                            ResultWidget(
                              results: _logs,
                              onClearTap: (int? index) {
                                setState(() {
                                  if (index != null) {
                                    _logs.removeAt(index);
                                  } else {
                                    _logs.clear();
                                  }
                                });
                              },
                            ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  bool _hasSelectedCharacteristicProperty(
    List<CharacteristicProperty> properties,
  ) {
    return properties.any(
      (property) =>
          selectedCharacteristic?.properties.contains(property) ?? false,
    );
  }
}
