import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

import 'device_id_util.dart';

/// Cross-platform scan de-duplication, backing `UniversalBle.startScan`'s
/// `skipDuplicates`.
///
/// When enabled, [shouldEmit] returns `false` for a repeated result whose
/// advertisement payload is unchanged, so consumers only see a device's first
/// sighting and later payload changes. Volatile metadata (RSSI, timestamps,
/// pairing state) is intentionally excluded: an identical broadcast is treated
/// as a duplicate.
class ScanDeduplicator {
  bool _enabled = false;
  final Map<String, BleDevice> _lastByDevice = {};

  bool get enabled => _enabled;

  /// Turns de-duplication on or off without clearing remembered results.
  void setEnabled(bool enabled) => _enabled = enabled;

  /// Forgets remembered results so a new scan session starts from a clean slate.
  void reset() => _lastByDevice.clear();

  /// Whether [device] should be emitted. Always `true` while disabled.
  bool shouldEmit(BleDevice device) {
    if (!_enabled) return true;

    final key = canonicalDeviceId(device.deviceId);
    final previous = _lastByDevice[key];
    final isDuplicate =
        previous != null && _isSameAdvertisement(previous, device);
    _lastByDevice[key] = device;
    return !isDuplicate;
  }

  /// Compares only the fields that make up a device's advertisement payload.
  bool _isSameAdvertisement(BleDevice a, BleDevice b) {
    return a.name == b.name &&
        a.connectable == b.connectable &&
        _sameStrings(a.services, b.services) &&
        _sameManufacturerData(a.manufacturerDataList, b.manufacturerDataList) &&
        _sameServiceData(a.serviceData, b.serviceData);
  }

  /// Order-insensitive, duplicate-preserving list comparison.
  bool _sameStrings(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    final remaining = List<String>.of(b);
    for (final value in a) {
      if (!remaining.remove(value)) return false;
    }
    return true;
  }

  bool _sameManufacturerData(
    List<ManufacturerData> a,
    List<ManufacturerData> b,
  ) {
    if (a.length != b.length) return false;
    final remaining = List<ManufacturerData>.of(b);
    for (final value in a) {
      final index = remaining.indexWhere((item) => item == value);
      if (index < 0) return false;
      remaining.removeAt(index);
    }
    return true;
  }

  bool _sameServiceData(Map<String, Uint8List> a, Map<String, Uint8List> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other == null || !listEquals(entry.value, other)) return false;
    }
    return true;
  }
}
