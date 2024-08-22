/// Platform specific config to scan devices
class PlatformConfig {
  WebConfig? web;

  PlatformConfig({this.web});
}

/// Web config to scan devices
/// if [scanAll] is true, then scanFilter properties will be used only as `optionalServices` or `optionalManufacturerData`, and no filter will be applied to scan results, where
/// `optionalServices` is a list of service uuid's to ensure that you can access the specified services after connecting to the device,
/// `optionalManufacturerData` is list of `CompanyIdentifier's` and used to add `ManufacturerData` in advertisement results of selected device from web dialog,
/// Checkout more details on [web](https://developer.mozilla.org/en-US/docs/Web/API/Bluetooth/requestDevice)
/// Note: you will only get advertisements if Experimental Flag is enabled in the browser
class WebConfig {
  final bool? scanAll;

  WebConfig({
    this.scanAll,
  });
}
