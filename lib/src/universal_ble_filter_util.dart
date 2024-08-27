import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

// A default Filter on dart side
// Used on Linux only
class UniversalBleFilterUtil {
  ScanFilter? scanFilter;

  bool filterDevice(BleDevice device) {
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
    return hasNamePrefixFilter && isNameMatchingFilters(filter, device) ||
        hasServiceFilter && isServicesMatchingFilters(filter, device) ||
        hasManufacturerDataFilter &&
            isManufacturerDataMatchingFilters(filter, device);
  }

  bool isNameMatchingFilters(ScanFilter scanFilter, BleDevice device) {
    var namePrefixFilter = scanFilter.withNamePrefix;
    if (namePrefixFilter.isEmpty) return true;

    String? name = device.name;
    if (name == null || name.isEmpty) return false;
    return namePrefixFilter.any(name.startsWith);
  }

  bool isServicesMatchingFilters(ScanFilter scanFilter, BleDevice device) {
    var serviceFilters = scanFilter.withServices;
    if (serviceFilters.isEmpty) return true;

    List<String> serviceUuids = device.services;
    if (serviceUuids.isEmpty) {
      return false;
    }
    return serviceFilters.any(serviceUuids.contains);
  }

  bool isManufacturerDataMatchingFilters(
    ScanFilter scanFilter,
    BleDevice device,
  ) {
    var filterMfdList = scanFilter.withManufacturerData;
    if (filterMfdList.isEmpty) return true;

    var mfd = device.manufacturerData;
    if (mfd == null || mfd.isEmpty) return false;

    var deviceMfd = ManufacturerData.fromData(mfd);

    // Check all filters
    for (final filterMfd in filterMfdList) {
      // Check if device have manufacturerData for this filter
      // Check companyIdentifier
      if (filterMfd.companyIdentifier != deviceMfd.companyId) {
        continue;
      }

      // Check data
      Uint8List? filterData = filterMfd.data;
      Uint8List? deviceData = deviceMfd.data;

      // If filter data is null and device data is not, continue to next deviceMfd
      if (filterData != null && deviceData == null) continue;

      if (filterData == null || deviceData == null) {
        return true;
      }

      if (filterData.length > deviceData.length) continue;

      // Apply mask
      Uint8List? filterMask = filterMfd.mask;
      bool dataMatched = true;
      if (filterMask != null && (filterMask.length == filterData.length)) {
        for (int i = 0; i < filterData.length; i++) {
          if ((filterData[i] & filterMask[i]) !=
              (deviceData[i] & filterMask[i])) {
            dataMatched = false;
            break;
          }
        }
      }
      // Compare data directly
      else {
        for (int i = 0; i < filterData.length; i++) {
          if (filterData[i] != deviceData[i]) {
            dataMatched = false;
            break;
          }
        }
      }

      if (dataMatched) return true;
    }

    return false;
  }
}
