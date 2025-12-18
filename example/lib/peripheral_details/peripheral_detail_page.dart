import 'dart:async';

import 'package:convert/convert.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:universal_ble_example/data/storage_service.dart';
import 'package:universal_ble_example/peripheral_details/widgets/result_widget.dart';
import 'package:universal_ble_example/peripheral_details/widgets/services_list_widget.dart';
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
  final Set<String> _favoriteServices = {};
  bool _isLoading = false;
  bool _isDeviceInfoExpanded = false;
  final Map<String, bool> _subscribedCharacteristics = {};

  StreamSubscription? connectionStreamSubscription;
  StreamSubscription? pairingStateSubscription;
  BleService? selectedService;
  BleCharacteristic? selectedCharacteristic;
  final ScrollController _logsScrollController = ScrollController();
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
    _asyncInits();
  }

  void _asyncInits() {
    bleDevice.connectionState.then((state) {
      if (state == BleConnectionState.connected) {
        setState(() {
          isConnected = true;
        });
      }
    });
    _loadFavoriteServices();
  }

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
        debugPrint(services.toString());
        setState(() {
          discoveredServices = services;
        });
        if (kIsWeb) {
          _addLog(
            "DiscoverServices",
            '${services.length} services discovered,\n$webWarning',
          );
        }
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
    if (selectedCharacteristic == null) return;
    await _executeWithLoading(
      () async {
        await selectedCharacteristic?.unsubscribe();
        setState(() {
          _subscribedCharacteristics.remove(selectedCharacteristic?.uuid);
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

  bool _isSystemService(String uuid) {
    final normalized = uuid.toUpperCase().replaceAll('-', '');
    return normalized == '00001800' ||
        normalized == '00001801' ||
        normalized == '0000180A' ||
        normalized.startsWith('000018');
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
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void setState(VoidCallback fn) {
    if (mounted) super.setState(fn);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(
              isConnected
                  ? Icons.bluetooth_connected
                  : Icons.bluetooth_disabled,
              color: isConnected
                  ? Colors.green
                  : colorScheme.onSurface.withValues(alpha: 0.6),
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SelectableText(
                bleDevice.name ?? "Unknown Device",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
        centerTitle: false,
        elevation: 0,
        actions: [
          if (_isLoading)
            Padding(
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
          if (isConnected)
            Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle,
                    size: 16,
                    color: Colors.green.shade700,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Connected',
                    style: TextStyle(
                      color: Colors.green.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.bluetooth_disabled,
                    size: 16,
                    color: Colors.orange.shade700,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Disconnected',
                    style: TextStyle(
                      color: Colors.orange.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: ResponsiveView(
        builder: (_, DeviceType deviceType) {
          // Split layout: services on left, details on right (or stacked on mobile)
          return Row(
            children: [
              // Services list (left side on desktop, hidden on mobile - shown below)
              if (deviceType == DeviceType.desktop)
                Expanded(
                  flex: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      border: Border(
                        right: BorderSide(
                          color: colorScheme.outline.withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            border: Border(
                              bottom: BorderSide(
                                color:
                                    colorScheme.outline.withValues(alpha: 0.2),
                                width: 1,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.apps,
                                color: colorScheme.primary,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Services',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${discoveredServices.length}',
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
                        Expanded(
                          child: discoveredServices.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.apps_outlined,
                                        size: 48,
                                        color: colorScheme.onSurface
                                            .withValues(alpha: 0.3),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        'No Services Discovered',
                                        style: TextStyle(
                                          color: colorScheme.onSurface
                                              .withValues(alpha: 0.6),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : ServicesListWidget(
                                  discoveredServices: discoveredServices,
                                  selectedService: selectedService,
                                  selectedCharacteristic:
                                      selectedCharacteristic,
                                  favoriteServices: _favoriteServices,
                                  subscribedCharacteristics:
                                      _subscribedCharacteristics,
                                  scrollable: true,
                                  onTap: (service, characteristic) {
                                    setState(() {
                                      selectedService = service;
                                      selectedCharacteristic = characteristic;
                                    });
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
                                  isSystemService: _isSystemService,
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              // Main content area
              Expanded(
                flex: deviceType == DeviceType.desktop ? 3 : 1,
                child: deviceType == DeviceType.desktop
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Main content
                          Expanded(
                            flex: 2,
                            child: SingleChildScrollView(
                              child: Column(
                                children: [
                                  // Device info with manufacturer data and advertised services
                                  Padding(
                                    padding: const EdgeInsets.all(16.0),
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
                                          initiallyExpanded:
                                              _isDeviceInfoExpanded,
                                          onExpansionChanged: (expanded) {
                                            setState(() {
                                              _isDeviceInfoExpanded = expanded;
                                            });
                                          },
                                          tilePadding:
                                              const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 8,
                                          ),
                                          childrenPadding:
                                              const EdgeInsets.only(
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
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 4),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        'Name: ${bleDevice.name ?? "Unknown"}',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: colorScheme
                                                              .onSurface
                                                              .withValues(
                                                                  alpha: 0.7),
                                                        ),
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        'ID: ${bleDevice.deviceId}',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontFamily:
                                                              'monospace',
                                                          color: colorScheme
                                                              .onSurface
                                                              .withValues(
                                                                  alpha: 0.6),
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ],
                                                  ),
                                                )
                                              : null,
                                          expandedCrossAxisAlignment:
                                              CrossAxisAlignment.start,
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
                                            if (bleDevice.manufacturerDataList
                                                .isNotEmpty) ...[
                                              const SizedBox(height: 16),
                                              Row(
                                                children: [
                                                  Icon(
                                                    Icons.memory,
                                                    size: 18,
                                                    color:
                                                        colorScheme.secondary,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    'Manufacturer Data',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 14,
                                                      color:
                                                          colorScheme.onSurface,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              ...bleDevice.manufacturerDataList
                                                  .map(
                                                (data) => Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                    bottom: 8.0,
                                                  ),
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.all(
                                                            12),
                                                    decoration: BoxDecoration(
                                                      color: colorScheme
                                                          .secondaryContainer,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                    ),
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Row(
                                                          children: [
                                                            Text(
                                                              'Company ID: ',
                                                              style: TextStyle(
                                                                fontSize: 12,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color: colorScheme
                                                                    .onSecondaryContainer,
                                                              ),
                                                            ),
                                                            Expanded(
                                                              child:
                                                                  SelectableText(
                                                                data.companyIdRadix16,
                                                                style:
                                                                    TextStyle(
                                                                  fontSize: 12,
                                                                  fontFamily:
                                                                      'monospace',
                                                                  color: colorScheme
                                                                      .onSecondaryContainer,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        if (data.payloadHex
                                                            .isNotEmpty) ...[
                                                          const SizedBox(
                                                              height: 4),
                                                          Row(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              Text(
                                                                'Payload: ',
                                                                style:
                                                                    TextStyle(
                                                                  fontSize: 11,
                                                                  color: colorScheme
                                                                      .onSecondaryContainer
                                                                      .withValues(
                                                                          alpha:
                                                                              0.8),
                                                                ),
                                                              ),
                                                              Expanded(
                                                                child:
                                                                    SelectableText(
                                                                  data.payloadHex,
                                                                  style:
                                                                      TextStyle(
                                                                    fontSize:
                                                                        11,
                                                                    fontFamily:
                                                                        'monospace',
                                                                    color: colorScheme
                                                                        .onSecondaryContainer
                                                                        .withValues(
                                                                            alpha:
                                                                                0.8),
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
                                            if (bleDevice
                                                .services.isNotEmpty) ...[
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
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 14,
                                                      color:
                                                          colorScheme.onSurface,
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
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 10,
                                                          vertical: 6,
                                                        ),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: colorScheme
                                                              .tertiaryContainer,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(8),
                                                        ),
                                                        child: SelectableText(
                                                          service,
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            fontFamily:
                                                                'monospace',
                                                            color: colorScheme
                                                                .onTertiaryContainer,
                                                            fontWeight:
                                                                FontWeight.w500,
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
                                  ),
                                  // Connect/Disconnect buttons
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16.0,
                                      vertical: 8.0,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            onPressed: !isConnected
                                                ? () async {
                                                    await _executeWithLoading(
                                                      () async {
                                                        await bleDevice
                                                            .connect();
                                                        _addLog(
                                                            "ConnectionResult",
                                                            true);
                                                      },
                                                      onError: (error) {
                                                        _addLog(
                                                          'ConnectError (${error.runtimeType})',
                                                          error,
                                                        );
                                                      },
                                                    );
                                                  }
                                                : null,
                                            icon: Icon(
                                              Icons.bluetooth_connected,
                                              size: 20,
                                            ),
                                            label: const Text('Connect'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  colorScheme.primary,
                                              foregroundColor:
                                                  colorScheme.onPrimary,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                vertical: 16,
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              elevation: 2,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            onPressed: isConnected
                                                ? () {
                                                    bleDevice.disconnect();
                                                  }
                                                : null,
                                            icon: Icon(
                                              Icons.bluetooth_disabled,
                                              size: 20,
                                            ),
                                            label: const Text('Disconnect'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  colorScheme.error,
                                              foregroundColor:
                                                  colorScheme.onError,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                vertical: 16,
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              elevation: 2,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (selectedCharacteristic == null)
                                    Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: colorScheme
                                              .surfaceContainerHighest,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.info_outline,
                                              color: colorScheme.onSurface
                                                  .withValues(alpha: 0.6),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                discoveredServices.isEmpty
                                                    ? "Please discover services"
                                                    : "Please select a characteristic to read/write",
                                                style: TextStyle(
                                                  fontStyle: FontStyle.italic,
                                                  color: colorScheme.onSurface
                                                      .withValues(alpha: 0.7),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                  else
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16.0,
                                        vertical: 8.0,
                                      ),
                                      child: _buildSelectedCharacteristicCard(
                                          context),
                                    ),
                                  Padding(
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
                                        child: Form(
                                          key: valueFormKey,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Icon(
                                                    Icons.edit,
                                                    color: colorScheme.primary,
                                                    size: 20,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    'Read/Write',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 16,
                                                      color:
                                                          colorScheme.onSurface,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 16),
                                              TextFormField(
                                                controller: binaryCode,
                                                enabled: isConnected &&
                                                    _hasSelectedCharacteristicProperty([
                                                      CharacteristicProperty
                                                          .write,
                                                      CharacteristicProperty
                                                          .writeWithoutResponse,
                                                    ]),
                                                validator: (value) {
                                                  if (value == null ||
                                                      value.isEmpty) {
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
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12),
                                                  ),
                                                  filled: true,
                                                  fillColor: colorScheme
                                                      .surfaceContainerHighest,
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
                                                                CharacteristicProperty
                                                                    .write,
                                                                CharacteristicProperty
                                                                    .writeWithoutResponse,
                                                              ])
                                                          ? _writeValue
                                                          : null,
                                                      icon: const Icon(
                                                          Icons.send),
                                                      label:
                                                          const Text('Write'),
                                                      style: ElevatedButton
                                                          .styleFrom(
                                                        backgroundColor:
                                                            colorScheme.primary,
                                                        foregroundColor:
                                                            colorScheme
                                                                .onPrimary,
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          vertical: 16,
                                                        ),
                                                        shape:
                                                            RoundedRectangleBorder(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(12),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: ElevatedButton.icon(
                                                      onPressed: isConnected &&
                                                              _hasSelectedCharacteristicProperty([
                                                                CharacteristicProperty
                                                                    .read,
                                                              ])
                                                          ? _readValue
                                                          : null,
                                                      icon: const Icon(
                                                          Icons.download),
                                                      label: const Text('Read'),
                                                      style: ElevatedButton
                                                          .styleFrom(
                                                        backgroundColor:
                                                            colorScheme
                                                                .secondary,
                                                        foregroundColor:
                                                            colorScheme
                                                                .onSecondary,
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          vertical: 16,
                                                        ),
                                                        shape:
                                                            RoundedRectangleBorder(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(12),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                                  // Characteristic Actions
                                  Padding(
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
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
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
                                                    color:
                                                        colorScheme.onSurface,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 16),
                                            Wrap(
                                              spacing: 12,
                                              runSpacing: 12,
                                              children: [
                                                ElevatedButton.icon(
                                                  onPressed: isConnected &&
                                                          discoveredServices
                                                              .isNotEmpty &&
                                                          selectedCharacteristic !=
                                                              null &&
                                                          _hasSelectedCharacteristicProperty([
                                                            CharacteristicProperty
                                                                .notify,
                                                            CharacteristicProperty
                                                                .indicate,
                                                          ])
                                                      ? _subscribeChar
                                                      : null,
                                                  icon: const Icon(Icons
                                                      .notifications_active),
                                                  label:
                                                      const Text('Subscribe'),
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        Colors.green,
                                                    foregroundColor:
                                                        Colors.white,
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 16,
                                                      vertical: 12,
                                                    ),
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                    ),
                                                  ),
                                                ),
                                                OutlinedButton.icon(
                                                  onPressed: isConnected &&
                                                          discoveredServices
                                                              .isNotEmpty &&
                                                          selectedCharacteristic !=
                                                              null &&
                                                          _hasSelectedCharacteristicProperty([
                                                            CharacteristicProperty
                                                                .notify,
                                                            CharacteristicProperty
                                                                .indicate,
                                                          ])
                                                      ? _unsubscribeChar
                                                      : null,
                                                  icon: const Icon(
                                                      Icons.notifications_off),
                                                  label:
                                                      const Text('Unsubscribe'),
                                                  style:
                                                      OutlinedButton.styleFrom(
                                                    foregroundColor:
                                                        colorScheme.onSurface,
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 16,
                                                      vertical: 12,
                                                    ),
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                    ),
                                                  ),
                                                ),
                                                ElevatedButton.icon(
                                                  onPressed: isConnected &&
                                                          discoveredServices
                                                              .isNotEmpty
                                                      ? _subscribeToAllCharacteristics
                                                      : null,
                                                  icon: const Icon(Icons
                                                      .notifications_active),
                                                  label: const Text(
                                                      'Subscribe All'),
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        Colors.green,
                                                    foregroundColor:
                                                        Colors.white,
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 16,
                                                      vertical: 12,
                                                    ),
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Device Actions
                                  Padding(
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
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.devices,
                                                  color: colorScheme.primary,
                                                  size: 20,
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  'Device Actions',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                    color:
                                                        colorScheme.onSurface,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 16),
                                            Wrap(
                                              spacing: 12,
                                              runSpacing: 12,
                                              children: [
                                                ElevatedButton.icon(
                                                  onPressed: isConnected
                                                      ? () async {
                                                          _discoverServices();
                                                        }
                                                      : null,
                                                  icon:
                                                      const Icon(Icons.search),
                                                  label: const Text(
                                                      'Discover Services'),
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        colorScheme.primary,
                                                    foregroundColor:
                                                        colorScheme.onPrimary,
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 16,
                                                      vertical: 12,
                                                    ),
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                    ),
                                                  ),
                                                ),
                                                if (discoveredServices
                                                    .isNotEmpty)
                                                  OutlinedButton.icon(
                                                    onPressed: () async {
                                                      final servicesText =
                                                          discoveredServices
                                                              .map(
                                                                  (s) => s.uuid)
                                                              .join('\n');
                                                      await Clipboard.setData(
                                                        ClipboardData(
                                                            text: servicesText),
                                                      );
                                                      ScaffoldMessenger.of(
                                                              context)
                                                          .showSnackBar(
                                                        const SnackBar(
                                                          content: Text(
                                                              'All services copied to clipboard'),
                                                        ),
                                                      );
                                                    },
                                                    icon:
                                                        const Icon(Icons.copy),
                                                    label: const Text(
                                                        'Copy All Services'),
                                                    style: OutlinedButton
                                                        .styleFrom(
                                                      foregroundColor:
                                                          colorScheme.onSurface,
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 16,
                                                        vertical: 12,
                                                      ),
                                                      shape:
                                                          RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(8),
                                                      ),
                                                    ),
                                                  ),
                                                OutlinedButton.icon(
                                                  onPressed: () async {
                                                    _addLog(
                                                      'ConnectionState',
                                                      await bleDevice
                                                          .connectionState,
                                                    );
                                                  },
                                                  icon: const Icon(
                                                      Icons.info_outline),
                                                  label: const Text(
                                                      'Connection State'),
                                                  style:
                                                      OutlinedButton.styleFrom(
                                                    foregroundColor:
                                                        colorScheme.onSurface,
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 16,
                                                      vertical: 12,
                                                    ),
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                    ),
                                                  ),
                                                ),
                                                if (BleCapabilities
                                                    .supportsRequestMtuApi)
                                                  ElevatedButton.icon(
                                                    onPressed: isConnected
                                                        ? () async {
                                                            await _executeWithLoading(
                                                              () async {
                                                                int mtu =
                                                                    await bleDevice
                                                                        .requestMtu(
                                                                            247);
                                                                _addLog(
                                                                    'MTU', mtu);
                                                              },
                                                              onError: (error) {
                                                                _addLog(
                                                                    'RequestMtuError',
                                                                    error);
                                                              },
                                                            );
                                                          }
                                                        : null,
                                                    icon:
                                                        const Icon(Icons.speed),
                                                    label: const Text(
                                                        'Request MTU'),
                                                    style: ElevatedButton
                                                        .styleFrom(
                                                      backgroundColor:
                                                          colorScheme.secondary,
                                                      foregroundColor:
                                                          colorScheme
                                                              .onSecondary,
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 16,
                                                        vertical: 12,
                                                      ),
                                                      shape:
                                                          RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(8),
                                                      ),
                                                    ),
                                                  ),
                                                ElevatedButton.icon(
                                                  onPressed: BleCapabilities
                                                          .supportsAllPairingKinds
                                                      ? () async {
                                                          await _executeWithLoading(
                                                            () async {
                                                              await bleDevice
                                                                  .pair();
                                                              _addLog(
                                                                  "Pairing Result",
                                                                  true);
                                                            },
                                                            onError: (error) {
                                                              _addLog(
                                                                  'PairError',
                                                                  error);
                                                            },
                                                          );
                                                        }
                                                      : null,
                                                  icon: const Icon(Icons.link),
                                                  label: const Text('Pair'),
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        colorScheme.tertiary,
                                                    foregroundColor:
                                                        colorScheme.onTertiary,
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 16,
                                                      vertical: 12,
                                                    ),
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                    ),
                                                  ),
                                                ),
                                                OutlinedButton.icon(
                                                  onPressed: () async {
                                                    await _executeWithLoading(
                                                      () async {
                                                        bool? isPaired =
                                                            await bleDevice
                                                                .isPaired();
                                                        _addLog('isPaired',
                                                            isPaired);
                                                      },
                                                      onError: (error) {
                                                        _addLog('isPairedError',
                                                            error);
                                                      },
                                                    );
                                                  },
                                                  icon: const Icon(
                                                      Icons.check_circle),
                                                  label: const Text(
                                                      'Check Paired'),
                                                  style:
                                                      OutlinedButton.styleFrom(
                                                    foregroundColor:
                                                        colorScheme.onSurface,
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 16,
                                                      vertical: 12,
                                                    ),
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                    ),
                                                  ),
                                                ),
                                                OutlinedButton.icon(
                                                  onPressed: () async {
                                                    await bleDevice.unpair();
                                                  },
                                                  icon: const Icon(
                                                      Icons.link_off),
                                                  label: const Text('Unpair'),
                                                  style:
                                                      OutlinedButton.styleFrom(
                                                    foregroundColor:
                                                        colorScheme.error,
                                                    side: BorderSide(
                                                      color: colorScheme.error,
                                                    ),
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 16,
                                                      vertical: 12,
                                                    ),
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Services list (mobile/tablet)
                                  if (deviceType != DeviceType.desktop)
                                    ServicesListWidget(
                                      discoveredServices: discoveredServices,
                                      selectedService: selectedService,
                                      selectedCharacteristic:
                                          selectedCharacteristic,
                                      favoriteServices: _favoriteServices,
                                      subscribedCharacteristics:
                                          _subscribedCharacteristics,
                                      onTap: (service, characteristic) {
                                        setState(() {
                                          selectedService = service;
                                          selectedCharacteristic =
                                              characteristic;
                                        });
                                      },
                                      onFavoriteToggle: (serviceUuid) {
                                        setState(() {
                                          if (_favoriteServices.contains(
                                            serviceUuid,
                                          )) {
                                            _favoriteServices
                                                .remove(serviceUuid);
                                          } else {
                                            _favoriteServices.add(serviceUuid);
                                          }
                                        });
                                        _saveFavoriteServices();
                                      },
                                      isSystemService: _isSystemService,
                                    ),
                                  const Divider(),
                                  if (deviceType != DeviceType.desktop)
                                    ResultWidget(
                                      results: _logs,
                                      scrollController: _logsScrollController,
                                      onClearTap: (int? index) {
                                        setState(() {
                                          if (index != null) {
                                            _logs.removeAt(index);
                                          } else {
                                            _logs.clear();
                                          }
                                        });
                                      },
                                    ),
                                  if (deviceType != DeviceType.desktop)
                                    const SizedBox(height: 20),
                                ],
                              ),
                            ),
                          ),
                          // Logs on right side for desktop
                          if (deviceType == DeviceType.desktop)
                            Expanded(
                              flex: 2,
                              // width: 400,
                              // margin: const EdgeInsets.only(left: 16),
                              // decoration: BoxDecoration(
                              //   color: colorScheme.surfaceContainerHighest,
                              //   border: Border(
                              //     left: BorderSide(
                              //       color: colorScheme.outline
                              //           .withValues(alpha: 0.2),
                              //       width: 1,
                              //     ),
                              //   ),
                              // ),

                              child: ResultWidget(
                                scrollController: _logsScrollController,
                                results: _logs,
                                scrollable: true,
                                onClearTap: (int? index) {
                                  setState(() {
                                    if (index != null) {
                                      _logs.removeAt(index);
                                    } else {
                                      _logs.clear();
                                    }
                                  });
                                },
                              ),
                            ),
                        ],
                      )
                    : Column(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                children: [
                                  // Device info with manufacturer data and advertised services
                                  Padding(
                                    padding: const EdgeInsets.all(16.0),
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
                                          initiallyExpanded:
                                              _isDeviceInfoExpanded,
                                          onExpansionChanged: (expanded) {
                                            setState(() {
                                              _isDeviceInfoExpanded = expanded;
                                            });
                                          },
                                          tilePadding:
                                              const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 8,
                                          ),
                                          childrenPadding:
                                              const EdgeInsets.only(
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
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 4),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        'Name: ${bleDevice.name ?? "Unknown"}',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: colorScheme
                                                              .onSurface
                                                              .withValues(
                                                                  alpha: 0.7),
                                                        ),
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        'ID: ${bleDevice.deviceId}',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontFamily:
                                                              'monospace',
                                                          color: colorScheme
                                                              .onSurface
                                                              .withValues(
                                                                  alpha: 0.6),
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ],
                                                  ),
                                                )
                                              : null,
                                          expandedCrossAxisAlignment:
                                              CrossAxisAlignment.start,
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
                                            if (bleDevice.manufacturerDataList
                                                .isNotEmpty) ...[
                                              const SizedBox(height: 16),
                                              Row(
                                                children: [
                                                  Icon(
                                                    Icons.memory,
                                                    size: 18,
                                                    color:
                                                        colorScheme.secondary,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    'Manufacturer Data',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 14,
                                                      color:
                                                          colorScheme.onSurface,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              ...bleDevice.manufacturerDataList
                                                  .map(
                                                (data) => Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                    bottom: 8.0,
                                                  ),
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.all(
                                                            12),
                                                    decoration: BoxDecoration(
                                                      color: colorScheme
                                                          .secondaryContainer,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                    ),
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Row(
                                                          children: [
                                                            Text(
                                                              'Company ID: ',
                                                              style: TextStyle(
                                                                fontSize: 12,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color: colorScheme
                                                                    .onSecondaryContainer,
                                                              ),
                                                            ),
                                                            Expanded(
                                                              child:
                                                                  SelectableText(
                                                                data.companyIdRadix16,
                                                                style:
                                                                    TextStyle(
                                                                  fontSize: 12,
                                                                  fontFamily:
                                                                      'monospace',
                                                                  color: colorScheme
                                                                      .onSecondaryContainer,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        if (data.payloadHex
                                                            .isNotEmpty) ...[
                                                          const SizedBox(
                                                              height: 4),
                                                          Row(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              Text(
                                                                'Payload: ',
                                                                style:
                                                                    TextStyle(
                                                                  fontSize: 11,
                                                                  color: colorScheme
                                                                      .onSecondaryContainer
                                                                      .withValues(
                                                                          alpha:
                                                                              0.8),
                                                                ),
                                                              ),
                                                              Expanded(
                                                                child:
                                                                    SelectableText(
                                                                  data.payloadHex,
                                                                  style:
                                                                      TextStyle(
                                                                    fontSize:
                                                                        11,
                                                                    fontFamily:
                                                                        'monospace',
                                                                    color: colorScheme
                                                                        .onSecondaryContainer
                                                                        .withValues(
                                                                            alpha:
                                                                                0.8),
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
                                            if (bleDevice
                                                .services.isNotEmpty) ...[
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
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 14,
                                                      color:
                                                          colorScheme.onSurface,
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
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 10,
                                                          vertical: 6,
                                                        ),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: colorScheme
                                                              .tertiaryContainer,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(8),
                                                        ),
                                                        child: SelectableText(
                                                          service,
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            fontFamily:
                                                                'monospace',
                                                            color: colorScheme
                                                                .onTertiaryContainer,
                                                            fontWeight:
                                                                FontWeight.w500,
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
                                  ),
                                  // Connect/Disconnect buttons
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16.0,
                                      vertical: 8.0,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            onPressed: !isConnected
                                                ? () async {
                                                    await _executeWithLoading(
                                                      () async {
                                                        await bleDevice
                                                            .connect();
                                                        _addLog(
                                                            "ConnectionResult",
                                                            true);
                                                      },
                                                      onError: (error) {
                                                        _addLog(
                                                          'ConnectError (${error.runtimeType})',
                                                          error,
                                                        );
                                                      },
                                                    );
                                                  }
                                                : null,
                                            icon: Icon(
                                              Icons.bluetooth_connected,
                                              size: 20,
                                            ),
                                            label: const Text('Connect'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  colorScheme.primary,
                                              foregroundColor:
                                                  colorScheme.onPrimary,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                vertical: 16,
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              elevation: 2,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            onPressed: isConnected
                                                ? () {
                                                    bleDevice.disconnect();
                                                  }
                                                : null,
                                            icon: Icon(
                                              Icons.bluetooth_disabled,
                                              size: 20,
                                            ),
                                            label: const Text('Disconnect'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  colorScheme.error,
                                              foregroundColor:
                                                  colorScheme.onError,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                vertical: 16,
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              elevation: 2,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (selectedCharacteristic == null)
                                    Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: colorScheme
                                              .surfaceContainerHighest,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.info_outline,
                                              color: colorScheme.onSurface
                                                  .withValues(alpha: 0.6),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                discoveredServices.isEmpty
                                                    ? "Please discover services"
                                                    : "Please select a characteristic to read/write",
                                                style: TextStyle(
                                                  fontStyle: FontStyle.italic,
                                                  color: colorScheme.onSurface
                                                      .withValues(alpha: 0.7),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                  else
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16.0,
                                        vertical: 8.0,
                                      ),
                                      child: _buildSelectedCharacteristicCard(
                                          context),
                                    ),
                                  Padding(
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
                                        child: Form(
                                          key: valueFormKey,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Icon(
                                                    Icons.edit,
                                                    color: colorScheme.primary,
                                                    size: 20,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    'Read/Write',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 16,
                                                      color:
                                                          colorScheme.onSurface,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 16),
                                              TextFormField(
                                                controller: binaryCode,
                                                enabled: isConnected &&
                                                    _hasSelectedCharacteristicProperty([
                                                      CharacteristicProperty
                                                          .write,
                                                      CharacteristicProperty
                                                          .writeWithoutResponse,
                                                    ]),
                                                validator: (value) {
                                                  if (value == null ||
                                                      value.isEmpty) {
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
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12),
                                                  ),
                                                  filled: true,
                                                  fillColor: colorScheme
                                                      .surfaceContainerHighest,
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
                                                                CharacteristicProperty
                                                                    .write,
                                                                CharacteristicProperty
                                                                    .writeWithoutResponse,
                                                              ])
                                                          ? _writeValue
                                                          : null,
                                                      icon: const Icon(
                                                          Icons.send),
                                                      label:
                                                          const Text('Write'),
                                                      style: ElevatedButton
                                                          .styleFrom(
                                                        backgroundColor:
                                                            colorScheme.primary,
                                                        foregroundColor:
                                                            colorScheme
                                                                .onPrimary,
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          vertical: 16,
                                                        ),
                                                        shape:
                                                            RoundedRectangleBorder(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(12),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: ElevatedButton.icon(
                                                      onPressed: isConnected &&
                                                              _hasSelectedCharacteristicProperty([
                                                                CharacteristicProperty
                                                                    .read,
                                                              ])
                                                          ? _readValue
                                                          : null,
                                                      icon: const Icon(
                                                          Icons.download),
                                                      label: const Text('Read'),
                                                      style: ElevatedButton
                                                          .styleFrom(
                                                        backgroundColor:
                                                            colorScheme
                                                                .secondary,
                                                        foregroundColor:
                                                            colorScheme
                                                                .onSecondary,
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          vertical: 16,
                                                        ),
                                                        shape:
                                                            RoundedRectangleBorder(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(12),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Characteristic Actions
                                  Padding(
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
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
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
                                                    color:
                                                        colorScheme.onSurface,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 16),
                                            Wrap(
                                              spacing: 12,
                                              runSpacing: 12,
                                              children: [
                                                ElevatedButton.icon(
                                                  onPressed: isConnected &&
                                                          discoveredServices
                                                              .isNotEmpty &&
                                                          selectedCharacteristic !=
                                                              null &&
                                                          _hasSelectedCharacteristicProperty([
                                                            CharacteristicProperty
                                                                .notify,
                                                            CharacteristicProperty
                                                                .indicate,
                                                          ])
                                                      ? _subscribeChar
                                                      : null,
                                                  icon: const Icon(Icons
                                                      .notifications_active),
                                                  label:
                                                      const Text('Subscribe'),
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        Colors.green,
                                                    foregroundColor:
                                                        Colors.white,
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 16,
                                                      vertical: 12,
                                                    ),
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                    ),
                                                  ),
                                                ),
                                                OutlinedButton.icon(
                                                  onPressed: isConnected &&
                                                          discoveredServices
                                                              .isNotEmpty &&
                                                          selectedCharacteristic !=
                                                              null &&
                                                          _hasSelectedCharacteristicProperty([
                                                            CharacteristicProperty
                                                                .notify,
                                                            CharacteristicProperty
                                                                .indicate,
                                                          ])
                                                      ? _unsubscribeChar
                                                      : null,
                                                  icon: const Icon(
                                                      Icons.notifications_off),
                                                  label:
                                                      const Text('Unsubscribe'),
                                                  style:
                                                      OutlinedButton.styleFrom(
                                                    foregroundColor:
                                                        colorScheme.onSurface,
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 16,
                                                      vertical: 12,
                                                    ),
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                    ),
                                                  ),
                                                ),
                                                ElevatedButton.icon(
                                                  onPressed: isConnected &&
                                                          discoveredServices
                                                              .isNotEmpty
                                                      ? _subscribeToAllCharacteristics
                                                      : null,
                                                  icon: const Icon(Icons
                                                      .notifications_active),
                                                  label: const Text(
                                                      'Subscribe All'),
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        Colors.green,
                                                    foregroundColor:
                                                        Colors.white,
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 16,
                                                      vertical: 12,
                                                    ),
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Device Actions
                                  Padding(
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
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.devices,
                                                  color: colorScheme.primary,
                                                  size: 20,
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  'Device Actions',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                    color:
                                                        colorScheme.onSurface,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 16),
                                            Wrap(
                                              spacing: 12,
                                              runSpacing: 12,
                                              children: [
                                                ElevatedButton.icon(
                                                  onPressed: isConnected
                                                      ? () async {
                                                          _discoverServices();
                                                        }
                                                      : null,
                                                  icon:
                                                      const Icon(Icons.search),
                                                  label: const Text(
                                                      'Discover Services'),
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        colorScheme.primary,
                                                    foregroundColor:
                                                        colorScheme.onPrimary,
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 16,
                                                      vertical: 12,
                                                    ),
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                    ),
                                                  ),
                                                ),
                                                if (discoveredServices
                                                    .isNotEmpty)
                                                  OutlinedButton.icon(
                                                    onPressed: () async {
                                                      final servicesText =
                                                          discoveredServices
                                                              .map(
                                                                  (s) => s.uuid)
                                                              .join('\n');
                                                      await Clipboard.setData(
                                                        ClipboardData(
                                                            text: servicesText),
                                                      );
                                                      ScaffoldMessenger.of(
                                                              context)
                                                          .showSnackBar(
                                                        const SnackBar(
                                                          content: Text(
                                                              'All services copied to clipboard'),
                                                        ),
                                                      );
                                                    },
                                                    icon:
                                                        const Icon(Icons.copy),
                                                    label: const Text(
                                                        'Copy All Services'),
                                                    style: OutlinedButton
                                                        .styleFrom(
                                                      foregroundColor:
                                                          colorScheme.onSurface,
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 16,
                                                        vertical: 12,
                                                      ),
                                                      shape:
                                                          RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(8),
                                                      ),
                                                    ),
                                                  ),
                                                OutlinedButton.icon(
                                                  onPressed: () async {
                                                    _addLog(
                                                      'ConnectionState',
                                                      await bleDevice
                                                          .connectionState,
                                                    );
                                                  },
                                                  icon: const Icon(
                                                      Icons.info_outline),
                                                  label: const Text(
                                                      'Connection State'),
                                                  style:
                                                      OutlinedButton.styleFrom(
                                                    foregroundColor:
                                                        colorScheme.onSurface,
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 16,
                                                      vertical: 12,
                                                    ),
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                    ),
                                                  ),
                                                ),
                                                if (BleCapabilities
                                                    .supportsRequestMtuApi)
                                                  ElevatedButton.icon(
                                                    onPressed: isConnected
                                                        ? () async {
                                                            await _executeWithLoading(
                                                              () async {
                                                                int mtu =
                                                                    await bleDevice
                                                                        .requestMtu(
                                                                            247);
                                                                _addLog(
                                                                    'MTU', mtu);
                                                              },
                                                              onError: (error) {
                                                                _addLog(
                                                                    'RequestMtuError',
                                                                    error);
                                                              },
                                                            );
                                                          }
                                                        : null,
                                                    icon:
                                                        const Icon(Icons.speed),
                                                    label: const Text(
                                                        'Request MTU'),
                                                    style: ElevatedButton
                                                        .styleFrom(
                                                      backgroundColor:
                                                          colorScheme.secondary,
                                                      foregroundColor:
                                                          colorScheme
                                                              .onSecondary,
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 16,
                                                        vertical: 12,
                                                      ),
                                                      shape:
                                                          RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(8),
                                                      ),
                                                    ),
                                                  ),
                                                ElevatedButton.icon(
                                                  onPressed: BleCapabilities
                                                          .supportsAllPairingKinds
                                                      ? () async {
                                                          await _executeWithLoading(
                                                            () async {
                                                              await bleDevice
                                                                  .pair();
                                                              _addLog(
                                                                  "Pairing Result",
                                                                  true);
                                                            },
                                                            onError: (error) {
                                                              _addLog(
                                                                  'PairError',
                                                                  error);
                                                            },
                                                          );
                                                        }
                                                      : null,
                                                  icon: const Icon(Icons.link),
                                                  label: const Text('Pair'),
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        colorScheme.tertiary,
                                                    foregroundColor:
                                                        colorScheme.onTertiary,
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 16,
                                                      vertical: 12,
                                                    ),
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                    ),
                                                  ),
                                                ),
                                                OutlinedButton.icon(
                                                  onPressed: () async {
                                                    await _executeWithLoading(
                                                      () async {
                                                        bool? isPaired =
                                                            await bleDevice
                                                                .isPaired();
                                                        _addLog('isPaired',
                                                            isPaired);
                                                      },
                                                      onError: (error) {
                                                        _addLog('isPairedError',
                                                            error);
                                                      },
                                                    );
                                                  },
                                                  icon: const Icon(
                                                      Icons.check_circle),
                                                  label: const Text(
                                                      'Check Paired'),
                                                  style:
                                                      OutlinedButton.styleFrom(
                                                    foregroundColor:
                                                        colorScheme.onSurface,
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 16,
                                                      vertical: 12,
                                                    ),
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                    ),
                                                  ),
                                                ),
                                                OutlinedButton.icon(
                                                  onPressed: () async {
                                                    await bleDevice.unpair();
                                                  },
                                                  icon: const Icon(
                                                      Icons.link_off),
                                                  label: const Text('Unpair'),
                                                  style:
                                                      OutlinedButton.styleFrom(
                                                    foregroundColor:
                                                        colorScheme.error,
                                                    side: BorderSide(
                                                      color: colorScheme.error,
                                                    ),
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 16,
                                                      vertical: 12,
                                                    ),
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),

                                  // Services list (mobile/tablet)
                                  ServicesListWidget(
                                    discoveredServices: discoveredServices,
                                    selectedService: selectedService,
                                    selectedCharacteristic:
                                        selectedCharacteristic,
                                    favoriteServices: _favoriteServices,
                                    subscribedCharacteristics:
                                        _subscribedCharacteristics,
                                    onTap: (service, characteristic) {
                                      setState(() {
                                        selectedService = service;
                                        selectedCharacteristic = characteristic;
                                      });
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
                                    isSystemService: _isSystemService,
                                  ),
                                  const Divider(),
                                  ResultWidget(
                                    results: _logs,
                                    scrollController: _logsScrollController,
                                    onClearTap: (int? index) {
                                      setState(() {
                                        if (index != null) {
                                          _logs.removeAt(index);
                                        } else {
                                          _logs.clear();
                                        }
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 20),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          );
        },
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

  void _showCharacteristicSelector() {
    if (discoveredServices.isEmpty) return;
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.select_all,
                    color: colorScheme.primary,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "Select Characteristic",
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: discoveredServices.length,
                  itemBuilder: (context, serviceIndex) {
                    final service = discoveredServices[serviceIndex];
                    return ExpansionTile(
                      title: Text(
                        service.uuid,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                      ),
                      children: service.characteristics.map((char) {
                        final isSelected =
                            selectedCharacteristic?.uuid == char.uuid &&
                                selectedService?.uuid == service.uuid;
                        return ListTile(
                          selected: isSelected,
                          leading: Icon(
                            isSelected
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            color: isSelected ? colorScheme.primary : null,
                          ),
                          title: Text(
                            char.uuid,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                          subtitle: Wrap(
                            spacing: 4,
                            children: char.properties.take(3).map((prop) {
                              return Chip(
                                label: Text(
                                  prop.name,
                                  style: const TextStyle(fontSize: 9),
                                ),
                                padding: EdgeInsets.zero,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              );
                            }).toList(),
                          ),
                          onTap: () {
                            setState(() {
                              selectedService = service;
                              selectedCharacteristic = char;
                            });
                            Navigator.pop(context);
                          },
                        );
                      }).toList(),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSelectedCharacteristicCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (selectedCharacteristic == null) return const SizedBox.shrink();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: colorScheme.primaryContainer.withValues(alpha: 0.3),
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
                              child: SelectableText(
                                selectedCharacteristic!.uuid,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                  color: colorScheme.onSurface,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.arrow_drop_down,
                              size: 18,
                              color:
                                  colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ],
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
                        SelectableText(
                          selectedService?.uuid ?? "Unknown",
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w500,
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
}
