// ignore_for_file: use_build_context_synchronously, avoid_print

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:universal_ble_example/peripheral_detail_page.dart';
import 'package:universal_ble_example/permission_validator.dart';

// Run with auto connect to : auto Scan , FindDevice, Connect, DiscoverServices
const autoConnect = bool.fromEnvironment('AUTO_CONNECT', defaultValue: false);
const deviceIdToConnect = "50:e9:f1:c2:5e:2e";
const deviceNameFilterForAutoConnect = "MyDevice";
const primaryColor = Colors.blue;

void main() {
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  StreamSubscription<BleScanResult>? _subscription;
  final _scanResults = <BleScanResult>[];
  AvailabilityState? bleAvailabilityState;

  List<String> services = [
    "00001800-0000-1000-8000-00805f9b34fb",
    "00002a00-0000-1000-8000-00805f9b34fb",
    "00002a01-0000-1000-8000-00805f9b34fb",
    "00002a19-0000-1000-8000-00805f9b34fb",
    "8000cc00-cc00-ffff-ffff-ffffffffffff",
    "8000dd00-dd00-ffff-ffff-ffffffffffff",
  ];

  // Set the web request options with the required services
  get requestOptions =>
      WebRequestOptionsBuilder.acceptAllDevices(optionalServices: services);

  void initialize() {
    UniversalBle.getBluetoothAvailabilityState().then((value) {
      print("GetBluetoothAvailabilityState: ${value.name}");
      setState(() {
        bleAvailabilityState = value;
      });
    });

    UniversalBle.onAvailabilityChange = (state) {
      print("OnAvailabilityChange: ${state.name}");
      setState(() {
        bleAvailabilityState = state;
      });
    };

    if (autoConnect) {
      UniversalBle.startScan(webRequestOptions: requestOptions);
    }

    UniversalBle.onScanResult = (result) {
      if (!_scanResults.any((r) => r.deviceId == result.deviceId)) {
        setState(() => _scanResults.add(result));
      } else {
        setState(() {
          int index = _scanResults
              .indexWhere((element) => element.deviceId == result.deviceId);
          if (result.name == null && _scanResults[index].name != null) {
            result.name = _scanResults[index].name;
          }
          _scanResults[index] = result;
        });
      }
      if (autoConnect &&
          (result.deviceId == deviceIdToConnect ||
              (result.name?.contains(deviceNameFilterForAutoConnect) ==
                  true))) {
        print("Auto connecting to ${result.deviceId}");
        UniversalBle.stopScan();
        Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PeripheralDetailPage(result.deviceId, true),
            ));
      }
    };
  }

  @override
  void initState() {
    super.initState();

    initialize();
  }

  @override
  void dispose() {
    super.dispose();
    _subscription?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Universal Ble'),
      ),
      body: Column(
        children: [
          _buildButtons(),
          const Divider(
            color: Colors.blue,
          ),
          _scanResults.isEmpty
              ? const Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Icon(
                          Icons.bluetooth,
                          color: Colors.grey,
                          size: 100,
                        ),
                      ),
                      Text(
                        'Scan For Devices',
                        style: TextStyle(color: Colors.grey, fontSize: 22),
                      )
                    ],
                  ),
                )
              : _buildListView(),
        ],
      ),
    );
  }

  Widget _buildButtons() {
    return Column(
      children: [
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
                ElevatedButton(
                  child: const Text('Enable Bluetooth'),
                  onPressed: () async {
                    bool isEnabled = await UniversalBle.enableBluetooth();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("BluetoothEnabled: $isEnabled"),
                      ),
                    );
                  },
                ),
                ElevatedButton(
                  child: const Text('Permissions'),
                  onPressed: () async {
                    bool hasPermissions =
                        await Validator.arePermissionsGranted();
                    if (hasPermissions) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Permissions already granted"),
                        ),
                      );
                    }
                  },
                ),
                ElevatedButton(
                  child: const Text('Start Scan'),
                  onPressed: () {
                    setState(() {
                      _scanResults.clear();
                    });
                    UniversalBle.startScan(webRequestOptions: requestOptions);
                  },
                ),
                ElevatedButton(
                  child: const Text('Stop Scan'),
                  onPressed: () {
                    UniversalBle.stopScan();
                  },
                ),
                ElevatedButton(
                  child: const Text('Connected Devices'),
                  onPressed: () async {
                    var devices = await UniversalBle.getConnectedDevices(
                      withServices: services,
                    );
                    if (devices.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("No Connected Devices Found"),
                        ),
                      );
                    }
                    // print(devices.map((e) => e.toJson()));
                    setState(() {
                      _scanResults.clear();
                      _scanResults.addAll(devices);
                    });
                  },
                ),
              ],
            );
          }),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                'Ble Availability : ${bleAvailabilityState?.name}',
              ),
            ),
            IconButton(
                onPressed: () {
                  setState(() {
                    _scanResults.clear();
                  });
                },
                icon: const Icon(Icons.close_rounded)),
          ],
        ),
      ],
    );
  }

  Widget _buildListView() {
    return Expanded(
      child: ListView.separated(
        itemBuilder: (context, index) {
          var scanResult = _scanResults[index];
          String? name = scanResult.name;
          if (name == null || name.isEmpty) {
            name = 'NA';
          }
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Card(
              child: ListTile(
                title: Text(
                  '$name (${scanResult.rssi})',
                ),
                subtitle: scanResult.isPaired != null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("${scanResult.deviceId} "),
                          scanResult.isPaired == true
                              ? const Text(
                                  "Paired",
                                  style: TextStyle(color: Colors.green),
                                )
                              : const Text(
                                  "Not Paired",
                                  style: TextStyle(color: Colors.red),
                                ),
                        ],
                      )
                    : Text(scanResult.deviceId),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  print("$name: ${scanResult.deviceId}");
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            PeripheralDetailPage(scanResult.deviceId, false),
                      ));
                },
              ),
            ),
          );
        },
        separatorBuilder: (context, index) => const Divider(),
        itemCount: _scanResults.length,
      ),
    );
  }
}
