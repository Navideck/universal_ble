import 'package:universal_ble/universal_ble.dart';

import 'device_id_util.dart';

/// Cross-platform scan de-duplication, backing `UniversalBle.startScan`'s
/// `skipDuplicates`.
///
/// When enabled, [shouldEmit] returns `false` for any repeated result of a
/// device already reported since the last [reset], so consumers see each device
/// once per scan session. This matches Android's native
/// `CALLBACK_TYPE_FIRST_MATCH` and is enforced on every platform.
class ScanDeduplicator {
  bool _enabled = false;
  final Set<String> _seen = {};

  bool get enabled => _enabled;

  /// Turns de-duplication on or off without clearing remembered results.
  void setEnabled(bool enabled) => _enabled = enabled;

  /// Forgets remembered results so a new scan session starts from a clean slate.
  void reset() => _seen.clear();

  /// Whether [device] should be emitted. Always `true` while disabled.
  ///
  /// Returns `true` only the first time a device is seen since the last [reset];
  /// later sightings (including ones with a changed advertisement payload) are
  /// treated as duplicates.
  bool shouldEmit(BleDevice device) {
    if (!_enabled) return true;
    return _seen.add(canonicalDeviceId(device.deviceId));
  }
}
