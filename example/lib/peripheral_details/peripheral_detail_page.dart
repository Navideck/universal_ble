import 'dart:async';

import 'package:convert/convert.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:universal_ble_example/data/storage_service.dart';
import 'package:universal_ble_example/peripheral_details/widgets/result_widget.dart';
import 'package:universal_ble_example/peripheral_details/widgets/services_list_widget.dart';
import 'package:universal_ble_example/peripheral_details/widgets/services_side_widget.dart';
import 'package:universal_ble_example/widgets/responsive_view.dart';

class PeripheralDetailPage extends StatefulWidget {
  final BleDevice bleDevice;
  const PeripheralDetailPage(this.bleDevice, {super.key});

  @override
  State<StatefulWidget> createState() {
    return _PeripheralDetailPageState();
  }
}

class _PeripheralDetailPageState extends State<PeripheralDetailPage> {
  late final bleDevice = widget.bleDevice;
  bool isConnected = false;
  GlobalKey<FormState> valueFormKey = GlobalKey<FormState>();
  List<BleService> discoveredServices = [];
  final List<String> _logs = [];
  final binaryCode = TextEditingController();
  bool _isLoading = false;
  bool _isDeviceInfoExpanded = false;
  bool _isDeviceActionsExpanded = true;
  final Map<String, bool> _subscribedCharacteristics = {};
  bool _autoConnect = false;

  StreamSubscription? connectionStreamSubscription;
  StreamSubscription? pairingStateSubscription;
  BleService? selectedService;
  BleCharacteristic? selectedCharacteristic;
  final ScrollController _logsScrollController = ScrollController();
  final Set<String> _favoriteServices = {};

  void _loadFavoriteServices() {
    final favorites = StorageService.instance.getFavoriteServices();
    setState(() {
      _favoriteServices.addAll(favorites);
    });
  }

  Future<void> _saveFavoriteServices() async {
    await StorageService.instance.setFavoriteServices(
      _favoriteServices.toList(),
    );
  }

  @override
  void initState() {
    super.initState();

    connectionStreamSubscription = bleDevice.connectionStream.listen(
      _handleConnectionChange,
    );
    pairingStateSubscription = bleDevice.pairingStateStream.listen(
      _handlePairingStateChange,
    );
    UniversalBle.onValueChange = _handleValueChange;

    bleDevice.connectionState.then((state) {
      _handleConnectionChange(state == BleConnectionState.connected);
    });
    _loadFavoriteServices();
  }

  @override
  void dispose() {
    super.dispose();
    connectionStreamSubscription?.cancel();
    pairingStateSubscription?.cancel();
    UniversalBle.onValueChange = null;
  }

  void _addLog(String type, dynamic data) {
    setState(() {
      _logs.add('$type: ${data.toString()}');
    });
  }

  void _handleConnectionChange(bool isConnected) {
    debugPrint('_handleConnectionChange $isConnected');
    setState(() {
      this.isConnected = isConnected;
    });
    _addLog('Connection', isConnected ? "Connected" : "Disconnected");
    // Auto Discover Services
    if (this.isConnected) {
      _discoverServices();
    }
  }

  void _handleValueChange(
    String deviceId,
    String characteristicId,
    Uint8List value,
    int? timestamp,
  ) {
    String s = String.fromCharCodes(value);
    String data = '$s\nraw :  ${value.toString()}';
    DateTime? timestampDateTime = timestamp != null
        ? DateTime.fromMillisecondsSinceEpoch(timestamp)
        : null;
    debugPrint('_handleValueChange ($timestampDateTime) $characteristicId, $s');
    _addLog("Value", data);
  }

  void _handlePairingStateChange(bool isPaired) {
    debugPrint('isPaired $isPaired');
    _addLog("PairingStateChange - isPaired", isPaired);
  }

  Future<void> _discoverServices() async {
    const webWarning =
        "Note: Only services added in ScanFilter or WebOptions will be discovered";

    await _executeWithLoading(
      () async {
        var services = await bleDevice.discoverServices(withDescriptors: false);
        debugPrint('${services.length} services discovered');
        debugPrint(_formattedServices(services));
        setState(() {
          discoveredServices = services;
        });
        _addLog(
          "DiscoverServices",
          kIsWeb
              ? '${services.length} services discovered,\n$webWarning\n\n${_formattedServices(services)}'
              : '${services.length} services discovered\n\n${_formattedServices(services)}',
        );
      },
      onError: (error) {
        _addLog("DiscoverServicesError", '$error\n${kIsWeb ? webWarning : ""}');
      },
    );
  }

  Future<void> _readValue() async {
    BleCharacteristic? selectedCharacteristic = this.selectedCharacteristic;
    if (selectedCharacteristic == null) return;
    await _executeWithLoading(
      () async {
        Uint8List value = await selectedCharacteristic.read();
        String s = String.fromCharCodes(value);
        String data = '$s\nraw :  ${value.toString()}';
        _addLog('Read', data);
      },
      onError: (error) {
        _addLog('ReadError', error);
      },
    );
  }

  Future<void> _writeValue() async {
    BleCharacteristic? selectedCharacteristic = this.selectedCharacteristic;
    if (selectedCharacteristic == null ||
        !valueFormKey.currentState!.validate() ||
        binaryCode.text.isEmpty) {
      return;
    }

    Uint8List value;
    try {
      value = Uint8List.fromList(hex.decode(binaryCode.text));
    } catch (e) {
      _addLog('WriteError', "Error parsing hex $e");
      return;
    }

    bool writeWithResponse = true;
    if (!selectedCharacteristic.properties.contains(
      CharacteristicProperty.write,
    )) {
      writeWithResponse = false;
    }

    await _executeWithLoading(
      () async {
        await selectedCharacteristic.write(
          value,
          withResponse: writeWithResponse,
        );
        _addLog('Write${writeWithResponse ? "" : "WithoutResponse"}', value);
      },
      onError: (error) {
        _addLog('WriteError', error);
      },
    );
  }

  Future<void> _subscribeChar() async {
    BleCharacteristic? selectedCharacteristic = this.selectedCharacteristic;
    if (selectedCharacteristic == null) return;
    await _executeWithLoading(
      () async {
        var subscription = _getCharacteristicSubscription(
          selectedCharacteristic,
        );
        if (subscription == null) throw 'No notify or indicate property';
        await subscription.subscribe();
        setState(() {
          _subscribedCharacteristics[selectedCharacteristic.uuid] = true;
        });
        _addLog('BleCharSubscription', 'Subscribed');
      },
      onError: (error) {
        _addLog('NotifyError', error);
      },
    );
  }

  Future<void> _unsubscribeChar() async {
    final char = selectedCharacteristic;
    if (char == null) return;
    await _executeWithLoading(
      () async {
        await char.unsubscribe();
        setState(() {
          _subscribedCharacteristics.remove(char.uuid);
        });
        _addLog('BleCharSubscription', 'UnSubscribed');
      },
      onError: (error) {
        _addLog('NotifyError', error);
      },
    );
  }

  Future<void> _subscribeToAllCharacteristics() async {
    if (!isConnected) return;
    await _executeWithLoading(
      () async {
        int successCount = 0;
        int errorCount = 0;
        for (var service in discoveredServices) {
          for (var characteristic in service.characteristics) {
            var subscription = _getCharacteristicSubscription(characteristic);
            if (subscription != null) {
              try {
                await subscription.subscribe();
                setState(() {
                  _subscribedCharacteristics[characteristic.uuid] = true;
                });
                successCount++;
              } catch (e) {
                errorCount++;
                debugPrint('Failed to subscribe to ${characteristic.uuid}: $e');
              }
            }
          }
        }
        _addLog(
          'BleCharSubscription',
          'Subscribed to $successCount characteristics${errorCount > 0 ? ', $errorCount failed' : ''}',
        );
      },
      onError: (error) {
        _addLog('SubscribeToAllCharacteristicsError', error);
      },
    );
  }

  CharacteristicSubscription? _getCharacteristicSubscription(
    BleCharacteristic characteristic,
  ) {
    var properties = characteristic.properties;
    if (properties.contains(CharacteristicProperty.notify)) {
      return characteristic.notifications;
    } else if (properties.contains(CharacteristicProperty.indicate)) {
      return characteristic.indications;
    }
    return null;
  }

  Future<T> _executeWithLoading<T>(
    Future<T> Function() action, {
    Function(dynamic error)? onError,
  }) async {
    setState(() {
      _isLoading = true;
    });
    try {
      return await action();
    } catch (e) {
      onError?.call(e);
      rethrow;
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showCharacteristicSelector() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(bottom: 10.0),
          child: ServicesSideWidget(
            discoveredServices: discoveredServices,
            serviceListBuilder: () => _buildServicesList(onSelect: (_, __) {
              Navigator.pop(context);
            }),
            onCopyServices: discoveredServices.isNotEmpty
                ? () async {
                    final servicesText = _formattedServices(discoveredServices);
                    await Clipboard.setData(
                      ClipboardData(text: servicesText),
                    );
                    if (context.mounted) {
                      _showSnackBar('All services copied to clipboard');
                      Navigator.pop(context);
                    }
                  }
                : null,
          ),
        );
      },
    );
  }

  void _showSnackBar(String message) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
    }
  }

  String _formattedServices(List<BleService> services) {
    final buffer = StringBuffer();
    for (var service in services) {
      buffer.writeln('Service: ${service.uuid}');
      for (var characteristic in service.characteristics) {
        final properties =
            characteristic.properties.map((p) => p.name).join(', ');
        buffer.writeln(
            '  Characteristic: ${characteristic.uuid} (properties: $properties)');
      }
      buffer.writeln();
    }
    return buffer.toString().trim();
  }

  @override
  void setState(VoidCallback fn) {
    if (mounted) super.setState(fn);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ResponsiveView(
      builder: (_, DeviceType deviceType) {
        return Scaffold(
          appBar: AppBar(
            title: Text(
              bleDevice.name ?? "Unknown Device",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            centerTitle: false,
            elevation: 0,
            actions: [
              Visibility.maintain(
                visible: _isLoading,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
              if (deviceType != DeviceType.desktop)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Icon(
                    isConnected
                        ? Icons.bluetooth_connected
                        : Icons.bluetooth_disabled,
                    color: isConnected
                        ? Colors.green
                        : colorScheme.onSurface.withValues(alpha: 0.6),
                    size: 20,
                  ),
                )
              else
                Container(
                  margin: const EdgeInsets.only(right: 16),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isConnected
                        ? Colors.green.withValues(alpha: 0.2)
                        : Colors.orange.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isConnected
                            ? Icons.check_circle
                            : Icons.bluetooth_disabled,
                        size: 16,
                        color: isConnected
                            ? Colors.green.shade700
                            : Colors.orange.shade700,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isConnected ? 'Connected' : 'Disconnected',
                        style: TextStyle(
                          color: isConnected
                              ? Colors.green.shade700
                              : Colors.orange.shade700,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Services side widget on desktop
              if (deviceType == DeviceType.desktop)
                Expanded(
                  flex: 1,
                  child: ServicesSideWidget(
                    discoveredServices: discoveredServices,
                    serviceListBuilder: _buildServicesList,
                    onCopyServices: discoveredServices.isNotEmpty
                        ? () async {
                            final servicesText =
                                _formattedServices(discoveredServices);
                            await Clipboard.setData(
                              ClipboardData(text: servicesText),
                            );
                            _showSnackBar('All services copied to clipboard');
                          }
                        : null,
                  ),
                ),
              // Main content
              Expanded(
                flex: 2,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // Device info with manufacturer data and advertised services
                      _buildDeviceInfo(),

                      // Connect/Disconnect button
                      _buildConnectDisconnectButton(),

                      // Device Actions
                      _buildDeviceActions(),

                      // Characteristic selector
                      _buildCharacteristicSelector(),

                      // Characteristic Actions
                      _buildCharacteristicActions(),

                      // Logs on bottom for mobile
                      if (deviceType != DeviceType.desktop) ...[
                        const Divider(),
                        _buildResultWidget(scrollable: false),
                      ],
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),

              // Logs on right side for desktop
              if (deviceType == DeviceType.desktop)
                Expanded(
                  flex: 1,
                  child: _buildResultWidget(
                    scrollable: true,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCharacteristicActions() {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 16.0,
        vertical: 8.0,
      ),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.tune,
                    color: colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Characteristic Actions',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Form(
                key: valueFormKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: binaryCode,
                      enabled: isConnected &&
                          _hasSelectedCharacteristicProperty([
                            CharacteristicProperty.write,
                            CharacteristicProperty.writeWithoutResponse,
                          ]),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a value';
                        }
                        try {
                          hex.decode(binaryCode.text);
                          return null;
                        } catch (e) {
                          return 'Please enter a valid hex value ( without spaces or 0x (e.g. F0BB) )';
                        }
                      },
                      decoration: InputDecoration(
                        hintText:
                            "Enter Hex values without spaces or 0x (e.g. F0BB)",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest,
                        prefixIcon: Icon(
                          Icons.code,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: isConnected &&
                                    _hasSelectedCharacteristicProperty([
                                      CharacteristicProperty.write,
                                      CharacteristicProperty
                                          .writeWithoutResponse,
                                    ])
                                ? _writeValue
                                : null,
                            icon: const Icon(Icons.send),
                            label: const Text('Write'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colorScheme.primary,
                              foregroundColor: colorScheme.onPrimary,
                              padding: const EdgeInsets.symmetric(
                                vertical: 16,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: isConnected &&
                                    _hasSelectedCharacteristicProperty([
                                      CharacteristicProperty.read,
                                    ])
                                ? _readValue
                                : null,
                            icon: const Icon(Icons.download),
                            label: const Text('Read'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colorScheme.secondary,
                              foregroundColor: colorScheme.onSecondary,
                              padding: const EdgeInsets.symmetric(
                                vertical: 16,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  ElevatedButton.icon(
                    onPressed: isConnected &&
                            discoveredServices.isNotEmpty &&
                            selectedCharacteristic != null &&
                            _hasSelectedCharacteristicProperty([
                              CharacteristicProperty.notify,
                              CharacteristicProperty.indicate,
                            ])
                        ? _subscribeChar
                        : null,
                    icon: const Icon(Icons.notifications_active),
                    label: const Text('Subscribe'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: isConnected &&
                            discoveredServices.isNotEmpty &&
                            selectedCharacteristic != null &&
                            _hasSelectedCharacteristicProperty([
                              CharacteristicProperty.notify,
                              CharacteristicProperty.indicate,
                            ])
                        ? _unsubscribeChar
                        : null,
                    icon: const Icon(Icons.notifications_off),
                    label: const Text('Unsubscribe'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.onSurface,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: isConnected && discoveredServices.isNotEmpty
                        ? _subscribeToAllCharacteristics
                        : null,
                    icon: const Icon(Icons.notifications_active),
                    label: const Text('Subscribe All'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectDisconnectButton() {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 16.0,
        vertical: 8.0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AutoConnect toggle
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            color: colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.autorenew,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Auto Reconnect',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          'Automatically reconnect when device becomes available',
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _autoConnect,
                    onChanged: (value) async {
                      // If toggling off auto-connect, disconnect to prevent unwanted reconnections
                      if (!value && _autoConnect) {
                        if (isConnected) {
                          // Device is connected, disconnect it to prevent auto-reconnect
                          await _executeWithLoading(
                            () async {
                              await bleDevice.disconnect();
                              _addLog("DisconnectResult",
                                  "Disconnected to disable auto-reconnect");
                            },
                            onError: (error) {
                              _addLog('DisconnectError', error);
                            },
                          );
                        } else {
                          // Device is already disconnected, but call disconnect() anyway
                          // to ensure cleanup and prevent any pending auto-reconnection attempts
                          await _executeWithLoading(
                            () async {
                              await bleDevice.disconnect();
                              _addLog("DisconnectResult",
                                  "Cleanup performed to prevent auto-reconnect");
                            },
                            onError: (error) {
                              _addLog('DisconnectError', error);
                            },
                          );
                        }
                      }
                      setState(() {
                        _autoConnect = value;
                      });
                    },
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Connect/Disconnect button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                if (isConnected) {
                  await _executeWithLoading(
                    () async {
                      await bleDevice.disconnect();
                      _addLog("DisconnectResult", true);
                    },
                    onError: (error) {
                      _addLog('DisconnectError', error);
                    },
                  );
                } else {
                  await _executeWithLoading(
                    () async {
                      await bleDevice.connect(autoConnect: _autoConnect);
                      _addLog(
                        "ConnectionResult",
                        "Connected${_autoConnect ? ' (Auto-reconnect enabled)' : ''}",
                      );
                    },
                    onError: (error) {
                      _addLog(
                        'ConnectError (${error.runtimeType})',
                        error,
                      );
                    },
                  );
                }
              },
              icon: Icon(
                isConnected
                    ? Icons.bluetooth_disabled
                    : Icons.bluetooth_connected,
                size: 20,
              ),
              label: Text(isConnected ? 'Disconnect' : 'Connect'),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    isConnected ? colorScheme.error : colorScheme.primary,
                foregroundColor:
                    isConnected ? colorScheme.onError : colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceInfo() {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 16.0,
        vertical: 2.0,
      ),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(
            dividerColor: Colors.transparent,
          ),
          child: ExpansionTile(
            initiallyExpanded: _isDeviceInfoExpanded,
            onExpansionChanged: (expanded) {
              setState(() {
                _isDeviceInfoExpanded = expanded;
              });
            },
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            childrenPadding: const EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: 16,
            ),
            leading: Icon(
              Icons.info_outline,
              color: colorScheme.primary,
              size: 24,
            ),
            title: Text(
              'Device Information',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: colorScheme.onSurface,
              ),
            ),
            subtitle: !_isDeviceInfoExpanded
                ? Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Name: ${bleDevice.name ?? "Unknown"}',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'ID: ${bleDevice.deviceId}',
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  )
                : null,
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow(
                context,
                'Device ID',
                bleDevice.deviceId,
                Icons.fingerprint,
              ),
              const SizedBox(height: 12),
              _buildInfoRow(
                context,
                'Name',
                bleDevice.name ?? "Unknown",
                Icons.label,
              ),
              // Manufacturer data
              if (bleDevice.manufacturerDataList.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(
                      Icons.memory,
                      size: 18,
                      color: colorScheme.secondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Manufacturer Data',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...bleDevice.manufacturerDataList.map(
                  (data) => Padding(
                    padding: const EdgeInsets.only(
                      bottom: 8.0,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Company ID: ',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSecondaryContainer,
                                ),
                              ),
                              Expanded(
                                child: SelectableText(
                                  data.companyIdRadix16,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                    color: colorScheme.onSecondaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (data.payloadRadix16.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Payload: ',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colorScheme.onSecondaryContainer
                                        .withValues(alpha: 0.8),
                                  ),
                                ),
                                Expanded(
                                  child: SelectableText(
                                    data.payloadRadix16,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                      color: colorScheme.onSecondaryContainer
                                          .withValues(alpha: 0.8),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              // Advertised services
              if (bleDevice.services.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(
                      Icons.list,
                      size: 18,
                      color: colorScheme.tertiary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Advertised Services',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: bleDevice.services
                      .map(
                        (service) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.tertiaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: SelectableText(
                            service,
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: colorScheme.onTertiaryContainer,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceActions() {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 16.0,
        vertical: 2.0,
      ),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(
            dividerColor: Colors.transparent,
          ),
          child: ExpansionTile(
            initiallyExpanded: _isDeviceActionsExpanded,
            onExpansionChanged: (expanded) {
              setState(() {
                _isDeviceActionsExpanded = expanded;
              });
            },
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            childrenPadding: const EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: 16,
            ),
            leading: Icon(
              Icons.devices,
              color: colorScheme.primary,
              size: 24,
            ),
            title: Text(
              'Device Actions',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: colorScheme.onSurface,
              ),
            ),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  children: [
                    ElevatedButton.icon(
                      onPressed: isConnected
                          ? () async {
                              _discoverServices();
                            }
                          : null,
                      icon: const Icon(Icons.search),
                      label: const Text('Discover Services'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        _addLog(
                          'ConnectionState',
                          await bleDevice.connectionState,
                        );
                      },
                      icon: const Icon(Icons.info_outline),
                      label: const Text('State'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colorScheme.onSurface,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: isConnected
                          ? () async {
                              try {
                                int rssi = await bleDevice.readRssi();
                                _addLog('RSSI', '$rssi dBm');
                              } catch (e) {
                                _addLog('ReadRssiError (${e.runtimeType})', e);
                              }
                            }
                          : null,
                      icon: const Icon(Icons.signal_cellular_alt),
                      label: const Text('Get RSSI'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colorScheme.onSurface,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    if (BleCapabilities.supportsRequestMtuApi)
                      ElevatedButton.icon(
                        onPressed: isConnected
                            ? () async {
                                await _executeWithLoading(
                                  () async {
                                    int mtu = await bleDevice.requestMtu(247);
                                    _addLog('MTU', mtu);
                                  },
                                  onError: (error) {
                                    _addLog('RequestMtuError', error);
                                  },
                                );
                              }
                            : null,
                        icon: const Icon(Icons.speed),
                        label: const Text('MTU'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.secondary,
                          foregroundColor: colorScheme.onSecondary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ElevatedButton.icon(
                      onPressed: BleCapabilities.supportsAllPairingKinds
                          ? () async {
                              await _executeWithLoading(
                                () async {
                                  await bleDevice.pair();
                                  _addLog("Pairing Result", true);
                                },
                                onError: (error) {
                                  _addLog('PairError', error);
                                },
                              );
                            }
                          : null,
                      icon: const Icon(Icons.link),
                      label: const Text('Pair'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.tertiary,
                        foregroundColor: colorScheme.onTertiary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await _executeWithLoading(
                          () async {
                            bool? isPaired = await bleDevice.isPaired();
                            _addLog('isPaired', isPaired);
                          },
                          onError: (error) {
                            _addLog('isPairedError', error);
                          },
                        );
                      },
                      icon: const Icon(Icons.check_circle),
                      label: const Text('Check Paired'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colorScheme.onSurface,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await _executeWithLoading(
                          () async {
                            await bleDevice.unpair();
                          },
                          onError: (error) {
                            _addLog('UnpairError', error);
                          },
                        );
                      },
                      icon: const Icon(Icons.link_off),
                      label: const Text('Unpair'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colorScheme.error,
                        side: BorderSide(
                          color: colorScheme.error,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _hasSelectedCharacteristicProperty(
    List<CharacteristicProperty> properties,
  ) {
    return properties.any(
      (property) =>
          selectedCharacteristic?.properties.contains(property) ?? false,
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 18,
          color: colorScheme.onSurface.withValues(alpha: 0.6),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              SelectableText(
                value,
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurface,
                  fontFamily: label == 'Device ID' ? 'monospace' : null,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCharacteristicSelector() {
    final colorScheme = Theme.of(context).colorScheme;
    if (selectedCharacteristic == null) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: InkWell(
          onTap: () {
            if (discoveredServices.isEmpty) {
              _discoverServices();
            } else {
              _showCharacteristicSelector();
            }
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    discoveredServices.isEmpty
                        ? "Please discover services"
                        : "Please select a characteristic to read/write",
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 16.0,
          vertical: 8.0,
        ),
        child: _buildSelectedCharacteristicCard(),
      );
    }
  }

  Widget _buildServicesList({
    Function(BleService, BleCharacteristic?)? onSelect,
  }) {
    return ServicesListWidget(
      discoveredServices: discoveredServices,
      selectedService: selectedService,
      selectedCharacteristic: selectedCharacteristic,
      favoriteServices: _favoriteServices,
      subscribedCharacteristics: _subscribedCharacteristics,
      scrollable: true,
      onTap: (service, characteristic) {
        setState(() {
          selectedService = service;
          selectedCharacteristic = characteristic;
        });
        onSelect?.call(service, characteristic);
      },
      onFavoriteToggle: (serviceUuid) {
        setState(() {
          if (_favoriteServices.contains(
            serviceUuid,
          )) {
            _favoriteServices.remove(serviceUuid);
          } else {
            _favoriteServices.add(serviceUuid);
          }
        });
        _saveFavoriteServices();
      },
    );
  }

  Widget _buildSelectedCharacteristicCard() {
    final colorScheme = Theme.of(context).colorScheme;
    if (selectedCharacteristic == null) return const SizedBox.shrink();
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: colorScheme.primaryContainer,
      child: InkWell(
        onTap: _showCharacteristicSelector,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.settings,
                    size: 16,
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Characteristic',
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurface.withValues(alpha: 0.6),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () {
                                  Clipboard.setData(ClipboardData(
                                    text: selectedCharacteristic?.uuid ?? "",
                                  ));
                                  _showSnackBar('Copied to clipboard');
                                },
                                child: Text(
                                  selectedCharacteristic!.uuid,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                    color: colorScheme.onSurface,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_drop_down,
                    size: 18,
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.apps,
                    size: 16,
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Service',
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurface.withValues(alpha: 0.6),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(
                              text: selectedService?.uuid ?? "",
                            ));
                            _showSnackBar('Copied to clipboard');
                          },
                          child: Text(
                            selectedService?.uuid ?? "Unknown",
                            style: TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.tune,
                    size: 16,
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Properties',
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurface.withValues(alpha: 0.6),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children:
                              selectedCharacteristic!.properties.map((prop) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                prop.name,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: colorScheme.onSecondaryContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultWidget({
    required bool scrollable,
  }) {
    return ResultWidget(
      results: _logs,
      scrollController: _logsScrollController,
      scrollable: scrollable,
      onClearTap: (int? index) {
        setState(() {
          if (index != null) {
            _logs.removeAt(index);
          } else {
            _logs.clear();
          }
        });
      },
    );
  }
}
