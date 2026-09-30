/// A connection state change of a device, including the platform's error
/// details when the change was not requested by the app.
class BleConnectionUpdate {
  /// Device id as reported by the platform.
  final String deviceId;

  /// `true` after a successful connection, `false` after a disconnect or a
  /// failed connection attempt.
  final bool isConnected;

  /// Human readable error, `null` when the change was requested by the app.
  ///
  /// The text is platform dependent and, on Apple, localized. Prefer
  /// [errorCode] when deciding how to react.
  final String? error;

  /// Platform's numeric code for the error, `null` when there is no error or
  /// the platform does not report one.
  ///
  /// * Apple: `CBError.Code`, e.g. `6` (`connectionTimeout`, link lost) or
  ///   `7` (`peripheralDisconnected`, the peripheral closed the link).
  /// * Android: the GATT `status` of `onConnectionStateChange`, e.g. `8`
  ///   (`GATT_CONN_TIMEOUT`), `19` (remote terminated), `133`
  ///   (`GATT_ERROR`), `147` (`GATT_CONNECTION_TIMEOUT`) or `257`
  ///   (`GATT_FAILURE`). Which value the stack reports depends on the OS
  ///   version and vendor.
  /// * Windows, Linux, Web: always `null`.
  final int? errorCode;

  const BleConnectionUpdate({
    required this.deviceId,
    required this.isConnected,
    this.error,
    this.errorCode,
  });

  @override
  String toString() =>
      'BleConnectionUpdate(deviceId: $deviceId, isConnected: $isConnected, '
      'error: $error, errorCode: $errorCode)';
}
