import 'package:flutter/foundation.dart';

class BleCapabilities {
  /// Returns true if pairing is possible either by API or by encrypted characteristic.
  ///
  /// All platforms return true except Web/Windows and Web/Linux which return false.
  ///
  /// Under conditions, `Web/Windows` and `Web/Linux` could still trigger in-app pairing.
  /// Peripherals that require "Numeric Comparison" or "Passkey Entry" can
  /// successfully trigger pairing.
  ///
  /// `Web/Linux` could also, under certain conditions, trigger "Just Works" pairing
  /// but it very unreliable, therefore we return false.
  static final bool supportsInAppPairing =
      _triggersPairingWithEncryptedChar || hasSystemPairingApi;

  static final _triggersPairingWithEncryptedChar =
      defaultTargetPlatform != TargetPlatform.windows &&
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
