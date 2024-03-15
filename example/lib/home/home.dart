// ignore_for_file: use_build_context_synchronously

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:universal_ble_example/data/capabilities.dart';
import 'package:universal_ble_example/data/mock_universal_ble.dart';
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
  bool _isQueueEnabled = true;

  AvailabilityState? bleAvailabilityState;
  final List<String> _services = [
    "00001800-0000-1000-8000-00805f9b34fb",
    "0000180f-0000-1000-8000-00805f9b34fb",
    "00002a00-0000-1000-8000-00805f9b34fb",
    "00002a01-0000-1000-8000-00805f9b34fb",
    "00002a19-0000-1000-8000-00805f9b34fb",
    "8000cc00-cc00-ffff-ffff-ffffffffffff",
    "8000dd00-dd00-ffff-ffff-ffffffffffff",
  ];

  @override
  void initState() {
    super.initState();

    /// Set mock instance for testing
    if (const bool.fromEnvironment('MOCK')) {
      UniversalBle.setInstance(MockUniversalBle());
    }

    /// Setup queue and timeout
    UniversalBle.queuesCommands = _isQueueEnabled;
    UniversalBle.timeout = const Duration(seconds: 10);

    UniversalBle.onAvailabilityChange = (state) {
      setState(() {
        bleAvailabilityState = state;
      });
    };

    UniversalBle.onScanResult = (result) {
      // debugPrint("ScanResult: ${result.name}  ${result.services}");
      // debugPrint("${result.name} ${result.manufacturerData}");
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

  Future<void> startScan() async {
    await UniversalBle.startScan(
      scanFilter: ScanFilter(
        // withServices: ['180f'],
        //  withServices: kIsWeb ? _services : [],
        withManufacturerData: [
          ManufacturerDataFilter(
            companyIdentifier: 0x012D,
            data: Uint8List.fromList(
              [0x03, 0x00, 0x64, 0x00],
            ),
            // mask: Uint8List.fromList([0xff]),
          ),
          ManufacturerDataFilter(
            companyIdentifier: 0x012D,
            data: Uint8List.fromList(
              [0x03, 0x00, 0x65, 0x00],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Universal BLE'),
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
                    try {
                      await startScan();
                    } catch (e) {
                      setState(() {
                        _isScanning = false;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(e.toString())),
                      );
                    }
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
                if (Capabilities.supportsBluetoothEnableApi &&
                    bleAvailabilityState == AvailabilityState.poweredOff)
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
                PlatformButton(
                  text: _isQueueEnabled ? 'Disable Queue' : 'Enable Queue',
                  onPressed: () {
                    setState(() {
                      _isQueueEnabled = !_isQueueEnabled;
                      UniversalBle.queuesCommands = _isQueueEnabled;
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
