import 'package:universal_ble/universal_ble.dart';

/// Filter criteria used to discover matching devices during BLE scanning.
class ScanFilter {
  List<String> withServices;
  List<ManufacturerDataFilter> withManufacturerData;
  List<String> withNamePrefix;
  List<ExclusionFilter> exclusionFilters;

  /// Whether to discover only connectable devices.
  ///
  /// When set to `true`, non-connectable devices (such as beacons) are filtered out.
  /// Only applies when a [BleDevice] provides a non-null [BleDevice.connectable] status.
  bool? connectableOnly;

  ScanFilter({
    this.withServices = const [],
    this.withManufacturerData = const [],
    this.withNamePrefix = const [],
    this.exclusionFilters = const [],
    this.connectableOnly,
  });

  @override
  String toString() {
    return 'ScanFilter(withServices: $withServices, withManufacturerData: $withManufacturerData, withNamePrefix: $withNamePrefix, exclusionFilters: $exclusionFilters, connectableOnly: $connectableOnly)';
  }
}

class ExclusionFilter {
  List<String> services;
  List<ManufacturerDataFilter> manufacturerDataFilter;
  String? namePrefix;

  ExclusionFilter({
    this.services = const [],
    this.manufacturerDataFilter = const [],
    this.namePrefix,
  });

  bool get hasValidFilters =>
      services.isNotEmpty ||
      manufacturerDataFilter.isNotEmpty ||
      (namePrefix?.isNotEmpty ?? false);
}
