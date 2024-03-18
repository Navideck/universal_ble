import 'package:flutter/foundation.dart';

class Capabilities {
  static bool requiresRuntimePermission =
      !Platform.isWeb && !Platform.isWindows && !Platform.isLinux;

  static bool supportsBluetoothEnableApi =
      !Platform.isWeb && !Platform.isCupertino;

  static bool supportsConnectedDevicesApi = !Platform.isWeb;

  static bool supportsPairingApi = !Platform.isWeb && !Platform.isCupertino;

  static bool supportsRequestMtuApi = !Platform.isWeb;
}

class Platform {
  static bool isWeb = kIsWeb;
  static bool isIOS = !isWeb && defaultTargetPlatform == TargetPlatform.iOS;
  static bool isAndroid =
      !isWeb && defaultTargetPlatform == TargetPlatform.android;
  static bool isMacos = !isWeb && defaultTargetPlatform == TargetPlatform.macOS;
  static bool isWindows =
      !isWeb && defaultTargetPlatform == TargetPlatform.windows;
  static bool isLinux = !isWeb && defaultTargetPlatform == TargetPlatform.linux;
  static bool get isMobile => isIOS || isAndroid;
  static bool get isCupertino => isIOS || isMacos;
  static bool get isDesktop => isWindows || isLinux || isMacos;
}
