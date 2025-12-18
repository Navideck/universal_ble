import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:universal_ble_example/data/mock_universal_ble.dart';
import 'package:universal_ble_example/home/widgets/ble_availability_icon.dart';
import 'package:universal_ble_example/home/widgets/drawer.dart';
import 'package:universal_ble_example/home/widgets/scan_filter_widget.dart';
import 'package:universal_ble_example/home/widgets/scanned_devices_placeholder_widget.dart';
import 'package:universal_ble_example/home/widgets/scanned_item_widget.dart';
import 'package:universal_ble_example/peripheral_details/peripheral_detail_page.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final _bleDevices = <BleDevice>[];
  final _hiddenDevices = <BleDevice>[];
  bool _isScanning = false;
  QueueType _queueType = QueueType.global;
  TextEditingController servicesFilterController = TextEditingController();
  TextEditingController namePrefixController = TextEditingController();
  TextEditingController manufacturerDataController = TextEditingController();
  final TextEditingController _searchFilterController = TextEditingController();
  final TextEditingController _webServicesController = TextEditingController();
  StreamSubscription<BleDevice>? _scanSubscription;

  AvailabilityState? bleAvailabilityState;
  ScanFilter? scanFilter;
  final Map<String, bool> _isExpanded = {};

  @override
  void initState() {
    super.initState();
    if (const bool.fromEnvironment('MOCK')) {
      UniversalBle.setInstance(MockUniversalBle());
    }
    UniversalBle.queueType = _queueType;
    UniversalBle.timeout = const Duration(seconds: 10);

    _scanSubscription = UniversalBle.scanStream.listen(_handleScanResult);

    UniversalBle.isScanning().then(
      (isScanning) => setState(() => _isScanning = isScanning),
    );
  }

  void _handleScanResult(BleDevice result) {
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
    PlatformConfig? platformConfig;
    if (kIsWeb && _webServicesController.text.isNotEmpty) {
      List<String> webServices = _webServicesController.text
          .split(',')
          .where((s) => s.trim().isNotEmpty)
          .map((s) {
        try {
          return BleUuidParser.string(s.trim());
        } catch (_) {
          return s.trim();
        }
      }).toList();
      platformConfig = PlatformConfig(
        web: WebOptions(optionalServices: webServices),
      );
    }
    await UniversalBle.startScan(
      scanFilter: scanFilter,
      platformConfig: platformConfig,
    );
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
    _webServicesController.dispose();

    _scanSubscription?.cancel();
    super.dispose();
  }

  void _showQueueBottomSheet() {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.queue,
                    color: colorScheme.primary,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "Queue Type",
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Close',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                "Controls how BLE commands are executed. Global queue executes all commands sequentially. Per Device queue executes commands for each device separately. None executes all commands in parallel.",
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
              ),
              const SizedBox(height: 24),
              _buildQueueOption(
                context,
                QueueType.global,
                'Global',
                'All commands from all devices execute sequentially in a single queue',
                Icons.queue,
              ),
              const SizedBox(height: 12),
              _buildQueueOption(
                context,
                QueueType.perDevice,
                'Per Device',
                'Commands for each device execute in separate queues',
                Icons.devices,
              ),
              const SizedBox(height: 12),
              _buildQueueOption(
                context,
                QueueType.none,
                'None',
                'All commands execute in parallel without queuing',
                Icons.all_inclusive,
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQueueOption(
    BuildContext context,
    QueueType value,
    String title,
    String description,
    IconData icon,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = _queueType == value;
    return InkWell(
      onTap: () {
        setState(() {
          _queueType = value;
          UniversalBle.queueType = _queueType;
        });
        Navigator.pop(context);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.outline.withValues(alpha: 0.2),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurface,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: isSelected
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected
                          ? colorScheme.onPrimaryContainer
                              .withValues(alpha: 0.7)
                          : colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: Row(
          children: [
            BleAvailabilityIcon(onAvailabilityStateChanged: (state) {
              setState(() => bleAvailabilityState = state);
            }),
            const SizedBox(width: 12),
            Expanded(
              child: const Text(
                'Scanner',
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
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isScanning ? Icons.stop_circle : Icons.play_arrow,
              color: _isScanning ? colorScheme.error : colorScheme.primary,
            ),
            tooltip: _isScanning ? 'Stop Scan' : 'Start Scan',
            onPressed: _isBluetoothAvailable
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
          ),
          IconButton(
            icon: Icon(
              Icons.queue,
              color: colorScheme.onSurface,
            ),
            tooltip: 'Queue Type',
            onPressed: _showQueueBottomSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search filter
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
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
                            color: colorScheme.onSurface.withValues(alpha: 0.6),
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
                  fillColor: colorScheme.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),
          // Web Services input (only for web)
          if (kIsWeb)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.web,
                            size: 18,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Ble Services',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: TextFormField(
                        controller: _webServicesController,
                        maxLines: 2,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12),
                        decoration: InputDecoration(
                          hintText:
                              'Enter service UUIDs for web (comma-separated)',
                          helperText:
                              'These services will be available to use after connection on Web',
                          helperMaxLines: 2,
                          helperStyle: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: colorScheme.surface,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Device count badge with hide/unhide
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _filteredDevices.length == _bleDevices.length
                            ? '${_bleDevices.length} device${_bleDevices.length == 1 ? '' : 's'}'
                            : '${_filteredDevices.length} of ${_bleDevices.length} devices',
                        style: TextStyle(
                          color: colorScheme.onPrimaryContainer,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_hiddenDevices.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          '/ ${_hiddenDevices.length} hidden',
                          style: TextStyle(
                            color: colorScheme.onPrimaryContainer
                                .withValues(alpha: 0.7),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (_hiddenDevices.isNotEmpty)
                  Tooltip(
                    message: 'Show hidden devices.',
                    child: TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _hiddenDevices.clear();
                        });
                      },
                      icon: Icon(
                        Icons.visibility,
                        size: 18,
                        color: colorScheme.onSurface,
                      ),
                      label: Text(
                        'Unhide',
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                else if (_bleDevices.isNotEmpty)
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
                        'Hide ${_bleDevices.length}',
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                const Spacer(),
                // Scan Filter button
                if (scanFilter != null)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.filter_list,
                          size: 14,
                          color: colorScheme.onPrimaryContainer,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Filter',
                          style: TextStyle(
                            color: colorScheme.onPrimaryContainer,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                TextButton.icon(
                  onPressed: _showScanFilterBottomSheet,
                  icon: Icon(
                    scanFilter != null
                        ? Icons.filter_list
                        : Icons.filter_list_outlined,
                    size: 18,
                    color: scanFilter != null
                        ? colorScheme.primary
                        : colorScheme.onSurface,
                  ),
                  label: Text(
                    'Filter',
                    style: TextStyle(
                      color: scanFilter != null
                          ? colorScheme.primary
                          : colorScheme.onSurface,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
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
          const Divider(),
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
}
