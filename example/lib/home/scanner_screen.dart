import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:universal_ble_example/data/company_identifier_service.dart';
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
  final Map<String, int> _deviceAdFlashTrigger = {};

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

    // Get initial Bluetooth availability state
    UniversalBle.getBluetoothAvailabilityState().then((state) {
      if (mounted) {
        setState(() => bleAvailabilityState = state);
      }
    });

    _loadScanFilters().then((_) {
      // Auto-start scanning after filters are loaded
      _tryAutoStartScan();
    });

    // Load company identifiers in the background
    CompanyIdentifierService.instance.load();

    // Save search filter when it changes
    _searchFilterController.addListener(() {
      _saveScanFilters();
    });
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
    _deviceAdFlashTrigger[result.deviceId] =
        (_deviceAdFlashTrigger[result.deviceId] ?? 0) + 1;
    setState(() {});
  }

  Future<void> _startScan() async {
    setState(() {
      _bleDevices.clear();
      _isScanning = true;
    });
    try {
      PlatformConfig platformConfig = PlatformConfig(
        android: AndroidOptions(
          scanMode: AndroidScanMode.lowLatency,
        ),
      );
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
        platformConfig.web = WebOptions(optionalServices: webServices);
      }

      await UniversalBle.startScan(
        scanFilter: scanFilter,
        platformConfig: platformConfig,
      );
    } catch (e) {
      setState(() {
        _isScanning = false;
      });
      showSnackbar(e.toString());
    }
  }

  Future<void> _loadScanFilters() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final services = prefs.getString('scan_filter_services') ?? '';
      final namePrefix = prefs.getString('scan_filter_name_prefix') ?? '';
      final manufacturerData =
          prefs.getString('scan_filter_manufacturer_data') ?? '';
      final searchFilter = prefs.getString('scan_filter_search') ?? '';

      servicesFilterController.text = services;
      namePrefixController.text = namePrefix;
      manufacturerDataController.text = manufacturerData;
      _searchFilterController.text = searchFilter;

      // Reconstruct the scan filter if any values exist
      if (services.isNotEmpty ||
          namePrefix.isNotEmpty ||
          manufacturerData.isNotEmpty) {
        _applyFilterFromControllers();
      }
    } catch (e) {
      // Silently fail if preferences can't be loaded
      debugPrint('Failed to load scan filters: $e');
    }
  }

  Future<void> _saveScanFilters() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'scan_filter_services', servicesFilterController.text);
      await prefs.setString(
          'scan_filter_name_prefix', namePrefixController.text);
      await prefs.setString(
          'scan_filter_manufacturer_data', manufacturerDataController.text);
      await prefs.setString('scan_filter_search', _searchFilterController.text);
    } catch (e) {
      debugPrint('Failed to save scan filters: $e');
    }
  }

  void _applyFilterFromControllers() async {
    try {
      // Ensure company identifier service is loaded
      await CompanyIdentifierService.instance.load();
      List<String> serviceUUids = [];
      List<String> namePrefixes = [];
      List<ManufacturerDataFilter> manufacturerDataFilters = [];

      // Parse Services
      if (servicesFilterController.text.isNotEmpty) {
        List<String> services = servicesFilterController.text
            .split(',')
            .map((e) => e.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        for (String service in services) {
          try {
            serviceUUids.add(BleUuidParser.string(service.trim()));
          } on FormatException catch (_) {
            // Skip invalid service UUIDs when loading from preferences
            continue;
          }
        }
      }

      // Parse Name Prefix
      String namePrefix = namePrefixController.text;
      if (namePrefix.isNotEmpty) {
        namePrefixes = namePrefix.split(',').map((e) => e.trim()).toList();
      }

      // Parse Manufacturer Data
      String manufacturerDataText = manufacturerDataController.text;
      if (manufacturerDataText.isNotEmpty) {
        final companyService = CompanyIdentifierService.instance;
        List<String> manufacturerData = manufacturerDataText
            .split(',')
            .map((e) => e.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        for (String manufacturer in manufacturerData) {
          final companyIdentifier =
              companyService.parseCompanyIdentifier(manufacturer);
          if (companyIdentifier == null) {
            // Skip invalid manufacturer data when loading from preferences
            continue;
          }
          manufacturerDataFilters.add(
              ManufacturerDataFilter(companyIdentifier: companyIdentifier));
        }
      }

      if (serviceUUids.isEmpty &&
          namePrefixes.isEmpty &&
          manufacturerDataFilters.isEmpty) {
        scanFilter = null;
      } else {
        scanFilter = ScanFilter(
          withServices: serviceUUids,
          withNamePrefix: namePrefixes,
          withManufacturerData: manufacturerDataFilters,
        );
      }
      setState(() {});
    } catch (e) {
      // Silently fail if filter can't be applied
      debugPrint('Failed to apply filter from controllers: $e');
    }
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
            _saveScanFilters();
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
    final companyService = CompanyIdentifierService.instance;

    // Try to parse the filter as a company ID (supports hex and decimal formats)
    final parsedCompanyId =
        companyService.parseCompanyIdentifier(_searchFilterController.text);

    return _bleDevices.where((device) {
      final name = device.name?.toLowerCase() ?? '';
      final deviceId = device.deviceId.toLowerCase();
      final services = device.services.join(' ').toLowerCase();

      // Check if filter matches device name, ID, or services
      if (name.contains(filter) ||
          deviceId.contains(filter) ||
          services.contains(filter)) {
        return true;
      }

      // Check if filter matches any company name or company ID from manufacturer data
      for (final manufacturerData in device.manufacturerDataList) {
        // Check company name match
        final companyName =
            companyService.getCompanyName(manufacturerData.companyId);
        if (companyName != null && companyName.toLowerCase().contains(filter)) {
          return true;
        }

        // Check company ID match (if filter was parsed as a company ID)
        if (parsedCompanyId != null &&
            manufacturerData.companyId == parsedCompanyId) {
          return true;
        }

        // Also check if filter matches the hex representation of company ID
        final companyIdHex = manufacturerData.companyIdRadix16.toLowerCase();
        if (companyIdHex.contains(filter) ||
            companyIdHex.replaceAll('0x', '').contains(filter)) {
          return true;
        }
      }

      return false;
    }).toList();
  }

  bool get _isBluetoothAvailable =>
      bleAvailabilityState == AvailabilityState.poweredOn;

  Future<void> _tryAutoStartScan() async {
    // Only auto-start if Bluetooth is available and not already scanning
    if (_isBluetoothAvailable && !_isScanning) {
      // Check again to make sure we're not already scanning
      final isScanning = await UniversalBle.isScanning();
      if (!isScanning && mounted) {
        await _startScan();
      }
    }
  }

  String _getBluetoothAvailabilityTooltip() {
    switch (bleAvailabilityState) {
      case AvailabilityState.poweredOn:
        return 'Bluetooth is on';
      case AvailabilityState.poweredOff:
        return 'Bluetooth is off';
      case AvailabilityState.resetting:
        return 'Bluetooth is resetting';
      case AvailabilityState.unauthorized:
        return 'Bluetooth permission denied';
      case AvailabilityState.unsupported:
        return 'Bluetooth not supported';
      case AvailabilityState.unknown:
        return 'Bluetooth status unknown';
      case null:
        return 'Checking Bluetooth status...';
    }
  }

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      drawer: AppDrawer(
        queueType: _queueType,
        onQueueTypeChanged: (queueType) {
          setState(() {
            _queueType = queueType;
            UniversalBle.queueType = _queueType;
          });
        },
      ),
      appBar: AppBar(
        title: Row(
          children: [
            Expanded(
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: TextField(
                  controller: _searchFilterController,
                  decoration: InputDecoration(
                    hintText: 'Search by name, ID, service, company name/ID',
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
                              _saveScanFilters();
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
            const SizedBox(width: 12),
            Tooltip(
              message: _getBluetoothAvailabilityTooltip(),
              triggerMode: TooltipTriggerMode.tap,
              child: BleAvailabilityIcon(onAvailabilityStateChanged: (state) {
                setState(() => bleAvailabilityState = state);
                // Auto-start scanning when Bluetooth becomes available
                if (state == AvailabilityState.poweredOn) {
                  _tryAutoStartScan();
                }
              }),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: FilledButton.icon(
              onPressed: _isBluetoothAvailable
                  ? () async {
                      if (_isScanning) {
                        await UniversalBle.stopScan();
                        setState(() {
                          _isScanning = false;
                        });
                      } else {
                        await _startScan();
                      }
                    }
                  : null,
              icon: Icon(
                _isScanning ? Icons.stop_circle : Icons.play_arrow,
                size: 20,
              ),
              label: Text(
                _isScanning ? 'Stop Scan' : 'Start Scan',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor:
                    _isScanning ? colorScheme.error : colorScheme.primary,
                foregroundColor:
                    _isScanning ? colorScheme.onError : colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: _isScanning ? 0 : 2,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
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
                Tooltip(
                  message: _hiddenDevices.isNotEmpty
                      ? 'Show hidden devices'
                      : _bleDevices.isNotEmpty
                          ? 'Hide already discovered devices. When you turn on a new device, it will be easier to spot.'
                          : '',
                  child: TextButton.icon(
                    onPressed:
                        _bleDevices.isNotEmpty || _hiddenDevices.isNotEmpty
                            ? () {
                                if (_hiddenDevices.isNotEmpty) {
                                  // Unhide all devices
                                  setState(() {
                                    _hiddenDevices.clear();
                                  });
                                } else if (_bleDevices.isNotEmpty) {
                                  // Hide all devices
                                  setState(() {
                                    _hiddenDevices.clear();
                                    _hiddenDevices.addAll(_bleDevices);
                                    _bleDevices.clear();
                                  });
                                }
                              }
                            : null,
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${_bleDevices.length} ${_hiddenDevices.isNotEmpty ? "/ ${_hiddenDevices.length}" : ""} device${_bleDevices.length == 1 ? '' : 's'}',
                          style: TextStyle(
                            color: colorScheme.onPrimaryContainer,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          _hiddenDevices.isNotEmpty
                              ? Icons.visibility
                              : Icons.visibility_off,
                          size: 16,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ],
                    ),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      backgroundColor: colorScheme.primaryContainer,
                    ),
                  ),
                ),
                const Spacer(),
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
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    backgroundColor: scanFilter != null
                        ? colorScheme.primaryContainer
                        : null,
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
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 8),
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
                        ? ScannedDevicesPlaceholderWidget(onTap: _startScan)
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
                                    adFlashTrigger:
                                        _deviceAdFlashTrigger[device.deviceId] ??
                                            0,
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
