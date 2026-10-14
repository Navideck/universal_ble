import 'package:universal_ble/universal_ble.dart';

/// Extension methods for [BleService] objects.
extension BleServiceExtension on BleService {
  /// Retrieves a [BleCharacteristic] from the service by its UUID.
  ///
  /// Throws an error if no characteristics are found or if the characteristic
  /// with the given UUID is not available.
  BleCharacteristic getCharacteristic(String characteristicId) {
    if (characteristics.isEmpty) {
      throw UniversalBleException(
        code: UniversalBleErrorCode.characteristicNotFound,
        message: 'No characteristics found',
      );
    }
    return characteristics.firstWhere(
      (c) => BleUuidParser.compareStrings(c.uuid, characteristicId),
      orElse: () => throw UniversalBleException(
        code: UniversalBleErrorCode.characteristicNotFound,
        message: 'Characteristic "$characteristicId" not available',
      ),
    );
  }
}
