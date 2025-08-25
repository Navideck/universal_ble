import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

// A default Filter on dart side
// Used on Linux only
class UniversalBleFilterUtil {
  ScanFilter? scanFilter;

  bool shouldAcceptDevice(BleDevice device) =>
      !matchesExclusionFilter(device) && matchedScanFilter(device);

  bool matchesExclusionFilter(BleDevice device) {
    final exclusionFilters = scanFilter?.exclusionFilters;
    if (exclusionFilters == null || exclusionFilters.isEmpty) return false;

    final deviceName = device.name?.toLowerCase() ?? '';
    final deviceServices = device.services.toValidUUIDList();

    for (var filter in exclusionFilters) {
      if (!filter.hasValidFilters) continue;

      // Check name prefix
      final filterNamePrefix = filter.namePrefix?.toLowerCase();
      if (filterNamePrefix != null && filterNamePrefix.isNotEmpty) {
        if (!deviceName.startsWith(filterNamePrefix)) continue;
      }
      // Check services
      final filterServices = filter.services.toValidUUIDList();
      if (filterServices.isNotEmpty &&
          !filterServices.any(deviceServices.contains)) {
        continue;
      }
      // Check manufacturer data
      if (!manufacturerDataMatches(filter.manufacturerDataFilter, device)) {
        continue;
      }
      // Device matches an exclusion filter
      return true;
    }
    return false;
  }

  /// Returns true if the device matches the filter
  bool matchedScanFilter(BleDevice device) {
    final filter = scanFilter;
    if (filter == null) return true;

    final hasNamePrefixFilter = filter.withNamePrefix.isNotEmpty;
    final hasServiceFilter = filter.withServices.isNotEmpty;
    final hasManufacturerDataFilter = filter.withManufacturerData.isNotEmpty;

    // If there is no filter at all, then allow device
    if (!hasNamePrefixFilter &&
        !hasServiceFilter &&
        !hasManufacturerDataFilter) {
      return true;
    }

    // Else check one of the filter passes
    return (hasNamePrefixFilter && nameMatches(filter, device)) ||
        (hasServiceFilter && servicesMatch(filter, device)) ||
        (hasManufacturerDataFilter &&
            manufacturerDataMatches(filter.withManufacturerData, device));
  }

  bool nameMatches(ScanFilter scanFilter, BleDevice device) {
    final namePrefixFilter = scanFilter.withNamePrefix;
    if (namePrefixFilter.isEmpty) return true;

    final name = device.name;
    if (name == null || name.isEmpty) return false;
    return namePrefixFilter.any(name.startsWith);
  }

  bool servicesMatch(ScanFilter scanFilter, BleDevice device) {
    final serviceFilters = scanFilter.withServices.toValidUUIDList();
    if (serviceFilters.isEmpty) return true;

    final serviceUuids = device.services.toValidUUIDList();
    if (serviceUuids.isEmpty) {
      return false;
    }
    return serviceFilters.any(serviceUuids.contains);
  }

  bool manufacturerDataMatches(
    List<ManufacturerDataFilter> filters,
    BleDevice device,
  ) {
    if (filters.isEmpty) return true;

    final deviceDataList = device.manufacturerDataList;
    if (deviceDataList.isEmpty) return false;

    return deviceDataList.any((deviceData) {
      return filters.any((filter) {
        // Early return if company identifiers don't match
        if (filter.companyIdentifier != deviceData.companyId) {
          return false;
        }

        final payloadPrefix = filter.payloadPrefix;
        final payload = deviceData.payload;

        // Handle cases where payload prefix is null or empty
        if (payloadPrefix == null || payloadPrefix.isEmpty) {
          return true;
        }

        if (payload.isEmpty || payloadPrefix.length > payload.length) {
          return false;
        }

        final filterMask = filter.payloadMask;
        // Choose comparison strategy based on filter mask
        return filterMask != null && filterMask.length == payloadPrefix.length
            ? _compareWithMask(payloadPrefix, payload, filterMask)
            : _compareWithoutMask(payloadPrefix, payload);
      });
    });
  }

  bool _compareWithMask(Uint8List prefix, Uint8List payload, Uint8List mask) {
    for (int i = 0; i < prefix.length; i++) {
      if ((prefix[i] & mask[i]) != (payload[i] & mask[i])) {
        return false;
      }
    }
    return true;
  }

  bool _compareWithoutMask(Uint8List prefix, Uint8List payload) {
    for (int i = 0; i < prefix.length; i++) {
      if (prefix[i] != payload[i]) {
        return false;
      }
    }
    return true;
  }
}
