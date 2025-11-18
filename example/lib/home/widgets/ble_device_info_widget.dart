import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';

class BleDeviceInfoWidget extends StatelessWidget {
  final BleDevice bleDevice;
  const BleDeviceInfoWidget({super.key, required this.bleDevice});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText('Device ID: ${bleDevice.deviceId}'),
          SelectableText('Name: ${bleDevice.name ?? 'N/A'}'),
          SelectableText('RSSI: ${bleDevice.rssi}'),
          SelectableText('Paired: ${bleDevice.paired}'),
          SelectableText(
            'Services: ${bleDevice.services.isNotEmpty ? bleDevice.services.join(', ') : 'N/A'}',
          ),
          SelectableText(
            'Manufacturer Data: ${bleDevice.manufacturerDataList.isNotEmpty ? bleDevice.manufacturerDataList.map((e) => e.toString()).join(', ') : 'N/A'}',
          ),
        ],
      ),
    );
  }
}
