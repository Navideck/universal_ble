import 'package:flutter/foundation.dart';

class BleCapabilities {
  /// You should pass wether your peripheral uses "Just Works" pairing.
  /// Defaults to true since most devices use this kind of pairing.
  ///
  /// Returns true if pairing is possible either by API or by encrypted characteristic.
  ///
  /// Platforms other than Web/Windows and Web/Linux always return true.
  ///
  /// Web/Windows and Web/Linux return false if the peripheral uses "Just Works" pairing
  /// or true otherwise.
  ///
  /// `Web/Linux` could also, under certain conditions, trigger "Just Works" pairing
  /// but it very unreliable, therefore we return false.
  static bool supportsInAppPairing({bool peripheralUsesJustWorks = true}) =>
      _triggersPairingWithEncryptedChar(peripheralUsesJustWorks) ||
      hasSystemPairingApi;

  static _triggersPairingWithEncryptedChar(bool peripheralUsesJustWorks) {
    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux) {
      return !peripheralUsesJustWorks;
    }

    return true;
  }

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
