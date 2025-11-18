import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:universal_ble_example/home/widgets/rssi_signal_indicator.dart';

class ScannedItemWidget extends StatelessWidget {
  final BleDevice bleDevice;
  final VoidCallback? onTap;
  const ScannedItemWidget({super.key, required this.bleDevice, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    String? name = bleDevice.name;
    List<ManufacturerData> rawManufacturerData = bleDevice.manufacturerDataList;
    if (name == null || name.isEmpty) name = 'Unknown Device';

    return Card(
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
          child: Row(
            children: [
              // Signal indicator
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.5),
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
                            bleDevice.paired == true ? 'Paired' : 'Unpaired',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: bleDevice.paired == true
                                  ? Colors.green.shade700
                                  : Colors.orange.shade700,
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
                          color: colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            bleDevice.deviceId,
                            style: TextStyle(
                              fontSize: 12,
                              color:
                                  colorScheme.onSurface.withValues(alpha: 0.7),
                              fontFamily: 'monospace',
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (rawManufacturerData.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: rawManufacturerData.take(2).map((data) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              data.companyIdRadix16,
                              style: TextStyle(
                                fontSize: 10,
                                color: colorScheme.onSecondaryContainer,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    if (bleDevice.services.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: bleDevice.services.take(3).map((service) {
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
                        }).toList(),
                      ),
                      if (bleDevice.services.length > 3)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '+${bleDevice.services.length - 3} more',
                            style: TextStyle(
                              fontSize: 10,
                              color:
                                  colorScheme.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                color: colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
