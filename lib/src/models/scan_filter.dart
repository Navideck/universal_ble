import 'package:universal_ble/universal_ble.dart';

/// Filter criteria used to discover matching devices during BLE scanning.
class ScanFilter {
  List<String> withServices;

  /// Matches devices that advertise [Service Data](https://www.bluetooth.com/blog/advertising-works-part-2/)
  /// for any of the given service UUIDs.
  ///
  /// This is a different field from the advertised service UUIDs matched by
  /// [withServices]: a device may carry a service UUID only inside its Service
  /// Data (the `0x16`/`0x20`/`0x21` advertising data types) without listing it in
  /// its advertised service UUID list — beacons such as Eddystone (`0xFEAA`) or
  /// the ATC_MiThermometer (`0x181A`) do exactly that, and are invisible to
  /// [withServices]. See [#57](https://github.com/Navideck/universal_ble/issues/57).
  ///
  /// UUIDs are accepted in any case and in short (`181A`), `0x`-prefixed, or
  /// full 128-bit form. As with the other conditions, an empty list is ignored
  /// and the conditions are in `OR` relation.
  ///
  /// The matching Service Data bytes are reported in [BleDevice.serviceData].
  ///
  /// Platform notes: on `Android` and `Apple` this switches the scan to the
  /// software filter path — the advertisement packets cannot be filtered by the
  /// platform (a controller-level scan filter or `withServices` would discard
  /// the device before the plugin sees it), so more advertisements reach the app
  /// process at some battery cost. Unsupported on Web, which throws
  /// `notSupported`; scan without a service filter there and read
  /// [BleDevice.serviceData] from the advertisement events instead.
  List<String> withServiceData;
  List<ManufacturerDataFilter> withManufacturerData;
  List<String> withNamePrefix;
  List<ExclusionFilter> exclusionFilters;

  /// Whether to discover only connectable devices.
  ///
  /// When set to `true`, non-connectable devices (such as beacons) are filtered out.
  /// Devices with unknown (`null`) [BleDevice.connectable] status pass this filter,
  /// so this option is a no-op on platforms that do not report connectability (e.g. Linux and Web).
  bool? connectableOnly;

  ScanFilter({
    this.withServices = const [],
    this.withServiceData = const [],
    this.withManufacturerData = const [],
    this.withNamePrefix = const [],
    this.exclusionFilters = const [],
    this.connectableOnly,
  });

  @override
  String toString() {
    return 'ScanFilter(withServices: $withServices, withServiceData: $withServiceData, withManufacturerData: $withManufacturerData, withNamePrefix: $withNamePrefix, exclusionFilters: $exclusionFilters, connectableOnly: $connectableOnly)';
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
