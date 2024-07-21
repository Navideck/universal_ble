class PlatformConfig {
  WebConfig? web;

  PlatformConfig({
    this.web,
  });
}

class WebConfig {
  List<String> optionalServices;
  List<int> optionalManufacturerData;

  WebConfig({
    this.optionalServices = const [],
    this.optionalManufacturerData = const [],
  });
}
