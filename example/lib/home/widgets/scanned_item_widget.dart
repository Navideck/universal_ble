import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:universal_ble_example/home/widgets/rssi_signal_indicator.dart';

class ScannedItemWidget extends StatelessWidget {
  final BleDevice bleDevice;
  final VoidCallback? onTap;
  const ScannedItemWidget({super.key, required this.bleDevice, this.onTap});

  @override
  Widget build(BuildContext context) {
    String? name = bleDevice.name;
    List<ManufacturerData> rawManufacturerData = bleDevice.manufacturerDataList;
    if (name == null || name.isEmpty) name = 'N/A';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Card(
        child: ListTile(
          leading: RssiSignalIndicator(rssi: bleDevice.rssi ?? 0),
          title: Text(name),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(bleDevice.deviceId),
              if (rawManufacturerData.isNotEmpty)
                ...rawManufacturerData.map(
                  (data) => Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      'Manufacturer: ${data.companyIdRadix16}-${data.payloadHex}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              if (bleDevice.services.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Advertised Services:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      ...bleDevice.services.map(
                        (service) => Text(
                          '  • $service',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              bleDevice.paired == true
                  ? const Text("Paired", style: TextStyle(color: Colors.green))
                  : const Text(
                      "Not Paired",
                      style: TextStyle(color: Colors.red),
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
