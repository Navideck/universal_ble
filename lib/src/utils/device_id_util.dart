import 'package:universal_ble/src/utils/device_id.dart';

/// Canonical form of a BLE device id.
///
/// A device id identifies the same device across platforms but is reported in
/// different cases (Android upper-cases MACs, Windows/WinRT lower-cases them).
/// Per-device state must be keyed by this canonical form so a device reported
/// in two cases can't split across entries.
String canonicalDeviceId(String deviceId) => deviceId.toDeviceId().canonical;
