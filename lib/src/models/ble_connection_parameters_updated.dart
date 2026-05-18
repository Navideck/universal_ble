import 'package:universal_ble/src/universal_ble.g.dart';

export 'package:universal_ble/src/universal_ble.g.dart'
    show BleConnectionParametersUpdated;

/// Helpers for [BleConnectionParametersUpdated] reported on Android.
extension BleConnectionParametersUpdatedX on BleConnectionParametersUpdated {
  /// Connection interval in milliseconds (interval × 1.25).
  double get intervalMs => interval * 1.25;

  /// Supervision timeout in milliseconds (supervisionTimeout × 10).
  double get supervisionTimeoutMs => supervisionTimeout * 10;

  /// Whether [status] indicates a successful parameter update (GATT_SUCCESS).
  bool get isSuccess => status == 0;

  /// Rough mapping from connection interval to [BleConnectionPriority].
  ///
  /// This is approximate — the OS may use intervals outside documented priority
  /// ranges (e.g. interval 420 ≈ 525 ms). Prefer [intervalMs] for throughput logic.
  BleConnectionPriority? get estimatedPriority {
    if (interval <= 24) return BleConnectionPriority.highPerformance;
    if (interval <= 64) return BleConnectionPriority.balanced;
    return BleConnectionPriority.lowPower;
  }
}
