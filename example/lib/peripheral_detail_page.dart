// ignore_for_file: avoid_print, depend_on_referenced_packages

import 'dart:convert';

import 'package:convert/convert.dart';
import 'package:expandable/expandable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:universal_ble_example/main.dart';

String gssUuid(String code) => '0000$code-0000-1000-8000-00805f9b34fb';

class PeripheralDetailPage extends StatefulWidget {
  final String deviceId;
  final bool autoConnect;
  const PeripheralDetailPage(this.deviceId, this.autoConnect, {Key? key})
      : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return _PeripheralDetailPageState();
  }
}

class _PeripheralDetailPageState extends State<PeripheralDetailPage> {
  bool isConnected = false;
  bool parseValue = true;
  GlobalKey<FormState> uuidFormKey = GlobalKey<FormState>();
  GlobalKey<FormState> valueFormKey = GlobalKey<FormState>();

  List<BleService> discoveredServices = [];
  ExpandableController expandableController =
      ExpandableController(initialExpanded: autoConnect);
  List<String> results = [];

  @override
  void initState() {
    super.initState();
    UniversalBle.onConnectionChanged = _handleConnectionChange;
    UniversalBle.onValueChanged = _handleValueChange;
    UniversalBle.onPairingStateChange =
        (String deviceId, bool isPaired, String? error) {
      print('OnPairingStateChange $deviceId, $isPaired');
      setState(() {
        if (error != null) {
          results.add("PairStateChangeError (Paired: $isPaired): $error ");
        } else {
          results.add('PairStateChange: $isPaired');
        }
      });
    };

    if (autoConnect) {
      UniversalBle.connect(widget.deviceId);
    }
  }

  @override
  void dispose() {
    super.dispose();
    UniversalBle.onConnectionChanged = null;
    UniversalBle.onValueChanged = null;

    // Disconnect when leaving the page
    if (isConnected) UniversalBle.disconnect(widget.deviceId);
  }

  void _handleConnectionChange(String deviceId, BleConnectionState state) {
    print('_handleConnectionChange $deviceId, ${state.name}');
    setState(() {
      if (deviceId == widget.deviceId) {
        isConnected = (state == BleConnectionState.connected);
      }
      results.add('Connection: ${state.name.toUpperCase()}');
    });

    // Auto Discover Services
    if (isConnected) {
      discoverServices();
    } else if (autoConnect && !isConnected) {
      print("Trying to reconnect");
      UniversalBle.connect(widget.deviceId);
    }
  }

  void discoverServices() async {
    var services = await UniversalBle.discoverServices(widget.deviceId);
    print('${services.length} services discovered');
    discoveredServices.clear();
    setState(() {
      discoveredServices = services;
    });
  }

  void _handleValueChange(
      String deviceId, String characteristicId, Uint8List value) {
    String s = String.fromCharCodes(value);
    String data =
        parseValue ? '$s\nraw :  ${value.toString()}' : value.toString();
    print('_handleValueChange $deviceId, $characteristicId, $s');
    setState(() {
      results.add("Value: $data");
    });
  }

  Uint8List? _getWriteValue() {
    if (!uuidFormKey.currentState!.validate() ||
        !valueFormKey.currentState!.validate()) {
      return null;
    }

    if (binaryCode.text.isEmpty) {
      print("Error: No value to write");
      return null;
    }
    List<int>? value;
    String text = binaryCode.text;
    if (text.contains(",") || text.contains("[") || text.contains("]")) {
      text = text.replaceAll("[", "").replaceAll("]", "").trim();
      value = text.split(',').map(int.parse).toList();
    } else {
      try {
        value = hex.decode(text);
      } catch (e) {
        print("Error parsing hex $e");
        print("Trying utf8 encoding");
        value = utf8.encode(text);
      }
    }
    return Uint8List.fromList(value);
  }

  final serviceUUID = TextEditingController();
  final characteristicUUID = TextEditingController();
  final binaryCode = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Peripheral Details'),
        actions: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Icon(
              Icons.circle,
              color: isConnected ? Colors.greenAccent : Colors.red,
              size: 20,
            ),
          )
        ],
      ),
      body: LayoutBuilder(builder: (context, constraints) {
        bool isDesktop = constraints.maxWidth > 1000;
        return Row(
          children: [
            if (isDesktop)
              Expanded(
                flex: 1,
                child: Container(
                  color: Colors.grey[300],
                  child: discoveredServices.isEmpty
                      ? const Center(
                          child: Text('No Services Discovered'),
                        )
                      : ServicesView(
                          discoveredServices: discoveredServices,
                          scrollable: true,
                          onTap: (BleService service,
                              BleCharacteristic characteristic) {
                            serviceUUID.text = service.uuid;
                            characteristicUUID.text = characteristic.uuid;
                            print(
                              characteristic.properties.map((e) => e.name),
                            );
                          },
                        ),
                ),
              ),
            Expanded(
              flex: 3,
              child: Align(
                alignment: Alignment.topCenter,
                child: SingleChildScrollView(
                  child: Form(
                    key: uuidFormKey,
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
                                    print(e);
                                    setState(() {
                                      results.add('ConnectError : $e');
                                    });
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
                        const Divider(),

                        // Text Fields
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: TextFormField(
                            controller: serviceUUID,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter a service uuid';
                              }
                              return null;
                            },
                            decoration: const InputDecoration(
                              labelText: 'ServiceUUID',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: TextFormField(
                            controller: characteristicUUID,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter a Characteristic uuid';
                              }
                              return null;
                            },
                            decoration: const InputDecoration(
                              labelText: 'CharacteristicUUID',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),

                        Form(
                          key: valueFormKey,
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: TextFormField(
                                    controller: binaryCode,
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Please enter a value';
                                      }
                                      return null;
                                    },
                                    decoration: const InputDecoration(
                                      labelText: 'Enter Value ',
                                      hintText:
                                          "Enter Value (String, Hex or List<int>)",
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                Switch(
                                    value: parseValue,
                                    onChanged: (value) {
                                      setState(() {
                                        parseValue = value;
                                      });
                                    }),
                              ],
                            ),
                          ),
                        ),

                        const Divider(),

                        // Buttons
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: LayoutBuilder(builder: (context, constraints) {
                            const tileWidth = 150;
                            const tileHeight = 500;
                            final count = constraints.maxWidth ~/ tileWidth;
                            return GridView.count(
                              crossAxisCount: count,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                              childAspectRatio: tileHeight / tileWidth,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              children: [
                                PlatformButton(
                                  enabled: isConnected,
                                  onPressed: () {
                                    Uint8List? value = _getWriteValue();
                                    if (value == null) return;
                                    print("Writing $value");
                                    UniversalBle.writeValue(
                                        widget.deviceId,
                                        serviceUUID.text,
                                        characteristicUUID.text,
                                        value,
                                        BleOutputProperty.withResponse);
                                  },
                                  text: 'Write',
                                ),
                                PlatformButton(
                                  enabled: isConnected,
                                  onPressed: () async {
                                    if (!uuidFormKey.currentState!.validate()) {
                                      return;
                                    }
                                    try {
                                      Uint8List value =
                                          await UniversalBle.readValue(
                                              widget.deviceId,
                                              serviceUUID.text,
                                              characteristicUUID.text);
                                      String s = String.fromCharCodes(value);
                                      String data = parseValue
                                          ? '$s\nraw :  ${value.toString()}'
                                          : value.toString();
                                      setState(() {
                                        results.add('Read : $data');
                                      });
                                    } catch (e) {
                                      print(e);
                                      setState(() {
                                        results.add('ReadError : $e');
                                      });
                                    }
                                  },
                                  text: 'Read',
                                ),
                                PlatformButton(
                                  enabled: isConnected,
                                  onPressed: () async {
                                    int mtu = await UniversalBle.requestMtu(
                                        widget.deviceId, 247);
                                    setState(() {
                                      results.add('MTU : $mtu');
                                    });
                                  },
                                  text: 'Request Mtu',
                                ),
                                PlatformButton(
                                  enabled: isConnected,
                                  onPressed: () {
                                    if (!uuidFormKey.currentState!.validate()) {
                                      return;
                                    }
                                    BleCharacteristic? characteristic;

                                    for (BleService service
                                        in discoveredServices) {
                                      for (BleCharacteristic c
                                          in service.characteristics) {
                                        if (c.uuid == characteristicUUID.text) {
                                          characteristic = c;
                                          break;
                                        }
                                      }
                                    }
                                    BleInputProperty inputProperty =
                                        BleInputProperty.notification;
                                    if (characteristic != null) {
                                      if (characteristic.properties.contains(
                                          CharacteristicProperty.indicate)) {
                                        inputProperty =
                                            BleInputProperty.indication;
                                      } else if (characteristic.properties
                                          .contains(
                                              CharacteristicProperty.notify)) {
                                        inputProperty =
                                            BleInputProperty.notification;
                                      } else {
                                        print('No notify or indicate property');
                                        return;
                                      }
                                    }
                                    print(inputProperty);
                                    UniversalBle.setNotifiable(
                                      widget.deviceId,
                                      serviceUUID.text,
                                      characteristicUUID.text,
                                      inputProperty,
                                    );
                                  },
                                  text: 'Notify/Indicate',
                                ),
                                PlatformButton(
                                  enabled: isConnected,
                                  onPressed: () {
                                    if (!uuidFormKey.currentState!.validate()) {
                                      return;
                                    }
                                    UniversalBle.setNotifiable(
                                      widget.deviceId,
                                      serviceUUID.text,
                                      characteristicUUID.text,
                                      BleInputProperty.disabled,
                                    );
                                  },
                                  text: 'Cancel Notify',
                                ),
                                PlatformButton(
                                  onPressed: () async {
                                    discoverServices();
                                  },
                                  enabled: isConnected,
                                  text: 'Discover Services',
                                ),
                                PlatformButton(
                                  onPressed: () async {
                                    await UniversalBle.pair(widget.deviceId);
                                  },
                                  text: 'Pair',
                                ),
                                PlatformButton(
                                  onPressed: () async {
                                    bool isPaired = await UniversalBle.isPaired(
                                        widget.deviceId);
                                    setState(() {
                                      results.add('IsPaired : $isPaired');
                                    });
                                  },
                                  text: 'IsPaired',
                                ),
                                PlatformButton(
                                  onPressed: () async {
                                    await UniversalBle.unPair(widget.deviceId);
                                  },
                                  text: 'UnPair',
                                ),
                                PlatformButton(
                                  onPressed: () async {
                                    setState(() {
                                      results.clear();
                                      discoveredServices.clear();
                                    });
                                  },
                                  text: 'Clear',
                                ),
                              ],
                            );
                          }),
                        ),

                        // Results , Services
                        if (!isDesktop)
                          Column(
                            children: [
                              ResultView(
                                  results: results,
                                  onClearTap: (int? index) {
                                    setState(() {
                                      if (index != null) {
                                        results.removeAt(index);
                                      } else {
                                        results.clear();
                                      }
                                    });
                                  }),
                              const Divider(),
                              ServicesView(
                                discoveredServices: discoveredServices,
                                onTap: (BleService service,
                                    BleCharacteristic characteristic) {
                                  serviceUUID.text = service.uuid;
                                  characteristicUUID.text = characteristic.uuid;
                                  print(
                                    characteristic.properties
                                        .map((e) => e.name),
                                  );
                                },
                              ),
                            ],
                          )
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // For Desktop
            if (isDesktop)
              Expanded(
                  flex: 1,
                  child: Container(
                    color: Colors.grey[300],
                    child: results.isEmpty
                        ? const Center(
                            child: Text('No results'),
                          )
                        : ResultView(
                            results: results,
                            scrollable: true,
                            onClearTap: (int? index) {
                              setState(() {
                                if (index != null) {
                                  results.removeAt(index);
                                } else {
                                  results.clear();
                                }
                              });
                            }),
                  )),
          ],
        );
      }),
    );
  }
}

class ResultView extends StatelessWidget {
  final List<String> results;
  final bool scrollable;
  final Function(int? index) onClearTap;
  const ResultView({
    required this.results,
    required this.onClearTap,
    this.scrollable = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: !scrollable,
      physics: scrollable ? null : const NeverScrollableScrollPhysics(),
      itemCount: results.length,
      itemBuilder: (BuildContext context, int index) {
        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: Card(
            child: ListTile(
              onTap: () {
                onClearTap(index);
              },
              title: Text(results[index]),
              trailing: const Icon(Icons.clear),
            ),
          ),
        );
      },
    );
  }
}

class ServicesView extends StatelessWidget {
  final List<BleService> discoveredServices;
  final bool scrollable;

  final Function(BleService service, BleCharacteristic characteristic)? onTap;
  const ServicesView({
    super.key,
    required this.discoveredServices,
    this.onTap,
    this.scrollable = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: !scrollable,
      physics: scrollable ? null : const NeverScrollableScrollPhysics(),
      itemCount: discoveredServices.length,
      itemBuilder: (BuildContext context, int index) {
        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: Card(
            child: ExpandablePanel(
              header: Container(
                color: scrollable ? Colors.lime : Colors.grey[300],
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      const Icon(Icons.arrow_forward_ios),
                      Expanded(child: Text(discoveredServices[index].uuid)),
                    ],
                  ),
                ),
              ),
              collapsed: const SizedBox(),
              expanded: Column(
                children: discoveredServices[index]
                    .characteristics
                    .map((e) => Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              InkWell(
                                onTap: () {
                                  onTap?.call(discoveredServices[index], e);
                                },
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.arrow_right_outlined),
                                        Expanded(child: Text(e.uuid)),
                                      ],
                                    ),
                                    Text(
                                      "Properties: ${e.properties.map((e) => e.name)}",
                                    )
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ),
          ),
        );
      },
    );
  }
}

class PlatformButton extends StatelessWidget {
  final String text;
  final Function()? onPressed;
  final bool enabled;
  const PlatformButton({
    required this.text,
    required this.onPressed,
    this.enabled = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: enabled ? onPressed : null,
      child: Text(text),
    );
  }
}
