import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

// A default Filter on dart side
// Used on Linux only
class UniversalBleFilterUtil {
  /// The filter of the current scan session.
  ///
  /// Kept as a plain field rather than derived state: unlike the native filter
  /// utils, there is nothing here to keep in sync with it. Every platform
  /// assigns it in `startScan`, so a previous scan's filter cannot leak in.
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
      final manufacturerFilters = filter.manufacturerDataFilter;
      if (manufacturerFilters.isNotEmpty &&
          !manufacturerDataMatches(manufacturerFilters, device)) {
        continue;
      }
      // Device matches an exclusion filter
      return true;
    }
    return false;
  }

  bool matchesConnectableFilter(BleDevice device) {
    final filter = scanFilter;
    if (filter == null || filter.connectableOnly != true) return true;
    if (device.connectable == null) return true;
    return device.connectable!;
  }

  /// Returns true if the device matches the filter
  bool matchedScanFilter(BleDevice device) {
    final filter = scanFilter;
    if (filter == null) return true;

    // Check if connectable
    if (!matchesConnectableFilter(device)) {
      return false;
    }

    // The conditions are in OR relation. Each check below is a strict predicate
    // answering "does this dimension match?", so an unfiltered dimension
    // contributes nothing and needs no `has…Filter &&` guard of its own.
    final hasAnyFilter = filter.withNamePrefix.isNotEmpty ||
        filter.withServices.isNotEmpty ||
        filter.withServiceData.isNotEmpty ||
        filter.withManufacturerData.isNotEmpty;
    if (!hasAnyFilter) return true;

    return nameMatches(filter, device) ||
        servicesMatch(filter, device) ||
        serviceDataMatch(filter, device) ||
        manufacturerDataMatches(filter.withManufacturerData, device);
  }

  bool nameMatches(ScanFilter scanFilter, BleDevice device) {
    final name = device.name;
    if (name == null || name.isEmpty) return false;
    return scanFilter.withNamePrefix.any(name.startsWith);
  }

  bool servicesMatch(ScanFilter scanFilter, BleDevice device) {
    final serviceFilters = scanFilter.withServices.toValidUUIDList();
    final serviceUuids = device.services.toValidUUIDList();
    if (serviceUuids.isEmpty) {
      return false;
    }
    return serviceFilters.any(serviceUuids.contains);
  }

  /// Returns true if the device advertises Service Data for any of the filter's
  /// UUIDs.
  ///
  /// Unlike [servicesMatch], this looks at [BleDevice.serviceData], so devices
  /// that carry a service UUID only in their Service Data (beacons) are matched.
  /// The device keys are normalised by [BleDevice], but anything unparseable is
  /// skipped rather than throwing, so malformed advertisement data cannot fail a
  /// scan.
  bool serviceDataMatch(ScanFilter scanFilter, BleDevice device) {
    final serviceDataFilters = scanFilter.withServiceData.toValidUUIDList();
    final advertisedUuids = device.serviceData.keys
        .map(BleUuidParser.stringOrNull)
        .whereType<String>()
        .toSet();
    return serviceDataFilters.any(advertisedUuids.contains);
  }

  bool manufacturerDataMatches(
    List<ManufacturerDataFilter> filters,
    BleDevice device,
  ) {
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
