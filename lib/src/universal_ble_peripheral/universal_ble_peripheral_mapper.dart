import 'package:universal_ble/src/universal_ble_peripheral/generated/universal_ble_peripheral.g.dart'
    as pigeon;
import 'package:universal_ble/universal_ble.dart';

class UniversalBlePeripheralMapper {
  static pigeon.PeripheralService toPigeonService(
    BleService service, {
    required bool primary,
  }) {
    return pigeon.PeripheralService(
      uuid: BleUuidParser.string(service.uuid),
      primary: primary,
      characteristics: service.characteristics
          .map(
            (c) => pigeon.PeripheralCharacteristic(
              uuid: BleUuidParser.string(c.uuid),
              properties: c.properties.map((e) => e.index).toList(),
              // Attribute permissions are peripheral-only and optional.
              permissions: const <int>[],
              descriptors: c.descriptors
                  .map(
                    (d) => pigeon.PeripheralDescriptor(
                      uuid: BleUuidParser.string(d.uuid),
                      value: null,
                      permissions: const <int>[],
                    ),
                  )
                  .toList(),
              value: null,
            ),
          )
          .toList(),
    );
  }

  static pigeon.PeripheralManufacturerData? toPigeonManufacturerData(
    ManufacturerData? manufacturerData,
  ) {
    if (manufacturerData == null) return null;
    return pigeon.PeripheralManufacturerData(
      manufacturerId: manufacturerData.companyId,
      data: manufacturerData.payload,
    );
  }

  static PeripheralBondState fromPigeonBondState(pigeon.PeripheralBondState s) {
    return switch (s) {
      pigeon.PeripheralBondState.bonding => PeripheralBondState.bonding,
      pigeon.PeripheralBondState.bonded => PeripheralBondState.bonded,
      pigeon.PeripheralBondState.none => PeripheralBondState.none,
    };
  }
}
