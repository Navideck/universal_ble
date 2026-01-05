import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:universal_ble_example/home/widgets/ble_availability_icon.dart';
import 'package:universal_ble_example/home/widgets/drawer.dart';
import 'package:universal_ble_example/home/widgets/scanned_item_widget.dart';
import 'package:universal_ble_example/peripheral_details/peripheral_detail_page.dart';

class SystemDevicesScreen extends StatefulWidget {
  const SystemDevicesScreen({super.key});

  @override
  State<SystemDevicesScreen> createState() => _SystemDevicesScreenState();
}

class _SystemDevicesScreenState extends State<SystemDevicesScreen> {
  List<BleDevice> _systemDevices = [];
  bool _isLoading = false;
  AvailabilityState? bleAvailabilityState;
  List<String> withServices = [];
  final Map<String, bool> _isExpanded = {};
  final TextEditingController _servicesController = TextEditingController();

  void _parseServices() {
    setState(() {
      withServices = [];
      if (_servicesController.text.isNotEmpty) {
        final services = _servicesController.text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        for (String service in services) {
          try {
            withServices.add(BleUuidParser.string(service));
          } catch (e) {
            _showSnackbar("Invalid Service UUID: $service");
            return;
          }
        }
      }
    });
  }

  Future<void> _getSystemDevices() async {
    _parseServices();

    // For macOS and iOS, it is recommended to set a filter to get system devices
    if ((defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.iOS) &&
        withServices.isEmpty) {
      _showSnackbar(
        "No services filter was set for getting system connected devices. Using default services...",
      );
    }

    setState(() {
      _isLoading = true;
    });

    try {
      List<BleDevice> devices = await UniversalBle.getSystemDevices(
        withServices: withServices,
      );
      setState(() {
        _systemDevices = devices;
        _isLoading = false;
      });
      if (devices.isEmpty) {
        _showSnackbar("No System Connected Devices Found");
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showSnackbar(e.toString());
    }
  }

  void _showSnackbar(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  bool get _isBluetoothAvailable =>
      bleAvailabilityState == AvailabilityState.poweredOn;

  @override
  void setState(VoidCallback fn) {
    if (mounted) super.setState(fn);
  }

  @override
  void dispose() {
    _servicesController.dispose();
    super.dispose();
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
                'System Devices',
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
          IconButton(
            icon: Icon(
              Icons.refresh,
              color: colorScheme.primary,
            ),
            tooltip: 'Refresh',
            onPressed: _isBluetoothAvailable ? _getSystemDevices : null,
          ),
        ],
      ),
      body: Column(
        children: [
          // Services input text box
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.apps,
                          color: colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Service UUIDs (Optional)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enter service UUIDs separated by commas. Leave empty to use default services.\nMandatory on Apple platforms.',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _servicesController,
                      maxLines: 8,
                      minLines: 4,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                      decoration: InputDecoration(
                        hintText:
                            'eg: 0000180f-0000-1000-8000-00805f9b34fb, 0000180a-0000-1000-8000-00805f9b34fb',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest,
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isBluetoothAvailable && !_isLoading
                    ? _getSystemDevices
                    : null,
                icon: _isLoading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            colorScheme.onPrimary,
                          ),
                        ),
                      )
                    : const Icon(Icons.search),
                label: Text(_isLoading ? 'Loading...' : 'Get System Devices'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
              ),
            ),
          ),
          if (_systemDevices.isNotEmpty)
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
                      '${_systemDevices.length} device${_systemDevices.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        color: colorScheme.onPrimaryContainer,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const Divider(),
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
                            'Please turn on Bluetooth to get system devices',
                            style: TextStyle(
                              fontSize: 16,
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.7,
                              ),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                : _systemDevices.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.devices_outlined,
                              size: 64,
                              color:
                                  colorScheme.onSurface.withValues(alpha: 0.3),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No system devices found',
                              style: TextStyle(
                                color: colorScheme.onSurface
                                    .withValues(alpha: 0.6),
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Click "Get System Devices" to refresh',
                              style: TextStyle(
                                color: colorScheme.onSurface
                                    .withValues(alpha: 0.5),
                                fontSize: 14,
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
                        itemCount: _systemDevices.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          BleDevice device = _systemDevices[index];
                          return ScannedItemWidget(
                            bleDevice: device,
                            isExpanded: _isExpanded[device.deviceId] ?? false,
                            onExpand: (isExpanded) {
                              setState(() {
                                _isExpanded[device.deviceId] = isExpanded;
                              });
                            },
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PeripheralDetailPage(device),
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
