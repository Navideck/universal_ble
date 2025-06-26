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

  StreamSubscription? connectionStreamSubscription;
  StreamSubscription? pairingStateSubscription;
  BleService? selectedService;
  BleCharacteristic? selectedCharacteristic;

  @override
  void initState() {
    super.initState();

    connectionStreamSubscription =
        bleDevice.connectionStream.listen(_handleConnectionChange);
    pairingStateSubscription =
        bleDevice.pairingStateStream.listen(_handlePairingStateChange);
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
      String deviceId, String characteristicId, Uint8List value) {
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
    try {
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
    } catch (e) {
      _addLog("DiscoverServicesError", '$e\n${kIsWeb ? webWarning : ""}');
    }
  }

  Future<void> _readValue() async {
    BleCharacteristic? selectedCharacteristic = this.selectedCharacteristic;
    if (selectedCharacteristic == null) return;
    try {
      Uint8List value = await selectedCharacteristic.read();
      String s = String.fromCharCodes(value);
      String data = '$s\nraw :  ${value.toString()}';
      _addLog('Read', data);
    } catch (e) {
      _addLog('ReadError', e);
    }
  }

  Future<void> _writeValue({required bool withResponse}) async {
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

    try {
      await selectedCharacteristic.write(value, withResponse: withResponse);
      _addLog('Write${withResponse ? "" : "WithoutResponse"}', value);
    } catch (e) {
      debugPrint(e.toString());
      _addLog('WriteError', e);
    }
  }

  Future<void> _subscribeChar() async {
    BleCharacteristic? selectedCharacteristic = this.selectedCharacteristic;
    if (selectedCharacteristic == null) return;
    try {
      var subscription = _getCharacteristicSubscription(selectedCharacteristic);
      if (subscription == null) throw 'No notify or indicate property';
      await subscription.subscribe();
      _addLog('BleCharSubscription', 'Subscribed');
      // Updates can also be handled by
      // subscription.listen((data) {});
    } catch (e) {
      _addLog('NotifyError', e);
    }
  }

  Future<void> _unsubscribeChar() async {
    try {
      await selectedCharacteristic?.unsubscribe();
      _addLog('BleCharSubscription', 'UnSubscribed');
    } catch (e) {
      _addLog('NotifyError', e);
    }
  }

  CharacteristicSubscription? _getCharacteristicSubscription(
      BleCharacteristic characteristic) {
    var properties = characteristic.properties;
    if (properties.contains(CharacteristicProperty.notify)) {
      return characteristic.notifications;
    } else if (properties.contains(CharacteristicProperty.indicate)) {
      return characteristic.indications;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("${bleDevice.name ?? "Unknown"} - ${bleDevice.deviceId}"),
        elevation: 4,
        actions: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Icon(
              isConnected
                  ? Icons.bluetooth_connected
                  : Icons.bluetooth_disabled,
              color: isConnected ? Colors.greenAccent : Colors.red,
              size: 20,
            ),
          )
        ],
      ),
      body: ResponsiveView(builder: (_, DeviceType deviceType) {
        return Row(
          children: [
            if (deviceType == DeviceType.desktop)
              Expanded(
                flex: 1,
                child: Container(
                  color: Theme.of(context).secondaryHeaderColor,
                  child: discoveredServices.isEmpty
                      ? const Center(
                          child: Text('No Services Discovered'),
                        )
                      : ServicesListWidget(
                          discoveredServices: discoveredServices,
                          scrollable: true,
                          onTap: (service, characteristic) {
                            setState(() {
                              selectedService = service;
                              selectedCharacteristic = characteristic;
                            });
                          },
                        ),
                ),
              ),
            Expanded(
              flex: 3,
              child: Align(
                alignment: Alignment.topCenter,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // Top buttons
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: <Widget>[
                            PlatformButton(
                              text: 'Connect',
                              enabled: !isConnected,
                              onPressed: () async {
                                try {
                                  await bleDevice.connect();
                                  _addLog("ConnectionResult", true);
                                } catch (e) {
                                  _addLog('ConnectError (${e.runtimeType})', e);
                                }
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
                      selectedCharacteristic == null
                          ? Text(discoveredServices.isEmpty
                              ? "Please discover services"
                              : "Please select a characteristic")
                          : Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8.0,
                              ),
                              child: Card(
                                child: ListTile(
                                  title: SelectableText(
                                    "Characteristic: ${selectedCharacteristic?.uuid}",
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SelectableText(
                                        "Service: ${selectedService?.uuid}",
                                      ),
                                      Text(
                                        "Properties: ${selectedCharacteristic?.properties.map((e) => e.name)}",
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                      if (_hasSelectedCharacteristicProperty([
                        CharacteristicProperty.write,
                        CharacteristicProperty.writeWithoutResponse
                      ]))
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: Form(
                            key: valueFormKey,
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: TextFormField(
                                controller: binaryCode,
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
                          ),
                        ),
                      const Divider(),
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
                                  int mtu = await bleDevice.requestMtu(247);
                                  _addLog('MTU', mtu);
                                },
                                text: 'Request Mtu',
                              ),
                            PlatformButton(
                              enabled: isConnected &&
                                  discoveredServices.isNotEmpty &&
                                  _hasSelectedCharacteristicProperty([
                                    CharacteristicProperty.read,
                                  ]),
                              onPressed: _readValue,
                              text: 'Read',
                            ),
                            PlatformButton(
                              enabled: isConnected &&
                                  discoveredServices.isNotEmpty &&
                                  _hasSelectedCharacteristicProperty([
                                    CharacteristicProperty.write,
                                  ]),
                              onPressed: () => _writeValue(withResponse: true),
                              text: 'Write',
                            ),
                            PlatformButton(
                              enabled: isConnected &&
                                  discoveredServices.isNotEmpty &&
                                  _hasSelectedCharacteristicProperty([
                                    CharacteristicProperty.writeWithoutResponse,
                                  ]),
                              onPressed: () => _writeValue(withResponse: false),
                              text: 'WriteWithoutResponse',
                            ),
                            PlatformButton(
                              enabled: isConnected &&
                                  discoveredServices.isNotEmpty &&
                                  _hasSelectedCharacteristicProperty([
                                    CharacteristicProperty.notify,
                                    CharacteristicProperty.indicate
                                  ]),
                              onPressed: _subscribeChar,
                              text: 'Subscribe',
                            ),
                            PlatformButton(
                              enabled: isConnected &&
                                  discoveredServices.isNotEmpty &&
                                  _hasSelectedCharacteristicProperty([
                                    CharacteristicProperty.notify,
                                    CharacteristicProperty.indicate
                                  ]),
                              onPressed: _unsubscribeChar,
                              text: 'Unsubscribe',
                            ),
                            PlatformButton(
                              enabled: BleCapabilities.supportsAllPairingKinds,
                              onPressed: () async {
                                try {
                                  await bleDevice.pair(
                                      // pairingCommand: BleCommand(
                                      //   service: "",
                                      //   characteristic: "",
                                      // ),
                                      );
                                  _addLog("Pairing Result", true);
                                } catch (e) {
                                  _addLog('PairError (${e.runtimeType})', e);
                                }
                              },
                              text: 'Pair',
                            ),
                            PlatformButton(
                              onPressed: () async {
                                bool? isPaired = await bleDevice.isPaired(
                                    // pairingCommand: BleCommand(
                                    //   service: "",
                                    //   characteristic: "",
                                    // ),
                                    );
                                _addLog('isPaired', isPaired);
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
                      // Services
                      if (deviceType != DeviceType.desktop)
                        ServicesListWidget(
                          discoveredServices: discoveredServices,
                          onTap: (service, characteristic) {
                            setState(() {
                              selectedService = service;
                              selectedCharacteristic = characteristic;
                            });
                          },
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
                          }),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  bool _hasSelectedCharacteristicProperty(
      List<CharacteristicProperty> properties) {
    return properties.any((property) =>
        selectedCharacteristic?.properties.contains(property) ?? false);
  }
}
