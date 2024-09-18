import 'package:flutter/foundation.dart';

class BleCapabilities {
  /// Returns true if pairing is possible either by API or by encrypted characteristic.
  /// 
  /// All platforms support this except Web/Windows and Web/Linux.
  /// 
  /// On `Web/Windows` and `Web/Linux` it is known to only work for devices that require passkey pairing.
  /// If your device requires passkey pairing you can consider this true for all platforms.
  /// 
  /// `Web/Linux` could under certain circumstances present a pairing dialog also for devices that do
  /// not use passkey pairing but it very unreliable so we consider it unsupported.
  static final bool supportsInAppPairing =
      _triggersPairingWithEncryptedChar || hasSystemPairingApi;

  static final _triggersPairingWithEncryptedChar =
      defaultTargetPlatform != TargetPlatform.windows ||
          defaultTargetPlatform != TargetPlatform.linux;

  static bool hasSystemPairingApi = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  static bool requiresRuntimePermission =
      !_Platform.isWeb && !_Platform.isWindows && !_Platform.isLinux;

  static bool supportsBluetoothEnableApi =
      !_Platform.isWeb && !_Platform.isCupertino;

  static bool supportsConnectedDevicesApi = !_Platform.isWeb;

  static bool supportsRequestMtuApi = !_Platform.isWeb;
}

class _Platform {
  static bool isWeb = kIsWeb;
  static bool isIOS = !isWeb && defaultTargetPlatform == TargetPlatform.iOS;
  static bool isMacos = !isWeb && defaultTargetPlatform == TargetPlatform.macOS;
  static bool isWindows =
      !isWeb && defaultTargetPlatform == TargetPlatform.windows;
  static bool isLinux = !isWeb && defaultTargetPlatform == TargetPlatform.linux;
  static bool get isCupertino => isIOS || isMacos;
}
