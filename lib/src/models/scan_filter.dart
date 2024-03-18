import 'dart:typed_data';

class ScanFilter {
  final List<String> withServices;
  final List<ManufacturerDataFilter> withManufacturerData;

  ScanFilter({
    this.withServices = const [],
    this.withManufacturerData = const [],
  });
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
}
