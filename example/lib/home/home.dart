// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:universal_ble_example/data/capabilities.dart';
import 'package:universal_ble_example/home/widgets/scanned_devices_placeholder_widget.dart';
import 'package:universal_ble_example/home/widgets/scanned_item_widget.dart';
import 'package:universal_ble_example/data/permission_handler.dart';
import 'package:universal_ble_example/peripheral_details/peripheral_detail_page.dart';
import 'package:universal_ble_example/widgets/platform_button.dart';
import 'package:universal_ble_example/widgets/responsive_buttons_grid.dart';

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _scanResults = <BleScanResult>[];
  bool _isScanning = false;
  AvailabilityState? bleAvailabilityState;
  late WebRequestOptionsBuilder _requestOptions;
  final List<String> _services = [
    "00001800-0000-1000-8000-00805f9b34fb",
    "00002a00-0000-1000-8000-00805f9b34fb",
    "00002a01-0000-1000-8000-00805f9b34fb",
    "00002a19-0000-1000-8000-00805f9b34fb",
    "8000cc00-cc00-ffff-ffff-ffffffffffff",
    "8000dd00-dd00-ffff-ffff-ffffffffffff",
  ];

  @override
  void initState() {
    super.initState();

    _requestOptions =
        WebRequestOptionsBuilder.acceptAllDevices(optionalServices: _services);

    UniversalBle.onAvailabilityChange = (state) {
      setState(() {
        bleAvailabilityState = state;
      });
    };

    UniversalBle.onScanResult = (result) {
      int index = _scanResults.indexWhere((e) => e.deviceId == result.deviceId);
      if (index == -1) {
        _scanResults.add(result);
      } else {
        if (result.name == null && _scanResults[index].name != null) {
          result.name = _scanResults[index].name;
        }
        _scanResults[index] = result;
      }
      setState(() {});
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Universal Ble'),
        elevation: 4,
        actions: [
          if (_isScanning)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator.adaptive(
                    strokeWidth: 2,
                  )),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ResponsiveButtonsGrid(
              children: [
                PlatformButton(
                  text: 'Start Scan',
                  onPressed: () async {
                    setState(() {
                      _scanResults.clear();
                      _isScanning = true;
                    });
                    await UniversalBle.startScan(
                        webRequestOptions: _requestOptions);
                  },
                ),
                PlatformButton(
                  text: 'Stop Scan',
                  onPressed: () async {
                    await UniversalBle.stopScan();
                    setState(() {
                      _isScanning = false;
                    });
                  },
                ),
                if (Capabilities.supportsBluetoothEnableApi)
                  PlatformButton(
                    text: 'Enable Bluetooth',
                    onPressed: () async {
                      bool isEnabled = await UniversalBle.enableBluetooth();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("BluetoothEnabled: $isEnabled")),
                      );
                    },
                  ),
                if (Capabilities.requiresRuntimePermission)
                  PlatformButton(
                    text: 'Check Permissions',
                    onPressed: () async {
                      bool hasPermissions =
                          await PermissionHandler.arePermissionsGranted();
                      if (hasPermissions) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Permissions granted")),
                        );
                      }
                    },
                  ),
                if (Capabilities.supportsConnectedDevicesApi)
                  PlatformButton(
                    text: 'Connected Devices',
                    onPressed: () async {
                      var devices = await UniversalBle.getConnectedDevices(
                        withServices: _services,
                      );
                      if (devices.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("No Connected Devices Found"),
                          ),
                        );
                      }
                      setState(() {
                        _scanResults.clear();
                        _scanResults.addAll(devices);
                      });
                    },
                  ),
                if (_scanResults.isNotEmpty)
                  PlatformButton(
                    text: 'Clear List',
                    onPressed: () {
                      setState(() {
                        _scanResults.clear();
                      });
                    },
                  ),
              ],
            ),
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
            ],
          ),
          const Divider(color: Colors.blue),
          Expanded(
            child: _isScanning && _scanResults.isEmpty
                ? const Center(child: CircularProgressIndicator.adaptive())
                : !_isScanning && _scanResults.isEmpty
                    ? const ScannedDevicesPlaceholderWidget()
                    : ListView.separated(
                        itemCount: _scanResults.length,
                        separatorBuilder: (context, index) => const Divider(),
                        itemBuilder: (context, index) {
                          BleScanResult scanResult = _scanResults[index];
                          return ScannedItemWidget(
                            scanResult: scanResult,
                            onTap: () {
                              Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => PeripheralDetailPage(
                                        scanResult.deviceId),
                                  ));
                              UniversalBle.stopScan();
                              setState(() {
                                _isScanning = false;
                              });
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
