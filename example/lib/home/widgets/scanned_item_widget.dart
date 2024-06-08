import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:universal_ble_example/data/capabilities.dart';

class ScannedItemWidget extends StatelessWidget {
  final BleDevice bleDevice;
  final VoidCallback? onTap;
  const ScannedItemWidget({super.key, required this.bleDevice, this.onTap});

  @override
  Widget build(BuildContext context) {
    String? name = bleDevice.name;
    Uint8List? rawManufacturerData = bleDevice.manufacturerData;
    ManufacturerData? manufacturerData;
    if (rawManufacturerData != null && rawManufacturerData.isNotEmpty) {
      manufacturerData = ManufacturerData.fromData(rawManufacturerData);
    }
    if (name == null || name.isEmpty) name = 'NA';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Card(
        child: ListTile(
          title: Text(
            '$name (${bleDevice.rssi})',
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(bleDevice.deviceId),
              Visibility(
                visible: manufacturerData != null,
                child: Text(
                  Platform.isWeb || Platform.isDesktop
                      ? manufacturerData.toString()
                      : 'ManufacturerCompanyId: ${manufacturerData?.companyIdRadix16}',
                ),
              ),
              Visibility(
                visible: bleDevice.isPaired != null,
                child: bleDevice.isPaired == true
                    ? const Text(
                        "Paired",
                        style: TextStyle(color: Colors.green),
                      )
                    : const Text(
                        "Not Paired",
                        style: TextStyle(color: Colors.red),
                      ),
              ),
            ],
          ),
          trailing: const Icon(Icons.arrow_forward_ios),
          onTap: onTap,
        ),
      ),
    );
  }
}
