import 'package:universal_ble/src/models/manufacturer_data_filter.dart';

class ScanFilter {
  List<String> withServices;
  List<ManufacturerDataFilter> withManufacturerData;
  List<String> withNamePrefix;
  List<ExclusionFilter> exclusionFilters;

  ScanFilter({
    this.withServices = const [],
    this.withManufacturerData = const [],
    this.withNamePrefix = const [],
    this.exclusionFilters = const [],
  });

  @override
  String toString() {
    return 'ScanFilter(withServices: $withServices, withManufacturerData: $withManufacturerData, withNamePrefix: $withNamePrefix, exclusionFilters: $exclusionFilters)';
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
      namePrefix != null;
}
