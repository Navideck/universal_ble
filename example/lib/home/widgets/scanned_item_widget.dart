import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:universal_ble_example/data/company_identifier_service.dart';
import 'package:universal_ble_example/data/storage_service.dart';
import 'package:universal_ble_example/home/widgets/rssi_signal_indicator.dart';
import 'package:universal_ble_example/widgets/company_info_widget.dart';

class ScannedItemWidget extends StatefulWidget {
  final BleDevice bleDevice;
  final VoidCallback? onTap;
  final bool isExpanded;
  final Function(bool) onExpand;
  final VoidCallback? onMonitorChanged;

  const ScannedItemWidget({
    super.key,
    required this.bleDevice,
    this.onTap,
    required this.isExpanded,
    required this.onExpand,
    this.onMonitorChanged,
  });

  @override
  State<ScannedItemWidget> createState() => _ScannedItemWidgetState();
}

class _ScannedItemWidgetState extends State<ScannedItemWidget> {
  bool get _supportsBackgroundMonitor => !kIsWeb && Platform.isAndroid;
  bool _isMonitored = false;

  @override
  void initState() {
    super.initState();
    if (_supportsBackgroundMonitor) {
      _isMonitored =
          StorageService.instance.isDeviceMonitored(widget.bleDevice.deviceId);
    }
  }

  @override
  void didUpdateWidget(ScannedItemWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_supportsBackgroundMonitor &&
        oldWidget.bleDevice.deviceId != widget.bleDevice.deviceId) {
      _isMonitored =
          StorageService.instance.isDeviceMonitored(widget.bleDevice.deviceId);
    }
  }

  Future<void> _toggleMonitor() async {
    final deviceId = widget.bleDevice.deviceId;
    if (_isMonitored) {
      await StorageService.instance.removeMonitoredDevice(deviceId);
      setState(() => _isMonitored = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Device removed from background monitor'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } else {
      await StorageService.instance.addMonitoredDevice(deviceId);
      setState(() => _isMonitored = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Device added to background monitor'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
    widget.onMonitorChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    String? name = widget.bleDevice.name;
    List<ManufacturerData> rawManufacturerData =
        widget.bleDevice.manufacturerDataList;
    if (name == null || name.isEmpty) name = 'Unknown Device';

    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: _isMonitored
            ? BorderSide(color: colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: _supportsBackgroundMonitor ? _toggleMonitor : null,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Signal indicator
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:
                          colorScheme.primaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child:
                        RssiSignalIndicator(rssi: widget.bleDevice.rssi ?? 0),
                  ),
                  const SizedBox(width: 16),
                  // Device info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSurface,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Monitor button (Android only)
                            if (_supportsBackgroundMonitor)
                              IconButton(
                                icon: Icon(
                                  _isMonitored
                                      ? Icons.monitor_heart
                                      : Icons.monitor_heart_outlined,
                                  color: _isMonitored
                                      ? colorScheme.primary
                                      : colorScheme.onSurface
                                          .withValues(alpha: 0.5),
                                  size: 20,
                                ),
                                onPressed: _toggleMonitor,
                                tooltip: _isMonitored
                                    ? 'Remove from monitor'
                                    : 'Add to monitor',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 28,
                                  minHeight: 28,
                                ),
                              ),
                            // Expand/Collapse button
                            if (rawManufacturerData.isNotEmpty ||
                                widget.bleDevice.services.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: colorScheme.primaryContainer
                                      .withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: IconButton(
                                  icon: Icon(
                                    widget.isExpanded
                                        ? Icons.expand_less
                                        : Icons.expand_more,
                                    color: colorScheme.primary,
                                    size: 18,
                                  ),
                                  onPressed: () {
                                    widget.onExpand(!widget.isExpanded);
                                  },
                                  tooltip:
                                      widget.isExpanded ? 'Collapse' : 'Expand',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 20,
                                    minHeight: 20,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.fingerprint,
                              size: 12,
                              color:
                                  colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                widget.bleDevice.deviceId,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurface
                                      .withValues(alpha: 0.7),
                                  fontFamily: 'monospace',
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            // Pair status
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: widget.bleDevice.paired == true
                                    ? Colors.green.withValues(alpha: 0.2)
                                    : Colors.orange.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                widget.bleDevice.paired == true
                                    ? 'Paired'
                                    : 'Unpaired',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: widget.bleDevice.paired == true
                                      ? Colors.green.shade700
                                      : Colors.orange.shade700,
                                ),
                              ),
                            ),
                            // Manufacturer data (only in collapsed mode)
                            if (!widget.isExpanded) ...[
                              ...rawManufacturerData.take(2).map((data) {
                                final companyName = CompanyIdentifierService
                                    .instance
                                    .getCompanyName(data.companyId);
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.secondaryContainer,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        data.companyIdRadix16,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color:
                                              colorScheme.onSecondaryContainer,
                                          fontWeight: FontWeight.w500,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                      if (companyName != null) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          companyName,
                                          style: TextStyle(
                                            fontSize: 9,
                                            color: colorScheme
                                                .onSecondaryContainer
                                                .withValues(alpha: 0.8),
                                            fontWeight: FontWeight.w400,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              }),
                            ],
                            // Services (only in collapsed mode)
                            if (!widget.isExpanded) ...[
                              ...widget.bleDevice.services
                                  .take(3)
                                  .map((service) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.tertiaryContainer,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    service.length > 12
                                        ? '${service.substring(0, 12)}...'
                                        : service,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: colorScheme.onTertiaryContainer,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                );
                              }),
                              if (widget.bleDevice.services.length > 3)
                                Text(
                                  '+${widget.bleDevice.services.length - 3} more',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: colorScheme.onSurface
                                        .withValues(alpha: 0.5),
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // Expanded details
              if (widget.isExpanded) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),
                if (rawManufacturerData.isNotEmpty) ...[
                  Text(
                    'Manufacturer Data',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...rawManufacturerData.map((data) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
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
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            'Company ID: ',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: colorScheme
                                                  .onSecondaryContainer,
                                            ),
                                          ),
                                          Expanded(
                                            child: SelectableText(
                                              data.companyIdRadix16,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: colorScheme
                                                    .onSecondaryContainer,
                                                fontFamily: 'monospace',
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      CompanyInfoWidget(
                                        companyId: data.companyId,
                                        colorScheme: colorScheme,
                                        labelStyle: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color:
                                              colorScheme.onSecondaryContainer,
                                        ),
                                        nameStyle: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color:
                                              colorScheme.onSecondaryContainer,
                                        ),
                                      ),
                                      if (data.payloadRadix16.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: SelectableText(
                                                data.payloadRadix16,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: colorScheme
                                                      .onSecondaryContainer
                                                      .withValues(alpha: 0.8),
                                                  fontFamily: 'monospace',
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: Icon(
                                    Icons.copy,
                                    size: 16,
                                    color: colorScheme.onSecondaryContainer,
                                  ),
                                  onPressed: () {
                                    final textToCopy = data
                                            .payloadRadix16.isNotEmpty
                                        ? 'Company ID: ${data.companyIdRadix16}\nPayload: ${data.payloadRadix16}'
                                        : 'Company ID: ${data.companyIdRadix16}';
                                    Clipboard.setData(
                                      ClipboardData(text: textToCopy),
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content:
                                            const Text('Copied to clipboard'),
                                        duration: const Duration(seconds: 1),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  },
                                  tooltip: 'Copy',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 24,
                                    minHeight: 24,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                ],
                if (widget.bleDevice.services.isNotEmpty) ...[
                  Text(
                    'Advertised Services',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: widget.bleDevice.services.map((service) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.tertiaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SelectableText(
                              service,
                              style: TextStyle(
                                fontSize: 10,
                                color: colorScheme.onTertiaryContainer,
                                fontWeight: FontWeight.w500,
                                fontFamily: 'monospace',
                              ),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: service));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text('Copied to clipboard'),
                                    duration: const Duration(seconds: 1),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                              child: Icon(
                                Icons.copy,
                                size: 14,
                                color: colorScheme.onTertiaryContainer
                                    .withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
