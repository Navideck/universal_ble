import 'package:flutter/foundation.dart';

class BleCapabilities {
  /// Returns true if in-app pairing is possible either by API or by encrypted characteristic
  /// using any kind of pairing method (Just Works, Numeric Comparison or Passkey Entry).
  ///
  /// All platforms return true except Web/Windows and Web/Linux which return false
  /// because they only support "Numeric Comparison" and "Passkey Entry".
  ///
  /// For more fine-grained control it is recommended to use `triggersConfirmOnlyPairing`
  /// in conjunction with the pairing method of your device,
  /// e.g. if (!BleCapabilities.triggersConfirmOnlyPairing && deviceUsesConfirmOnlyPairing) throw "In-app pairing not supported";
  static final bool supportsAllPairingKinds =
      triggersConfirmOnlyPairing || hasSystemPairingApi;

  /// Returns true if the platform triggers pairing for devices that use only confirmation pairing
  /// (a.k.a. "Just Works" or legacy pairing) when trying to read or write to an encrypted characteristic.
  ///
  /// The "Numeric Comparison" and "Passkey Entry" pairing methods trigger pairing on all platforms.
  ///
  /// `Web/Linux` could also, under certain conditions, trigger "Just Works" pairing
  /// but it very unreliable, therefore we return false.
  static final triggersConfirmOnlyPairing =
      defaultTargetPlatform != TargetPlatform.windows &&
      defaultTargetPlatform != TargetPlatform.linux;

  /// Returns true if pair()/unpair() are supported on the platform.
  static bool hasSystemPairingApi =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  static bool requiresRuntimePermission =
      !_Platform.isWeb && !_Platform.isWindows && !_Platform.isLinux;

  static bool supportsBluetoothEnableApi =
      !_Platform.isWeb && !_Platform.isCupertino;

  static bool supportsConnectedDevicesApi = !_Platform.isWeb;

  static bool supportsPeripheralApi = !_Platform.isWeb && !_Platform.isLinux;

  static bool supportsRequestMtuApi = !_Platform.isWeb;

  /// Whether [UniversalBle.requestMtu] discovers the device's services on
  /// demand before reading the MTU.
  ///
  /// `true` on `iOS`/`macOS`, where CoreBluetooth exposes no MTU callback and
  /// reports the default ATT MTU (23) as if it were the negotiated value until
  /// the connection has settled — discovering the services is the documented
  /// signal that it is ready. Also `true` on `Linux`, where the MTU is read off
  /// the resolved characteristics. On `Android`/`Windows` the MTU is a property
  /// of the connection itself and is always available, so nothing is discovered.
  /// `Web` has no MTU API.
  static bool get mtuRequiresServiceDiscovery =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  static bool supportsConnectionPriorityApi =
      !_Platform.isWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Whether connection parameter update events are reported (Android API 26+).
  static bool supportsConnectionParametersUpdates =
      !_Platform.isWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Whether the platform has a native device picker (`UniversalBle.requestDevice`).
  /// Web uses the browser Bluetooth chooser; iOS uses AccessorySetupKit.
  static bool supportsRequestDeviceApi = _Platform.isWeb || _Platform.isIOS;
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
