import 'package:flutter/foundation.dart';

class Capabilities {
  static bool requiresRuntimePermission =
      !_Platform.isWeb && !_Platform.isWindows && !_Platform.isLinux;

  static bool supportsBluetoothEnableApi =
      !_Platform.isWeb && !_Platform.isCupertino;

  static bool supportsConnectedDevicesApi = !_Platform.isWeb;

  static bool supportsPairingApi = !_Platform.isWeb && !_Platform.isCupertino;

  static bool supportsRequestMtuApi = !_Platform.isWeb && !_Platform.isLinux;
}

class _Platform {
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
