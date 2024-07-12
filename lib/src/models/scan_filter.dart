import 'dart:typed_data';

class ScanFilter {
  List<String> withServices;
  List<ManufacturerDataFilter> withManufacturerData;
  List<String> withNamePrefix;

  ScanFilter({
    this.withServices = const [],
    this.withManufacturerData = const [],
    this.withNamePrefix = const [],
  });

  @override
  String toString() {
    return 'ScanFilter(withServices: $withServices, withManufacturerData: $withManufacturerData, withNamePrefix: $withNamePrefix)';
  }
}

class ManufacturerDataFilter {
  int? companyIdentifier;

  // Mask and data must be of same length
  Uint8List? data;

  /// For any bit in the mask, set it the 1 if it needs to match
  /// the one in manufacturer data, otherwise set it to 0.
  /// The 'mask' must have the same length as 'data'.
  Uint8List? mask;

  ManufacturerDataFilter({
    this.companyIdentifier,
    this.data,
    this.mask,
  });

  @override
  String toString() {
    return 'ManufacturerDataFilter(companyIdentifier: $companyIdentifier, data: $data, mask: $mask)';
  }
}
