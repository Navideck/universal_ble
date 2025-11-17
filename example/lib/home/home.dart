import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:universal_ble_example/data/mock_universal_ble.dart';
import 'package:universal_ble_example/home/widgets/scan_filter_widget.dart';
import 'package:universal_ble_example/home/widgets/scanned_devices_placeholder_widget.dart';
import 'package:universal_ble_example/home/widgets/scanned_item_widget.dart';
import 'package:universal_ble_example/peripheral_details/peripheral_detail_page.dart';
import 'package:universal_ble_example/widgets/platform_button.dart';
import 'package:universal_ble_example/widgets/responsive_buttons_grid.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _bleDevices = <BleDevice>[];
  final _hiddenDevices = <BleDevice>[];
  bool _isScanning = false;
  QueueType _queueType = QueueType.global;
  TextEditingController servicesFilterController = TextEditingController();
  TextEditingController namePrefixController = TextEditingController();
  TextEditingController manufacturerDataController = TextEditingController();
  final TextEditingController _searchFilterController = TextEditingController();
  StreamSubscription<AvailabilityState>? _availabilityStreamSubscription;

  bool get isTrackingAvailabilityState =>
      _availabilityStreamSubscription != null;
  AvailabilityState? bleAvailabilityState;
  ScanFilter? scanFilter;

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

    UniversalBle.scanStream.listen((result) {
      // log(result.toString());
      // If device is already in hidden devices, skip
      if (_hiddenDevices.any((e) => e.deviceId == result.deviceId)) {
        // debugPrint("Skipping hidden device: ${result.deviceId}");
        return;
      }
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
    });

    // UniversalBle.onQueueUpdate = (String id, int remainingItems) {
    //   debugPrint("Queue: $id RemainingItems: $remainingItems");
    // };

    UniversalBle.isScanning().then((value) {
      debugPrint("Is Scanning: $value");
      setState(() {
        _isScanning = value;
      });
    });
  }

  void trackAvailabilityState() {
    _availabilityStreamSubscription = UniversalBle.availabilityStream.listen(
      (state) {
        setState(() {
          bleAvailabilityState = state;
        });
      },
    );
    setState(() {});
  }

  Future<void> startScan() async {
    await UniversalBle.startScan(scanFilter: scanFilter);
  }

  Future<void> _getSystemDevices() async {
    // For macOS and iOS, it is recommended to set a filter to get system devices
    if ((defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.iOS) &&
        (scanFilter?.withServices ?? []).isEmpty) {
      showSnackbar(
          "No services filter was set for getting system connected devices. Using default services...");
    }

    List<BleDevice> devices = await UniversalBle.getSystemDevices(
      withServices: scanFilter?.withServices,
    );
    if (devices.isEmpty) {
      showSnackbar("No System Connected Devices Found");
    }
    setState(() {
      _bleDevices.clear();
      _bleDevices.addAll(devices);
    });
  }

  void _showScanFilterBottomSheet() {
    showModalBottomSheet(
      isScrollControlled: true,
      context: context,
      builder: (context) {
        return ScanFilterWidget(
          servicesFilterController: servicesFilterController,
          namePrefixController: namePrefixController,
          manufacturerDataController: manufacturerDataController,
          onScanFilter: (ScanFilter? filter) {
            setState(() {
              scanFilter = filter;
            });
          },
        );
      },
    );
  }

  void showSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void dispose() {
    _availabilityStreamSubscription?.cancel();
    servicesFilterController.dispose();
    namePrefixController.dispose();
    manufacturerDataController.dispose();
    _searchFilterController.dispose();
    super.dispose();
  }

  List<BleDevice> get _filteredDevices {
    if (_searchFilterController.text.isEmpty) {
      return _bleDevices;
    }
    final filter = _searchFilterController.text.toLowerCase();
    return _bleDevices.where((device) {
      final name = device.name?.toLowerCase() ?? '';
      final deviceId = device.deviceId.toLowerCase();
      final services = device.services.join(' ').toLowerCase();
      return name.contains(filter) ||
          deviceId.contains(filter) ||
          services.contains(filter);
    }).toList();
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
                      _bleDevices.clear();
                      _isScanning = true;
                    });
                    try {
                      await startScan();
                    } catch (e) {
                      setState(() {
                        _isScanning = false;
                      });
                      showSnackbar(e.toString());
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
                if (BleCapabilities.supportsBluetoothEnableApi)
                  bleAvailabilityState != AvailabilityState.poweredOn
                      ? PlatformButton(
                          text: 'Enable Bluetooth',
                          onPressed: () async {
                            bool isEnabled =
                                await UniversalBle.enableBluetooth();
                            showSnackbar("BluetoothEnabled: $isEnabled");
                          },
                        )
                      : PlatformButton(
                          text: 'Disable Bluetooth',
                          onPressed: () async {
                            bool isDisabled =
                                await UniversalBle.disableBluetooth();
                            showSnackbar("BluetoothDisabled: $isDisabled");
                          },
                        ),
                if (BleCapabilities.requiresRuntimePermission)
                  PlatformButton(
                    text: 'Request Permissions',
                    onPressed: () async {
                      try {
                        await UniversalBle.requestPermissions(
                          withAndroidFineLocation: false,
                        );
                        showSnackbar("Permissions granted");
                      } catch (e) {
                        showSnackbar(e.toString());
                      }
                    },
                  ),
                if (!isTrackingAvailabilityState)
                  PlatformButton(
                    text: 'Track Availability State',
                    onPressed: trackAvailabilityState,
                  ),
                if (BleCapabilities.supportsConnectedDevicesApi)
                  PlatformButton(
                    text: 'System Devices',
                    onPressed: _getSystemDevices,
                  ),
                PlatformButton(
                  text: 'Queue: ${_queueType.name}',
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
                PlatformButton(
                  text: 'Scan Filters',
                  onPressed: _showScanFilterBottomSheet,
                ),
                if (_hiddenDevices.isNotEmpty)
                  PlatformButton(
                    text: 'Unhide ${_hiddenDevices.length} Devices',
                    onPressed: () {
                      setState(() {
                        _hiddenDevices.clear();
                      });
                    },
                  )
                else if (_bleDevices.isNotEmpty)
                  Tooltip(
                    message:
                        'Hide already discovered devices. When you turn on a new device, it will be easier to spot.',
                    child: PlatformButton(
                      text: 'Hide Already Discovered Devices',
                      onPressed: () {
                        setState(() {
                          _hiddenDevices.clear();
                          _hiddenDevices.addAll(_bleDevices);
                          _bleDevices.clear();
                        });
                      },
                    ),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (isTrackingAvailabilityState)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: SelectableText(
                    'Ble Availability : ${bleAvailabilityState?.name}',
                  ),
                ),
            ],
          ),
          // Search filter
          if (_bleDevices.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(
                controller: _searchFilterController,
                decoration: InputDecoration(
                  labelText: 'Filter devices',
                  hintText: 'Search by name, ID, or services...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchFilterController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchFilterController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          const Divider(color: Colors.blue),
          Expanded(
            child: _isScanning && _bleDevices.isEmpty
                ? const Center(child: CircularProgressIndicator.adaptive())
                : !_isScanning && _bleDevices.isEmpty
                    ? const ScannedDevicesPlaceholderWidget()
                    : _filteredDevices.isEmpty
                        ? const Center(
                            child:
                                SelectableText('No devices match your filter'))
                        : ListView.separated(
                            itemCount: _filteredDevices.length,
                            separatorBuilder: (context, index) =>
                                const Divider(),
                            itemBuilder: (context, index) {
                              BleDevice device = _filteredDevices[
                                  _filteredDevices.length - index - 1];
                              return ScannedItemWidget(
                                bleDevice: device,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          PeripheralDetailPage(device),
                                    ),
                                  );
                                  // Stop scan but keep results visible
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
