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
        final isSystem = isSystemService?.call(service.uuid) ?? false;
        final isSelected = selectedService?.uuid == service.uuid;

        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: Card(
            color: isSelected ? Colors.blue.withAlpha(10) : null,
            child: ExpandablePanel(
              header: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    const Icon(Icons.arrow_forward_ios),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              service.uuid,
                              style: TextStyle(
                                color: isSystem ? Colors.blue : null,
                                fontWeight: isSelected ? FontWeight.bold : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (onFavoriteToggle != null)
                      IconButton(
                        icon: Icon(
                          isFavorite ? Icons.star : Icons.star_border,
                          color: isFavorite ? Colors.amber : null,
                        ),
                        onPressed: () => onFavoriteToggle!(service.uuid),
                        iconSize: 20,
                      ),
                  ],
                ),
              ),
              collapsed: const SizedBox(),
              expanded: Column(
                children: service.characteristics.map((e) {
                  final isCharSelected = selectedCharacteristic?.uuid == e.uuid;
                  final isSubscribed =
                      subscribedCharacteristics?[e.uuid] ?? false;
                  return Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isCharSelected
                            ? Colors.blue.withAlpha(20)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                        border: isCharSelected
                            ? Border.all(color: Colors.blue, width: 2)
                            : null,
                      ),
                      child: InkWell(
                        onTap: () {
                          onTap?.call(service, e);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.arrow_right_outlined,
                                    color: isCharSelected ? Colors.blue : null,
                                  ),
                                  if (isSubscribed)
                                    const Icon(
                                      Icons.notifications_active,
                                      color: Colors.green,
                                      size: 16,
                                    ),
                                  Expanded(
                                    child: Text(
                                      e.uuid,
                                      style: TextStyle(
                                        fontWeight: isCharSelected
                                            ? FontWeight.bold
                                            : null,
                                        color: isCharSelected
                                            ? Colors.blue
                                            : null,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                "Properties: ${e.properties.map((e) => e.name).join(", ")}",
                                style: const TextStyle(fontSize: 12),
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
        );
      },
    );
  }
}
