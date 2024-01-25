import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';

class ScannedItemWidget extends StatelessWidget {
  final BleScanResult scanResult;
  final VoidCallback? onTap;
  const ScannedItemWidget({super.key, required this.scanResult, this.onTap});

  @override
  Widget build(BuildContext context) {
    String? name = scanResult.name;
    if (name == null || name.isEmpty) name = 'NA';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Card(
        child: ListTile(
          title: Text(
            '$name (${scanResult.rssi})',
          ),
          subtitle: scanResult.isPaired != null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("${scanResult.deviceId} "),
                    scanResult.isPaired == true
                        ? const Text(
                            "Paired",
                            style: TextStyle(color: Colors.green),
                          )
                        : const Text(
                            "Not Paired",
                            style: TextStyle(color: Colors.red),
                          ),
                  ],
                )
              : Text(scanResult.deviceId),
          trailing: const Icon(Icons.arrow_forward_ios),
          onTap: onTap,
        ),
      ),
    );
  }
}
