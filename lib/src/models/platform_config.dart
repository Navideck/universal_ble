/// Platform specific config to scan devices
class PlatformConfig {
  WebConfig? web;

  PlatformConfig({this.web});
}

/// Web config to scan devices
/// [useAsScanFilter] can be set to false if we want to use ScanFilter properties as `optionalServices` or `optionalManufacturerData` where
///  `optionalServices` is a list of service uuid's to ensure that you can access the specified services after connecting to the device,
/// by default services from scanFilter will be used
/// `optionalManufacturerData` is list of `CompanyIdentifier's` and used to add `ManufacturerData` in advertisement results of selected device from web dialog,
/// by default manufacturerData from scanFilter will be used
/// Checkout more details on [web](https://developer.mozilla.org/en-US/docs/Web/API/Bluetooth/requestDevice)
/// Note: you will only get advertisements if Experimental Flag is enabled in the browser
class WebConfig {
  final bool useAsScanFilter;

  WebConfig({
    this.useAsScanFilter = true,
  });
}
