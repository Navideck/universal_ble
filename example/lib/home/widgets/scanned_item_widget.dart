import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:universal_ble_example/data/company_identifier_service.dart';
import 'package:universal_ble_example/home/widgets/rssi_signal_indicator.dart';
import 'package:universal_ble_example/widgets/company_info_widget.dart';
import 'package:universal_ble_example/widgets/flash_on_update_widget.dart';

class ScannedItemWidget extends StatefulWidget {
  final BleDevice bleDevice;
  final int adFlashTrigger;
  final VoidCallback? onTap;
  final bool isExpanded;
  final Function(bool) onExpand;
  const ScannedItemWidget({
    super.key,
    required this.bleDevice,
    this.adFlashTrigger = 0,
    this.onTap,
    required this.isExpanded,
    required this.onExpand,
  });

  @override
  State<ScannedItemWidget> createState() => _ScannedItemWidgetState();
}

class _ScannedItemWidgetState extends State<ScannedItemWidget> {
  Timer? _timer;

  static String _formatLastAppeared(DateTime? timestamp) {
    if (timestamp == null) return '—';
    final elapsed = DateTime.now().difference(timestamp);
    if (elapsed.inSeconds < 2) return 'Actively advertising';
    if (elapsed.inSeconds < 60) {
      return '${elapsed.inSeconds} second${elapsed.inSeconds == 1 ? '' : 's'} ago';
    }
    if (elapsed.inMinutes < 60) {
      return '${elapsed.inMinutes} minute${elapsed.inMinutes == 1 ? '' : 's'} ago';
    }
    return '${elapsed.inHours} hour${elapsed.inHours == 1 ? '' : 's'} ago';
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    String? name = widget.bleDevice.name;
    List<ManufacturerData> rawManufacturerData =
        widget.bleDevice.manufacturerDataList;
    if (name == null || name.isEmpty) name = 'Unknown Device';

    final lastAppearedStr =
        _formatLastAppeared(widget.bleDevice.timestampDateTime);

    return FlashOnUpdateWidget(
      trigger: widget.adFlashTrigger,
      child: Card(
        elevation: 2,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
          child: InkWell(
          onTap: widget.onTap,
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
                      child: RssiSignalIndicator(
                          rssi: widget.bleDevice.rssi ?? 0),
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
                            // Expand/Collapse button
                            if (rawManufacturerData.isNotEmpty ||
                                widget.bleDevice.services.isNotEmpty ||
                                widget.bleDevice.serviceData.isNotEmpty)
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
                                  tooltip: widget.isExpanded
                                      ? 'Collapse'
                                      : 'Expand',
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
                        // Last seen
                        Row(
                          children: [
                            Icon(
                              Icons.ad_units_outlined,
                              size: 12,
                              color: colorScheme.primary
                                  .withValues(alpha: 0.8),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                lastAppearedStr == 'Actively advertising'
                                    ? lastAppearedStr
                                    : 'Last seen: $lastAppearedStr',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  color: colorScheme.onSurface
                                      .withValues(alpha: 0.7),
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
                              ...widget.bleDevice.services.take(3).map((service) {
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
                // Manufacturer Data (always shown)
                Text(
                  'Manufacturer Data',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                if (rawManufacturerData.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'No manufacturer data',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSecondaryContainer
                            .withValues(alpha: 0.7),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  )
                else
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
                // Service Data (always shown, last)
                Text(
                  'Service Data',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                if (widget.bleDevice.serviceData.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'No service data',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onTertiaryContainer
                            .withValues(alpha: 0.7),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  )
                else
                  ...widget.bleDevice.serviceData.entries.map((entry) {
                    final uuid = entry.key;
                    final bytes = entry.value;
                    final hex = bytes.isEmpty
                        ? ''
                        : '0x${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('').toUpperCase()}';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.tertiaryContainer,
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
                                            'Service UUID: ',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: colorScheme
                                                  .onTertiaryContainer,
                                            ),
                                          ),
                                          Expanded(
                                            child: SelectableText(
                                              uuid,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: colorScheme
                                                    .onTertiaryContainer,
                                                fontFamily: 'monospace',
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (hex.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        SelectableText(
                                          hex,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: colorScheme
                                                .onTertiaryContainer
                                                .withValues(alpha: 0.8),
                                            fontFamily: 'monospace',
                                          ),
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
                                    color: colorScheme.onTertiaryContainer,
                                  ),
                                  onPressed: () {
                                    final textToCopy = hex.isNotEmpty
                                        ? 'Service UUID: $uuid\nData: $hex'
                                        : 'Service UUID: $uuid';
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
              ],
            ],
          ),
        ),
      ),
    ),
    );
  }
}
