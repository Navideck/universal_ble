import 'package:universal_ble/src/universal_ble.g.dart';

/// A connection state change of a device, including the platform's error
/// details when the change was not requested by the app.
class BleConnectionChange {
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

  /// Classification of the error. `null` on success and where the platform
  /// reports no code at all: Windows, Linux and Web, and (usually) a
  /// disconnect requested by the app. A code the plugin does not recognise
  /// is [UniversalBleErrorCode.unknownError], not `null`. Connection related
  /// values:
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
  ///   `connectionLimitReached`; Android HCI 0x09
  /// * [UniversalBleErrorCode.connectionAlreadyExists]: Android HCI 0x0B
  /// * [UniversalBleErrorCode.connectionRejected]: Android HCI 0x0D-0x0F
  /// * [UniversalBleErrorCode.connectionTerminated]: Android HCI 0x16
  /// * [UniversalBleErrorCode.unknownError]: anything else
  ///
  /// A connection attempt that never succeeds is always
  /// [UniversalBleErrorCode.connectionFailed]: Apple reports it through
  /// `didFailToConnect`; on Android it arrives as a disconnect, and the plugin
  /// classifies it by whether the link had reached `STATE_CONNECTED`.
  final UniversalBleErrorCode? errorCode;

  /// The raw platform value behind [errorCode]: `CBError.Code` on Apple, the
  /// GATT `status` of `onConnectionStateChange` on Android. The numeric
  /// ranges overlap across platforms (6 is `connectionTimeout` on Apple and
  /// an HCI reason on Android), so branch on [errorCode] and keep this for
  /// diagnostics. `null` where [errorCode] is `null`.
  final int? nativeErrorCode;

  const BleConnectionChange({
    required this.deviceId,
    required this.isConnected,
    this.error,
    this.errorCode,
    this.nativeErrorCode,
  });

  @override
  String toString() =>
      'BleConnectionChange(deviceId: $deviceId, isConnected: $isConnected, '
      'error: $error, errorCode: $errorCode, nativeErrorCode: $nativeErrorCode)';
}
