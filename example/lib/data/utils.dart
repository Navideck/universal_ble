import 'package:universal_ble/universal_ble.dart';

bool isSystemService(String uuid) {
  final normalized = uuid.toUpperCase().replaceAll('-', '');
  return normalized == '00001800' ||
      normalized == '00001801' ||
      normalized == '0000180A' ||
      normalized.startsWith('000018');
}

/// Sorts BLE services with the following priority:
/// 1. Favorite services first
/// 2. System services last
/// 3. Other services in between
List<BleService> sortBleServices(
  List<BleService> services, {
  Set<String>? favoriteServices,
}) {
  final sortedServices = List<BleService>.from(services);
  sortedServices.sort((a, b) {
    final aIsFavorite = favoriteServices?.contains(a.uuid) ?? false;
    final bIsFavorite = favoriteServices?.contains(b.uuid) ?? false;
    if (aIsFavorite != bIsFavorite) {
      return aIsFavorite ? -1 : 1;
    }
    final aIsSystem = isSystemService(a.uuid);
    final bIsSystem = isSystemService(b.uuid);
    if (aIsSystem != bIsSystem) {
      return aIsSystem ? 1 : -1;
    }
    return 0;
  });
  return sortedServices;
}

/// Returns a list of all filtered characteristics with their parent services.
/// Services are sorted (favorites first, system services last).
/// Characteristics are filtered by property filters if provided.
List<({BleService service, BleCharacteristic characteristic})>
    getFilteredBleCharacteristics(
  List<BleService> services, {
  Set<String>? favoriteServices,
  Set<CharacteristicProperty>? propertyFilters,
}) {
  final List<({BleService service, BleCharacteristic characteristic})> result =
      [];

  // Sort services: favorites first, then system services, then others
  final sortedServices = sortBleServices(
    services,
    favoriteServices: favoriteServices,
  );

  for (var service in sortedServices) {
    for (var char in service.characteristics) {
      // Filter by properties if filters are selected
      if (propertyFilters != null && propertyFilters.isNotEmpty) {
        if (char.properties.any((prop) => propertyFilters.contains(prop))) {
          result.add((service: service, characteristic: char));
        }
      } else {
        result.add((service: service, characteristic: char));
      }
    }
  }
  return result;
}

/// Finds the next or previous characteristic in a filtered list.
/// 
/// [filtered] - The filtered list of (service, characteristic) tuples
/// [currentCharacteristicUuid] - The UUID of the currently selected characteristic
/// [next] - If true, finds the next item; if false, finds the previous item
/// 
/// Returns the next/previous item, or the first item if current is not found,
/// or null if the list is empty.
({BleService service, BleCharacteristic characteristic})?
    navigateToAdjacentCharacteristic(
  List<({BleService service, BleCharacteristic characteristic})> filtered,
  String currentCharacteristicUuid,
  bool next,
) {
  if (filtered.isEmpty) return null;

  final currentIndex = filtered.indexWhere(
    (item) => item.characteristic.uuid == currentCharacteristicUuid,
  );

  if (currentIndex == -1) {
    // Current selection not in filtered list, return first
    return filtered.first;
  }

  if (next) {
    // Navigate to next (with wrapping)
    final nextIndex = (currentIndex + 1) % filtered.length;
    return filtered[nextIndex];
  } else {
    // Navigate to previous (with wrapping)
    final previousIndex =
        currentIndex > 0 ? currentIndex - 1 : filtered.length - 1;
    return filtered[previousIndex];
  }
}
