import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:universal_ble_example/data/company_identifier_service.dart';

class ScanFilterWidget extends StatefulWidget {
  final void Function(ScanFilter? filter) onScanFilter;
  final TextEditingController servicesFilterController;
  final TextEditingController namePrefixController;
  final TextEditingController manufacturerDataController;

  const ScanFilterWidget({
    super.key,
    required this.onScanFilter,
    required this.servicesFilterController,
    required this.namePrefixController,
    required this.manufacturerDataController,
  });

  @override
  State<ScanFilterWidget> createState() => _ScanFilterWidgetState();
}

class _ScanFilterWidgetState extends State<ScanFilterWidget> {
  String? error;

  void applyFilter() async {
    setState(() {
      error = null;
    });
    try {
      // Ensure company identifier service is loaded
      await CompanyIdentifierService.instance.load();
      List<String> serviceUUids = [];
      List<String> namePrefixes = [];
      List<ManufacturerDataFilter> manufacturerDataFilters = [];

      // Parse Services - handle both comma and newline separated
      if (widget.servicesFilterController.text.isNotEmpty) {
        List<String> services = widget.servicesFilterController.text
            .split(',')
            .map((e) => e.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        for (String service in services) {
          try {
            serviceUUids.add(BleUuidParser.string(service.trim()));
          } on FormatException catch (_) {
            throw Exception("Invalid Service UUID $service");
          }
        }
      }

      // Parse Name Prefix - handle both comma and newline separated
      String namePrefix = widget.namePrefixController.text;
      if (namePrefix.isNotEmpty) {
        namePrefixes = namePrefix.split(',').map((e) => e.trim()).toList();
      }

      // Parse Manufacturer Data - handle both comma and newline separated
      String manufacturerDataText = widget.manufacturerDataController.text;
      if (manufacturerDataText.isNotEmpty) {
        final companyService = CompanyIdentifierService.instance;
        List<String> manufacturerData = manufacturerDataText
            .split(',')
            .map((e) => e.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        for (String manufacturer in manufacturerData) {
          final companyIdentifier = companyService.parseCompanyIdentifier(manufacturer);

          if (companyIdentifier == null) {
            throw Exception(
                "Invalid Manufacturer Data or Company Name: $manufacturer");
          }
          manufacturerDataFilters.add(
              ManufacturerDataFilter(companyIdentifier: companyIdentifier));
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
            withManufacturerData: manufacturerDataFilters,
          ),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Filters Applied")),
          );
        }
      }
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() {
        error = e.toString();
      });
    }
  }

  void clearFilter() {
    widget.servicesFilterController.clear();
    widget.namePrefixController.clear();
    widget.manufacturerDataController.clear();
    widget.onScanFilter(null);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Icon(
                      Icons.filter_list,
                      color: colorScheme.primary,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "Scan Filters",
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                      tooltip: 'Close',
                    ),
                  ],
                ),
                Text(
                  "Filter devices by name, services, or manufacturer data. Enter multiple values separated by commas.",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 8),
                if (error != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: colorScheme.error.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: colorScheme.error,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            error!,
                            style: TextStyle(
                              color: colorScheme.onErrorContainer,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Name Prefix Filter
                _buildFilterCard(
                  context: context,
                  title: "Name Prefixes",
                  icon: Icons.text_fields,
                  controller: widget.namePrefixController,
                  hintText: "e.g. MyDevice Sensor",
                  helperText: "Device names starting with these prefixes",
                ),
                const SizedBox(height: 16),
                // Services Filter
                _buildFilterCard(
                  context: context,
                  title: "Service UUIDs",
                  maxLines: 3,
                  icon: Icons.apps,
                  controller: widget.servicesFilterController,
                  hintText: "e.g. 0000180f-0000-1000-8000-00805f9b34fb,180F",
                  helperText: "Service UUIDs (16-bit, 32-bit, or 128-bit)",
                ),
                const SizedBox(height: 16),
                // Manufacturer Data Filter
                _buildFilterCard(
                  context: context,
                  title: "Manufacturer Company IDs",
                  icon: Icons.business,
                  controller: widget.manufacturerDataController,
                  hintText: "e.g. 76,0x004C,Apple Inc.",
                  helperText:
                      "Company identifiers (decimal/hex) or company names",
                ),
                const SizedBox(height: 24),
                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: OutlinedButton.icon(
                        onPressed: clearFilter,
                        icon: const Icon(Icons.clear_all),
                        label: const Text('Clear All'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colorScheme.onSurface,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      flex: 3,
                      child: ElevatedButton.icon(
                        onPressed: applyFilter,
                        icon: const Icon(Icons.check),
                        label: const Text('Apply Filters'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    required TextEditingController controller,
    required String hintText,
    required String helperText,
    int maxLines = 2,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            TextFormField(
              controller: controller,
              maxLines: maxLines,
              style: const TextStyle(fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: hintText,
                helperText: helperText,
                helperMaxLines: 2,
                helperStyle: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: colorScheme.outline.withValues(alpha: 0.5),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: colorScheme.outline.withValues(alpha: 0.3),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: colorScheme.primary,
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor:
                    colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
