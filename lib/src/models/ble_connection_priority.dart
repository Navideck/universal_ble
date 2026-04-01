/// Connection priority hint passed to [UniversalBle.requestConnectionPriority].
///
/// Maps to Android `BluetoothGatt.CONNECTION_PRIORITY_*` constants.
enum BleConnectionPriority {
  /// Default OS-managed interval (~30-50 ms). Android constant: 0.
  balanced,

  /// Low-latency interval (~7.5-15 ms), higher power draw. Android constant: 1.
  highPerformance,

  /// Power-optimised interval (~100-125 ms). Android constant: 2.
  lowPower,
}
