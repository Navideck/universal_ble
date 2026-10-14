class BlePeripheralCapabilities {
  final bool supportsPeripheralMode;
  final bool supportsManufacturerDataInAdvertisement;
  final bool supportsManufacturerDataInScanResponse;
  final bool supportsServiceDataInAdvertisement;
  final bool supportsServiceDataInScanResponse;
  final bool supportsTargetedCharacteristicUpdate;
  final bool supportsAdvertisingTimeout;

  const BlePeripheralCapabilities({
    required this.supportsPeripheralMode,
    required this.supportsManufacturerDataInAdvertisement,
    required this.supportsManufacturerDataInScanResponse,
    required this.supportsServiceDataInAdvertisement,
    required this.supportsServiceDataInScanResponse,
    required this.supportsTargetedCharacteristicUpdate,
    required this.supportsAdvertisingTimeout,
  });
}
