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
  /// Must be of integer type, in hex or decimal form (e.g. 0x004c or 76).
  int companyIdentifier;

  /// Matches as prefix the peripheral's advertised data.
  Uint8List? payload;

  /// For any bit in the mask, set it to 1 if it needs to match
  /// the corresponding one in manufacturer data, otherwise set it to 0.
  /// The 'mask' must have the same length as 'payload'.
  Uint8List? mask;

  /// Filter manufacturer data by company identifier, payload prefix, or payload mask.
  ManufacturerDataFilter({
    required this.companyIdentifier,
    this.payload,
    this.mask,
  });

  @override
  String toString() {
    return 'ManufacturerDataFilter(companyIdentifier: $companyIdentifier, payload: $payload, mask: $mask)';
  }
}
