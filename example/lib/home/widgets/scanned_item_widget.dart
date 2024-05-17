import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:universal_ble_example/data/capabilities.dart';

class ScannedItemWidget extends StatelessWidget {
  final BleScanResult scanResult;
  final VoidCallback? onTap;
  const ScannedItemWidget({super.key, required this.scanResult, this.onTap});

  @override
  Widget build(BuildContext context) {
    String? name = scanResult.name;
    Uint8List? rawManufacturerData = scanResult.manufacturerData;
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
            '$name (${scanResult.rssi})',
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(scanResult.deviceId),
              Visibility(
                visible: manufacturerData != null,
                child: Text(
                  Platform.isWeb || Platform.isDesktop
                      ? manufacturerData.toString()
                      : 'ManufacturerCompanyId: ${manufacturerData?.companyIdRadix16}',
                ),
              ),
              Visibility(
                visible: scanResult.isPaired != null,
                child: scanResult.isPaired == true
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
