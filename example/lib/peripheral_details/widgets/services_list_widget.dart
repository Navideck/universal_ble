import 'package:expandable/expandable.dart';
import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';

class ServicesListWidget extends StatelessWidget {
  final List<BleService> discoveredServices;
  final bool scrollable;
  final void Function(BleService service, BleCharacteristic characteristic)?
      onTap;
  final BleService? selectedService;
  final BleCharacteristic? selectedCharacteristic;
  final Set<String>? favoriteServices;
  final Map<String, bool>? subscribedCharacteristics;
  final void Function(String serviceUuid)? onFavoriteToggle;
  final bool Function(String uuid)? isSystemService;

  const ServicesListWidget({
    super.key,
    required this.discoveredServices,
    this.onTap,
    this.scrollable = false,
    this.selectedService,
    this.selectedCharacteristic,
    this.favoriteServices,
    this.subscribedCharacteristics,
    this.onFavoriteToggle,
    this.isSystemService,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final favoriteStarColor = Colors.amber;
    final subscribedNotificationIconColor = Colors.green;
    final selectedColor = colorScheme.primary;
    final selectedCharacteristicBackgroundColor =
        colorScheme.primaryContainer.withValues(alpha: 0.5);

    // Sort services: favorites first, then system services, then others
    final sortedServices = List<BleService>.from(discoveredServices);
    sortedServices.sort((a, b) {
      final aIsFavorite = favoriteServices?.contains(a.uuid) ?? false;
      final bIsFavorite = favoriteServices?.contains(b.uuid) ?? false;
      if (aIsFavorite != bIsFavorite) {
        return aIsFavorite ? -1 : 1;
      }
      final aIsSystem = isSystemService?.call(a.uuid) ?? false;
      final bIsSystem = isSystemService?.call(b.uuid) ?? false;
      if (aIsSystem != bIsSystem) {
        return aIsSystem ? 1 : -1;
      }
      return 0;
    });
    return ListView.builder(
      shrinkWrap: !scrollable,
      physics: scrollable ? null : const NeverScrollableScrollPhysics(),
      itemCount: sortedServices.length,
      itemBuilder: (BuildContext context, int index) {
        final service = sortedServices[index];
        final isFavorite = favoriteServices?.contains(service.uuid) ?? false;
        final isSelected = selectedService?.uuid == service.uuid;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: Card(
            elevation: isSelected ? 2 : 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: isSelected
                  ? BorderSide(color: selectedColor, width: 2)
                  : BorderSide.none,
            ),
            child: ExpandablePanel(
              header: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 14,
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        service.uuid,
                        style: TextStyle(
                          fontSize: 13,
                          fontFamily: 'monospace',
                          color: colorScheme.onSurface,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (onFavoriteToggle != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(
                          isFavorite ? Icons.star : Icons.star_border,
                          color: isFavorite
                              ? favoriteStarColor
                              : colorScheme.onSurface.withValues(alpha: 0.4),
                        ),
                        onPressed: () => onFavoriteToggle!(service.uuid),
                        iconSize: 20,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              collapsed: const SizedBox(),
              expanded: Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Column(
                  children: service.characteristics.map((e) {
                    final isCharSelected =
                        selectedCharacteristic?.uuid == e.uuid;
                    final isSubscribed =
                        subscribedCharacteristics?[e.uuid] ?? false;
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8.0,
                        vertical: 4.0,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isCharSelected
                              ? selectedCharacteristicBackgroundColor
                              : colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(8),
                          border: isCharSelected
                              ? Border.all(color: selectedColor, width: 1.5)
                              : null,
                        ),
                        child: InkWell(
                          onTap: () {
                            onTap?.call(service, e);
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.arrow_right_outlined,
                                      size: 16,
                                      color: isCharSelected
                                          ? selectedColor
                                          : colorScheme.onSurface
                                              .withValues(alpha: 0.6),
                                    ),
                                    const SizedBox(width: 8),
                                    if (isSubscribed) ...[
                                      Icon(
                                        Icons.notifications_active,
                                        color: subscribedNotificationIconColor,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 4),
                                    ],
                                    Expanded(
                                      child: Text(
                                        e.uuid,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontFamily: 'monospace',
                                          fontWeight: isCharSelected
                                              ? FontWeight.bold
                                              : FontWeight.w500,
                                          color: isCharSelected
                                              ? selectedColor
                                              : colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: e.properties.map((prop) {
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
                                          color:
                                              colorScheme.onSecondaryContainer,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
