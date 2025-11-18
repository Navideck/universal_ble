import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:universal_ble_example/data/mock_universal_ble.dart';
import 'package:universal_ble_example/home/widgets/scan_filter_widget.dart';
import 'package:universal_ble_example/home/widgets/scanned_devices_placeholder_widget.dart';
import 'package:universal_ble_example/home/widgets/scanned_item_widget.dart';
import 'package:universal_ble_example/peripheral_details/peripheral_detail_page.dart';
import 'package:universal_ble_example/widgets/responsive_buttons_grid.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final _bleDevices = <BleDevice>[];
  final _hiddenDevices = <BleDevice>[];
  bool _isScanning = false;
  QueueType _queueType = QueueType.global;
  TextEditingController servicesFilterController = TextEditingController();
  TextEditingController namePrefixController = TextEditingController();
  TextEditingController manufacturerDataController = TextEditingController();
  final TextEditingController _searchFilterController = TextEditingController();
  AvailabilityState? bleAvailabilityState;
  ScanFilter? scanFilter;
  final Map<String, bool> _isExpanded = {};

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

    UniversalBle.scanStream.listen(_handleScanResult);

    UniversalBle.availabilityStream.listen((state) {
      setState(() => bleAvailabilityState = state);
    });

    UniversalBle.isScanning().then(
      (isScanning) => setState(() => _isScanning = isScanning),
    );

    // UniversalBle.onQueueUpdate = (String id, int remainingItems) {
    //   debugPrint("Queue: $id RemainingItems: $remainingItems");
    // };
  }

  void _handleScanResult(BleDevice result) {
    // log(result.toString());
    if (_hiddenDevices.any((e) => e.deviceId == result.deviceId)) {
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
  }

  Future<void> _startScan() async {
    await UniversalBle.startScan(scanFilter: scanFilter);
  }

  Future<void> _getSystemDevices() async {
    // For macOS and iOS, it is recommended to set a filter to get system devices
    if ((defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.iOS) &&
        (scanFilter?.withServices ?? []).isEmpty) {
      showSnackbar(
        "No services filter was set for getting system connected devices. Using default services...",
      );
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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

  bool get _isBluetoothAvailable =>
      bleAvailabilityState == AvailabilityState.poweredOn;

  @override
  void setState(VoidCallback fn) {
    if (mounted) super.setState(fn);
  }

  @override
  void dispose() {
    servicesFilterController.dispose();
    namePrefixController.dispose();
    manufacturerDataController.dispose();
    _searchFilterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Row(
          children: [
            Icon(
              _getBluetoothIcon(),
              color: _getBluetoothIconColor(colorScheme),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: const Text(
                'Universal BLE',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
        elevation: 0,
        backgroundColor: colorScheme.surface,
        actions: [
          PopupMenuButton<QueueType>(
            icon: const Icon(Icons.queue),
            tooltip: 'Queue Type',
            onSelected: (QueueType value) {
              setState(() {
                _queueType = value;
                UniversalBle.queueType = _queueType;
              });
            },
            itemBuilder: (BuildContext context) => [
              PopupMenuItem<QueueType>(
                value: QueueType.global,
                child: Row(
                  children: [
                    Icon(
                      _queueType == QueueType.global
                          ? Icons.check
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: _queueType == QueueType.global
                          ? colorScheme.primary
                          : colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 12),
                    const Text('Global'),
                  ],
                ),
              ),
              PopupMenuItem<QueueType>(
                value: QueueType.perDevice,
                child: Row(
                  children: [
                    Icon(
                      _queueType == QueueType.perDevice
                          ? Icons.check
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: _queueType == QueueType.perDevice
                          ? colorScheme.primary
                          : colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 12),
                    const Text('Per Device'),
                  ],
                ),
              ),
              PopupMenuItem<QueueType>(
                value: QueueType.none,
                child: Row(
                  children: [
                    Icon(
                      _queueType == QueueType.none
                          ? Icons.check
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: _queueType == QueueType.none
                          ? colorScheme.primary
                          : colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 12),
                    const Text('None'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: Icon(
              Icons.filter_list,
              color: scanFilter != null
                  ? colorScheme.primary
                  : colorScheme.onSurface,
            ),
            tooltip: 'Scan Filters',
            onPressed: _showScanFilterBottomSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          // Action Buttons Section
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ResponsiveButtonsGrid(
              children: [
                _buildScanButton(context, colorScheme),
                if (BleCapabilities.supportsConnectedDevicesApi)
                  _buildActionButton(
                    context,
                    'System Devices',
                    Icons.devices,
                    colorScheme.primary,
                    _isBluetoothAvailable ? _getSystemDevices : null,
                  ),
                if (_hiddenDevices.isNotEmpty)
                  _buildActionButton(
                    context,
                    'Unhide ${_hiddenDevices.length}',
                    Icons.visibility,
                    colorScheme.primary,
                    () {
                      setState(() {
                        _hiddenDevices.clear();
                      });
                    },
                  ),
              ],
            ),
          ),
          // Search filter
          if (_bleDevices.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchFilterController,
                  decoration: InputDecoration(
                    hintText: 'Search by name, ID, or services...',
                    prefixIcon: Icon(
                      Icons.search,
                      color: colorScheme.primary,
                    ),
                    suffixIcon: _searchFilterController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(
                              Icons.clear,
                              color:
                                  colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                            onPressed: () {
                              _searchFilterController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: colorScheme.surface,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),

          // Device count badge
          if (_bleDevices.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _filteredDevices.length == _bleDevices.length
                          ? '${_bleDevices.length} device${_bleDevices.length == 1 ? '' : 's'}'
                          : '${_filteredDevices.length} of ${_bleDevices.length} devices',
                      style: TextStyle(
                        color: colorScheme.onPrimaryContainer,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (_hiddenDevices.isEmpty) ...[
                    Tooltip(
                      message:
                          'Hide already discovered devices. When you turn on a new device, it will be easier to spot.',
                      child: TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _hiddenDevices.clear();
                            _hiddenDevices.addAll(_bleDevices);
                            _bleDevices.clear();
                          });
                        },
                        icon: Icon(
                          Icons.visibility_off,
                          size: 18,
                          color: colorScheme.onSurface,
                        ),
                        label: Text(
                          'Hide',
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _bleDevices.clear();
                      });
                    },
                    icon: Icon(
                      Icons.clear_all,
                      size: 18,
                      color: colorScheme.error,
                    ),
                    label: Text(
                      'Clear',
                      style: TextStyle(
                        color: colorScheme.error,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // Devices List
          Expanded(
            child: !_isBluetoothAvailable
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(32),
                            decoration: BoxDecoration(
                              color: colorScheme.errorContainer.withValues(
                                alpha: 0.3,
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.bluetooth_disabled,
                              size: 80,
                              color: colorScheme.error,
                            ),
                          ),
                          const SizedBox(height: 32),
                          Text(
                            'Bluetooth is Turned Off',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Please turn on Bluetooth to scan for devices',
                            style: TextStyle(
                              fontSize: 16,
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.7,
                              ),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (BleCapabilities.supportsBluetoothEnableApi) ...[
                            const SizedBox(height: 48),
                            ElevatedButton.icon(
                              onPressed: () async {
                                try {
                                  bool isEnabled =
                                      await UniversalBle.enableBluetooth();
                                  if (!isEnabled) {
                                    showSnackbar(
                                      "Please enable Bluetooth in system settings",
                                    );
                                  }
                                } catch (e) {
                                  showSnackbar(e.toString());
                                }
                              },
                              icon: const Icon(Icons.bluetooth, size: 24),
                              label: const Text(
                                'Turn On Bluetooth',
                                style: TextStyle(fontSize: 18),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: colorScheme.primary,
                                foregroundColor: colorScheme.onPrimary,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 32,
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 2,
                              ),
                            ),
                          ]
                        ],
                      ),
                    ),
                  )
                : _isScanning && _bleDevices.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator.adaptive(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Scanning for devices...',
                              style: TextStyle(
                                color: colorScheme.onSurface
                                    .withValues(alpha: 0.6),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      )
                    : !_isScanning && _bleDevices.isEmpty
                        ? const ScannedDevicesPlaceholderWidget()
                        : _filteredDevices.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.search_off,
                                      size: 64,
                                      color: colorScheme.onSurface
                                          .withValues(alpha: 0.3),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'No devices match your filter',
                                      style: TextStyle(
                                        color: colorScheme.onSurface
                                            .withValues(alpha: 0.6),
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                itemCount: _filteredDevices.length,
                                separatorBuilder: (context, index) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  BleDevice device = _filteredDevices[
                                      _filteredDevices.length - index - 1];
                                  return ScannedItemWidget(
                                    bleDevice: device,
                                    isExpanded:
                                        _isExpanded[device.deviceId] ?? false,
                                    onExpand: (isExpanded) {
                                      setState(() {
                                        _isExpanded[device.deviceId] =
                                            isExpanded;
                                      });
                                    },
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

  Widget _buildScanButton(BuildContext context, ColorScheme colorScheme) {
    final isEnabled = _isBluetoothAvailable;
    final brightness = ThemeData.estimateBrightnessForColor(
      _isScanning ? colorScheme.error : colorScheme.primary,
    );
    final textColor = isEnabled
        ? (brightness == Brightness.dark ? Colors.white : Colors.black87)
        : colorScheme.onSurface.withValues(alpha: 0.38);
    final buttonColor = isEnabled
        ? (_isScanning ? colorScheme.error : colorScheme.primary)
        : colorScheme.onSurface.withValues(alpha: 0.12);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: isEnabled
            ? [
                BoxShadow(
                  color: buttonColor.withValues(alpha: 0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ]
            : [],
      ),
      child: ElevatedButton.icon(
        onPressed: isEnabled
            ? () async {
                if (_isScanning) {
                  await UniversalBle.stopScan();
                  setState(() {
                    _isScanning = false;
                  });
                } else {
                  setState(() {
                    _bleDevices.clear();
                    _isScanning = true;
                  });
                  try {
                    await _startScan();
                  } catch (e) {
                    setState(() {
                      _isScanning = false;
                    });
                    showSnackbar(e.toString());
                  }
                }
              }
            : null,
        icon: _isScanning
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(textColor),
                ),
              )
            : const Icon(
                Icons.play_arrow,
                size: 18,
              ),
        label: Text(
          _isScanning ? 'Stop Scan' : 'Start Scan',
          style: const TextStyle(fontSize: 12),
          overflow: TextOverflow.ellipsis,
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: buttonColor,
          foregroundColor: textColor,
          disabledBackgroundColor: buttonColor,
          disabledForegroundColor: textColor,
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context,
    String text,
    IconData icon,
    Color color,
    VoidCallback? onPressed,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isEnabled = onPressed != null;
    final brightness = ThemeData.estimateBrightnessForColor(color);
    final textColor = isEnabled
        ? (brightness == Brightness.dark ? Colors.white : Colors.black87)
        : colorScheme.onSurface.withValues(alpha: 0.38);
    final buttonColor =
        isEnabled ? color : colorScheme.onSurface.withValues(alpha: 0.12);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: isEnabled
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ]
            : [],
      ),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(
          text,
          style: const TextStyle(fontSize: 12),
          overflow: TextOverflow.ellipsis,
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: buttonColor,
          foregroundColor: textColor,
          disabledBackgroundColor: buttonColor,
          disabledForegroundColor: textColor,
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
      ),
    );
  }

  IconData _getBluetoothIcon() {
    switch (bleAvailabilityState) {
      case AvailabilityState.poweredOn:
        return Icons.bluetooth_connected;
      case AvailabilityState.poweredOff:
        return Icons.bluetooth_disabled;
      case AvailabilityState.unauthorized:
        return Icons.bluetooth_disabled;
      case AvailabilityState.unsupported:
        return Icons.bluetooth_disabled;
      case AvailabilityState.unknown:
      default:
        return Icons.bluetooth_searching;
    }
  }

  Color _getBluetoothIconColor(ColorScheme colorScheme) {
    switch (bleAvailabilityState) {
      case AvailabilityState.poweredOn:
        return colorScheme.primary;
      case AvailabilityState.poweredOff:
        return colorScheme.error;
      case AvailabilityState.unauthorized:
        return colorScheme.error;
      case AvailabilityState.unsupported:
        return colorScheme.outline;
      case AvailabilityState.unknown:
      default:
        return colorScheme.onSurface.withValues(alpha: 0.6);
    }
  }
}
