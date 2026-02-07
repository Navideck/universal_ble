import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:universal_ble_example/data/company_identifier_service.dart';
import 'package:universal_ble_example/home/widgets/rssi_signal_indicator.dart';
import 'package:universal_ble_example/widgets/company_info_widget.dart';
import 'package:universal_ble_example/widgets/flash_on_update_widget.dart';

class ScannedItemWidget extends StatelessWidget {
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

  static String _formatAdTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }

  static String _advertisementPayload(BleDevice device) {
    if (device.manufacturerDataList.isNotEmpty) {
      final hex = device.manufacturerDataList.first.payloadRadix16;
      return hex.length > 24 ? '${hex.substring(0, 24)}…' : hex;
    }
    if (device.serviceData.isNotEmpty) {
      final entry = device.serviceData.entries.first;
      final hex = '0x${entry.value.map((b) => b.toRadixString(16).padLeft(2, '0')).join('').toUpperCase()}';
      return hex.length > 24 ? '${hex.substring(0, 24)}…' : hex;
    }
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    String? name = bleDevice.name;
    List<ManufacturerData> rawManufacturerData = bleDevice.manufacturerDataList;
    if (name == null || name.isEmpty) name = 'Unknown Device';

    final adTimeStr = bleDevice.timestampDateTime != null
        ? _formatAdTime(bleDevice.timestampDateTime!)
        : '—';
    final payloadStr = _advertisementPayload(bleDevice);

    return FlashOnUpdateWidget(
      trigger: adFlashTrigger,
      child: Card(
        elevation: 2,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: InkWell(
          onTap: onTap,
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
                      child: RssiSignalIndicator(rssi: bleDevice.rssi ?? 0),
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
                                bleDevice.services.isNotEmpty)
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
                                    isExpanded
                                        ? Icons.expand_less
                                        : Icons.expand_more,
                                    color: colorScheme.primary,
                                    size: 18,
                                  ),
                                  onPressed: () {
                                    onExpand(!isExpanded);
                                  },
                                  tooltip: isExpanded ? 'Collapse' : 'Expand',
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
                                bleDevice.deviceId,
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
                        // Last advertisement (timestamp + payload only)
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
                                'Last ad: $adTimeStr · $payloadStr',
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
                                color: bleDevice.paired == true
                                    ? Colors.green.withValues(alpha: 0.2)
                                    : Colors.orange.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                bleDevice.paired == true
                                    ? 'Paired'
                                    : 'Unpaired',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: bleDevice.paired == true
                                      ? Colors.green.shade700
                                      : Colors.orange.shade700,
                                ),
                              ),
                            ),
                            // Manufacturer data (only in collapsed mode)
                            if (!isExpanded) ...[
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
                            if (!isExpanded) ...[
                              ...bleDevice.services.take(3).map((service) {
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
                              if (bleDevice.services.length > 3)
                                Text(
                                  '+${bleDevice.services.length - 3} more',
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
              if (isExpanded) ...[
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
                if (bleDevice.services.isNotEmpty) ...[
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
                    children: bleDevice.services.map((service) {
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
    ),
    );
  }
}
