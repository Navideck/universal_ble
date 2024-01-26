// ignore_for_file: avoid_print, depend_on_referenced_packages

import 'package:convert/convert.dart';
import 'package:expandable/expandable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:universal_ble_example/data/capabilities.dart';
import 'package:universal_ble_example/peripheral_details/widgets/result_widget.dart';
import 'package:universal_ble_example/peripheral_details/widgets/services_list_widget.dart';
import 'package:universal_ble_example/widgets/platform_button.dart';
import 'package:universal_ble_example/widgets/responsive_buttons_grid.dart';
import 'package:universal_ble_example/widgets/responsive_view.dart';

class PeripheralDetailPage extends StatefulWidget {
  final String deviceId;
  const PeripheralDetailPage(this.deviceId, {Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return _PeripheralDetailPageState();
  }
}

class _PeripheralDetailPageState extends State<PeripheralDetailPage> {
  bool isConnected = false;
  GlobalKey<FormState> valueFormKey = GlobalKey<FormState>();
  List<BleService> discoveredServices = [];
  ExpandableController expandableController = ExpandableController();
  final List<String> _logs = [];
  final binaryCode = TextEditingController();

  ({
    BleService service,
    BleCharacteristic characteristic
  })? selectedCharacteristic;

  @override
  void initState() {
    super.initState();
    UniversalBle.onConnectionChanged = _handleConnectionChange;
    UniversalBle.onValueChanged = _handleValueChange;
    UniversalBle.onPairingStateChange = _handlePairingStateChange;
  }

  @override
  void dispose() {
    super.dispose();
    UniversalBle.onConnectionChanged = null;
    UniversalBle.onValueChanged = null;
    // Disconnect when leaving the page
    if (isConnected) UniversalBle.disconnect(widget.deviceId);
  }

  void _addLog(String type, dynamic data) {
    setState(() {
      _logs.add('$type : ${data.toString()}');
    });
  }

  void _handleConnectionChange(String deviceId, BleConnectionState state) {
    print('_handleConnectionChange $deviceId, ${state.name}');
    setState(() {
      if (deviceId == widget.deviceId) {
        isConnected = (state == BleConnectionState.connected);
      }
    });
    _addLog('Connection', state.name.toUpperCase());
    // Auto Discover Services
    if (isConnected) {
      _discoverServices();
    }
  }

  void _handleValueChange(
      String deviceId, String characteristicId, Uint8List value) {
    String s = String.fromCharCodes(value);
    String data = '$s\nraw :  ${value.toString()}';
    print('_handleValueChange $deviceId, $characteristicId, $s');
    _addLog("Value", data);
  }

  void _handlePairingStateChange(
      String deviceId, bool isPaired, String? error) {
    print('OnPairStateChange $deviceId, $isPaired');
    if (error != null) {
      _addLog("PairStateChangeError", "(Paired: $isPaired): $error ");
    } else {
      _addLog("PairStateChange", isPaired);
    }
  }

  Uint8List? _getWriteValue() {
    if (!valueFormKey.currentState!.validate()) return null;
    if (binaryCode.text.isEmpty) {
      print("Error: No value to write");
      return null;
    }

    List<int> hexList = [];

    try {
      hexList = hex.decode(binaryCode.text);
    } catch (e) {
      print("Error parsing hex $e");
    }

    return Uint8List.fromList(hexList);
  }

  Future<void> _discoverServices() async {
    var services = await UniversalBle.discoverServices(widget.deviceId);
    print('${services.length} services discovered');
    discoveredServices.clear();
    setState(() {
      discoveredServices = services;
    });

    if (kIsWeb) {
      _addLog("DiscoverServices",
          '${services.length} services discovered,\nNote: Only services added in WebRequestOptionsBuilder will be discoverd');
    }
  }

  Future<void> _readValue() async {
    if (selectedCharacteristic == null) return;
    try {
      Uint8List value = await UniversalBle.readValue(
        widget.deviceId,
        selectedCharacteristic!.service.uuid,
        selectedCharacteristic!.characteristic.uuid,
      );
      String s = String.fromCharCodes(value);
      String data = '$s\nraw :  ${value.toString()}';
      _addLog('Read', data);
    } catch (e) {
      _addLog('ReadError', e);
    }
  }

  Future<void> _writeValue() async {
    Uint8List? value = _getWriteValue();
    if (value == null || selectedCharacteristic == null) return;
    print("Writing $value");
    try {
      await UniversalBle.writeValue(
        widget.deviceId,
        selectedCharacteristic!.service.uuid,
        selectedCharacteristic!.characteristic.uuid,
        value,
        BleOutputProperty.withResponse,
      );
      _addLog('Write', value);
    } catch (e) {
      print(e);
      _addLog('WriteError', e);
    }
  }

  Future<void> _setBleInputProperty(BleInputProperty inputProperty) async {
    if (selectedCharacteristic == null) return;
    try {
      if (inputProperty != BleInputProperty.disabled) {
        List<CharacteristicProperty> properties =
            selectedCharacteristic!.characteristic.properties;
        if (properties.contains(CharacteristicProperty.notify)) {
          inputProperty = BleInputProperty.notification;
        } else if (properties.contains(CharacteristicProperty.indicate)) {
          inputProperty = BleInputProperty.indication;
        } else {
          throw 'No notify or indicate property';
        }
      }
      await UniversalBle.setNotifiable(
        widget.deviceId,
        selectedCharacteristic!.service.uuid,
        selectedCharacteristic!.characteristic.uuid,
        inputProperty,
      );
      _addLog('BleInputProperty', inputProperty);
    } catch (e) {
      _addLog('NotifyError', e);
    }
  }

  bool isValidProperty(List<CharacteristicProperty> properties) {
    for (CharacteristicProperty property in properties) {
      if (selectedCharacteristic?.characteristic.properties
              .contains(property) ??
          false) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Peripheral Details'),
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
                          onTap: (BleService service,
                              BleCharacteristic characteristic) {
                            setState(() {
                              selectedCharacteristic = (
                                service: service,
                                characteristic: characteristic
                              );
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
                                  await UniversalBle.connect(widget.deviceId);
                                } catch (e) {
                                  _addLog('ConnectError', e);
                                }
                              },
                            ),
                            PlatformButton(
                              text: 'Disconnect',
                              enabled: isConnected,
                              onPressed: () {
                                UniversalBle.disconnect(widget.deviceId);
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
                                  title: Text(
                                    "Char: ${selectedCharacteristic!.characteristic.uuid}",
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "Service: ${selectedCharacteristic!.service.uuid}",
                                      ),
                                      Text(
                                        "Properties: ${selectedCharacteristic!.characteristic.properties.map((e) => e.name)}",
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                      if (isValidProperty([
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
                                  return null;
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
                            if (Capabilities.supportsRequestMtuApi)
                              PlatformButton(
                                enabled: isConnected,
                                onPressed: () async {
                                  int mtu = await UniversalBle.requestMtu(
                                      widget.deviceId, 247);
                                  _addLog('MTU', mtu);
                                },
                                text: 'Request Mtu',
                              ),
                            PlatformButton(
                              enabled: isConnected &&
                                  discoveredServices.isNotEmpty &&
                                  isValidProperty([
                                    CharacteristicProperty.read,
                                  ]),
                              onPressed: _readValue,
                              text: 'Read',
                            ),
                            PlatformButton(
                              enabled: isConnected &&
                                  discoveredServices.isNotEmpty &&
                                  isValidProperty([
                                    CharacteristicProperty.write,
                                    CharacteristicProperty.writeWithoutResponse
                                  ]),
                              onPressed: _writeValue,
                              text: 'Write',
                            ),
                            PlatformButton(
                              enabled: isConnected &&
                                  discoveredServices.isNotEmpty &&
                                  isValidProperty([
                                    CharacteristicProperty.notify,
                                    CharacteristicProperty.indicate
                                  ]),
                              onPressed: () => _setBleInputProperty(
                                  BleInputProperty.notification),
                              text: 'Subscribe',
                            ),
                            PlatformButton(
                              enabled: isConnected &&
                                  discoveredServices.isNotEmpty &&
                                  isValidProperty([
                                    CharacteristicProperty.notify,
                                    CharacteristicProperty.indicate
                                  ]),
                              onPressed: () => _setBleInputProperty(
                                  BleInputProperty.disabled),
                              text: 'Unsubscribe',
                            ),
                            if (Capabilities.supportsPairingApi)
                              PlatformButton(
                                onPressed: () async {
                                  await UniversalBle.pair(widget.deviceId);
                                },
                                text: 'Pair',
                              ),
                            if (Capabilities.supportsPairingApi)
                              PlatformButton(
                                onPressed: () async {
                                  bool isPaired = await UniversalBle.isPaired(
                                      widget.deviceId);
                                  _addLog('IsPaired', isPaired);
                                },
                                text: 'IsPaired',
                              ),
                            if (Capabilities.supportsPairingApi)
                              PlatformButton(
                                onPressed: () async {
                                  await UniversalBle.unPair(widget.deviceId);
                                },
                                text: 'UnPair',
                              ),
                          ],
                        ),
                      ),
                      // Services
                      if (deviceType != DeviceType.desktop)
                        ServicesListWidget(
                          discoveredServices: discoveredServices,
                          onTap: (BleService service,
                              BleCharacteristic characteristic) {
                            setState(() {
                              selectedCharacteristic = (
                                service: service,
                                characteristic: characteristic
                              );
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
}
