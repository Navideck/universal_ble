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
    final manufacturerDataFilters = scanFilter.withManufacturerData;
    if (manufacturerDataFilters.isEmpty) return true;

    List<ManufacturerData> manufacturerDataList = device.manufacturerDataList;
    if (manufacturerDataList.isEmpty) return false;

    return manufacturerDataList.any((deviceMsd) => manufacturerDataFilters.any(
          (filterMsd) => _isManufacturerDataMatch(filterMsd, deviceMsd),
        ));
  }

  bool _isManufacturerDataMatch(
    ManufacturerDataFilter filterMsd,
    ManufacturerData deviceMsd,
  ) {
    if (filterMsd.companyIdentifier != deviceMsd.companyId) return false;

    Uint8List? filterPayload = filterMsd.payload;
    Uint8List devicePayload = deviceMsd.payload;

    if (filterPayload == null || filterPayload.isEmpty) return true;
    if (devicePayload.isEmpty) return false;
    if (filterPayload.length > devicePayload.length) return false;

    Uint8List? filterMask = filterMsd.mask;

    if (filterMask != null && filterMask.length == filterPayload.length) {
      for (int i = 0; i < filterPayload.length; i++) {
        if ((filterPayload[i] & filterMask[i]) !=
            (devicePayload[i] & filterMask[i])) {
          return false;
        }
      }
    } else {
      for (int i = 0; i < filterPayload.length; i++) {
        if (filterPayload[i] != devicePayload[i]) {
          return false;
        }
      }
    }
    return true;
  }
}
