// ignore_for_file: use_build_context_synchronously

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:universal_ble_example/data/capabilities.dart';
import 'package:universal_ble_example/data/mock_universal_ble.dart';
import 'package:universal_ble_example/home/widgets/scan_filter_tile.dart';
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
  final _bleDevices = <BleDevice>[];
  bool _isScanning = false;
  QueueType _queueType = QueueType.global;

  AvailabilityState? bleAvailabilityState;
  ScanFilter? scanFilter;
  bool showFiltersTile = kIsWeb;

  @override
  void initState() {
    super.initState();

    /// Set mock instance for testing
    if (const bool.fromEnvironment('MOCK')) {
      UniversalBle.setInstance(MockUniversalBle());
    }

    /// Setup queue and timeout
    UniversalBle.queueType = _queueType;
    UniversalBle.timeout = const Duration(seconds: 10);

    UniversalBle.onAvailabilityChange = (state) {
      setState(() {
        bleAvailabilityState = state;
      });
    };

    UniversalBle.onScanResult = (result) {
      // debugPrint("BleDevice: ${result.name}  ${result.services}");
      // debugPrint("${result.name} ${result.manufacturerData}");
      int index = _bleDevices.indexWhere((e) => e.deviceId == result.deviceId);
      if (index == -1) {
        _bleDevices.add(result);
      } else {
        if (result.name == null && _bleDevices[index].name != null) {
          result.name = _bleDevices[index].name;
        }
        _bleDevices[index] = result;
      }
      setState(() {});
    };

    // UniversalBle.onQueueUpdate = (String id, int remainingItems) {
    //   debugPrint("Queue: $id RemainingItems: $remainingItems");
    // };
  }

  Future<void> startScan() async {
    await UniversalBle.startScan(
      scanFilter: !showFiltersTile ? null : scanFilter,
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
          IconButton(
            onPressed: () {
              setState(() {
                showFiltersTile = !showFiltersTile;
              });
            },
            icon: Icon(
              showFiltersTile ? Icons.filter_alt_off : Icons.filter_alt,
            ),
          )
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
                      _bleDevices.clear();
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
                      List<BleDevice> devices =
                          await UniversalBle.getSystemDevices();
                      if (devices.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("No Connected Devices Found"),
                          ),
                        );
                      }
                      setState(() {
                        _bleDevices.clear();
                        _bleDevices.addAll(devices);
                      });
                    },
                  ),
                PlatformButton(
                  text: 'Queue: ${_queueType.name.toUpperCase()}',
                  onPressed: () {
                    setState(() {
                      _queueType = switch (_queueType) {
                        QueueType.global => QueueType.perDevice,
                        QueueType.perDevice => QueueType.none,
                        QueueType.none => QueueType.global,
                      };
                      UniversalBle.queueType = _queueType;
                    });
                  },
                ),
                if (_bleDevices.isNotEmpty)
                  PlatformButton(
                    text: 'Clear List',
                    onPressed: () {
                      setState(() {
                        _bleDevices.clear();
                      });
                    },
                  ),
              ],
            ),
          ),
          if (showFiltersTile)
            ScanFilterTile(
              onScanFilter: (ScanFilter? filter) {
                scanFilter = filter;
              },
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
            child: _isScanning && _bleDevices.isEmpty
                ? const Center(child: CircularProgressIndicator.adaptive())
                : !_isScanning && _bleDevices.isEmpty
                    ? const ScannedDevicesPlaceholderWidget()
                    : ListView.separated(
                        itemCount: _bleDevices.length,
                        separatorBuilder: (context, index) => const Divider(),
                        itemBuilder: (context, index) {
                          BleDevice device =
                              _bleDevices[_bleDevices.length - index - 1];
                          return ScannedItemWidget(
                            bleDevice: device,
                            onTap: () {
                              Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => PeripheralDetailPage(
                                      device.deviceId,
                                      device.name ?? "Unknown Peripheral",
                                    ),
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
