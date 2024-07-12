import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:universal_ble_example/widgets/platform_button.dart';

class ScanFilterTile extends StatefulWidget {
  final Function(ScanFilter? filter) onScanFilter;
  const ScanFilterTile({super.key, required this.onScanFilter});

  @override
  State<ScanFilterTile> createState() => _ScanFilterTileState();
}

class _ScanFilterTileState extends State<ScanFilterTile> {
  final ExpansionTileController tileController = ExpansionTileController();
  final servicesFilterController = TextEditingController();
  final namePrefixController = TextEditingController();
  final manufacturerDataController = TextEditingController();

  void applyFilter() {
    try {
      List<String> serviceUUids = [];
      List<String> namePrefixes = [];
      List<ManufacturerDataFilter> manufacturerDataFilters = [];

      // Parse Services
      if (servicesFilterController.text.isNotEmpty) {
        List<String> services = servicesFilterController.text.split(',');
        for (String service in services) {
          try {
            serviceUUids.add(BleUuid.parse(service));
          } on FormatException catch (_) {
            throw Exception("Invalid Service UUID $service");
          }
        }
      }

      // Parse Name Prefix
      String namePrefix = namePrefixController.text;
      if (namePrefix.isNotEmpty) {
        namePrefixes = namePrefix.split(',').map((e) => e.trim()).toList();
      }

      // Parse Manufacturer Data
      String manufacturerDataText = manufacturerDataController.text;
      if (manufacturerDataText.isNotEmpty) {
        List<String> manufacturerData = manufacturerDataText.split(',');
        for (String manufacturer in manufacturerData) {
          int? companyIdentifier = int.tryParse(manufacturer);
          if (companyIdentifier == null) {
            throw Exception("Invalid Manufacturer Data $manufacturer");
          }
          manufacturerDataFilters.add(
            ManufacturerDataFilter(companyIdentifier: companyIdentifier),
          );
        }
      }

      if (serviceUUids.isEmpty &&
          namePrefixes.isEmpty &&
          manufacturerDataFilters.isEmpty) {
        widget.onScanFilter(null);
      } else {
        widget.onScanFilter(
          ScanFilter(
            withServices: serviceUUids,
            withNamePrefix: namePrefixes,
          ),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Filters Applied")),
        );
      }
      tileController.collapse();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to apply filter: $e")),
      );
    }
  }

  void clearFilter() {
    servicesFilterController.clear();
    namePrefixController.clear();
    manufacturerDataController.clear();
    widget.onScanFilter(null);
    tileController.collapse();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            controller: tileController,
            title: const Text("Scan Filters"),
            children: [
              const SizedBox(height: 10),
              const Text(
                  "Add scan filters ( user comma to add multiple values )"),
              const SizedBox(height: 10),
              TextFormField(
                controller: servicesFilterController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: "Services",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: namePrefixController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: "Name Prefix's",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: manufacturerDataController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: "Manufacturer Data CompanyId's",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Expanded(
                    child: PlatformButton(
                      text: 'Apply',
                      onPressed: applyFilter,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: PlatformButton(
                      text: 'Clear',
                      onPressed: clearFilter,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}
