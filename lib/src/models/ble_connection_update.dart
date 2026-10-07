import 'package:universal_ble/src/universal_ble.g.dart';

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

  /// Classification of the error, `null` when there is no error or the
  /// platform does not report one. Connection related values:
  ///
  /// * [UniversalBleErrorCode.deviceDisconnected]: the peripheral closed the
  ///   link (Apple `peripheralDisconnected`; Android HCI 0x13, `GATT_FAILURE`)
  /// * [UniversalBleErrorCode.connectionTimeout]: link lost, supervision
  ///   timeout (Apple `connectionTimeout`; Android HCI 0x08,
  ///   `GATT_CONNECTION_TIMEOUT`)
  /// * [UniversalBleErrorCode.connectionFailed]: the attempt did not succeed
  ///   (Apple `connectionFailed`; Android HCI 0x3E, `GATT_ERROR`,
  ///   `GATT_CONNECTION_CONGESTED`)
  /// * [UniversalBleErrorCode.connectionLimitExceeded]: Apple
  ///   `connectionLimitReached`
  /// * [UniversalBleErrorCode.connectionTerminated]: Android HCI 0x16
  /// * [UniversalBleErrorCode.unknownError]: anything else
  ///
  /// Windows, Linux and Web always report `null`.
  final UniversalBleErrorCode? errorCode;

  /// The raw platform value behind [errorCode]: `CBError.Code` on Apple, the
  /// GATT `status` of `onConnectionStateChange` on Android. Kept for
  /// diagnostics; `null` where [errorCode] is `null`.
  final int? nativeErrorCode;

  const BleConnectionUpdate({
    required this.deviceId,
    required this.isConnected,
    this.error,
    this.errorCode,
    this.nativeErrorCode,
  });

  @override
  String toString() =>
      'BleConnectionUpdate(deviceId: $deviceId, isConnected: $isConnected, '
      'error: $error, errorCode: $errorCode, nativeErrorCode: $nativeErrorCode)';
}
