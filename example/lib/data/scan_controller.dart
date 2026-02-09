import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:universal_ble_example/data/company_identifier_service.dart';

/// Shared controller for BLE scan state so the scan button can be shown
/// on both the scanner screen and the peripheral detail screen.
class ScanController extends ChangeNotifier {
  bool _isScanning = false;
  bool get isScanning => _isScanning;

  /// Syncs [isScanning] with the actual native state (e.g. after app restart).
  Future<void> syncState() async {
    final value = await UniversalBle.isScanning();
    if (_isScanning != value) {
      _isScanning = value;
      notifyListeners();
    }
  }

  Future<void> startScan() async {
    if (_isScanning) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final filter = await _loadFilterFromPrefs(prefs);
      final platformConfig = _loadPlatformConfigFromPrefs(prefs);

      await UniversalBle.startScan(
        scanFilter: filter,
        platformConfig: platformConfig,
      );
      _isScanning = true;
      notifyListeners();
    } catch (e) {
      _isScanning = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> stopScan() async {
    if (!_isScanning) return;
    try {
      await UniversalBle.stopScan();
      _isScanning = false;
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  Future<ScanFilter?> _loadFilterFromPrefs(SharedPreferences prefs) async {
    final services = prefs.getString('scan_filter_services') ?? '';
    final namePrefix = prefs.getString('scan_filter_name_prefix') ?? '';
    final manufacturerData =
        prefs.getString('scan_filter_manufacturer_data') ?? '';

    if (services.isEmpty &&
        namePrefix.isEmpty &&
        manufacturerData.isEmpty) {
      return null;
    }

    await CompanyIdentifierService.instance.load();

    final serviceUUids = <String>[];
    if (services.isNotEmpty) {
      for (final s in services.split(',').map((e) => e.trim())) {
        if (s.isEmpty) continue;
        try {
          serviceUUids.add(BleUuidParser.string(s));
        } on FormatException catch (_) {
          continue;
        }
      }
    }

    final namePrefixes = namePrefix.isEmpty
        ? <String>[]
        : namePrefix.split(',').map((e) => e.trim()).toList();

    final manufacturerDataFilters = <ManufacturerDataFilter>[];
    if (manufacturerData.isNotEmpty) {
      final companyService = CompanyIdentifierService.instance;
      for (final s in manufacturerData
          .split(',')
          .map((e) => e.trim())
          .where((s) => s.isNotEmpty)) {
        final id = companyService.parseCompanyIdentifier(s);
        if (id != null) {
          manufacturerDataFilters.add(ManufacturerDataFilter(
            companyIdentifier: id,
          ));
        }
      }
    }

    if (serviceUUids.isEmpty &&
        namePrefixes.isEmpty &&
        manufacturerDataFilters.isEmpty) {
      return null;
    }

    return ScanFilter(
      withServices: serviceUUids,
      withNamePrefix: namePrefixes,
      withManufacturerData: manufacturerDataFilters,
    );
  }

  PlatformConfig _loadPlatformConfigFromPrefs(SharedPreferences prefs) {
    WebOptions? web;
    if (kIsWeb) {
      final webServices = prefs.getString('scan_filter_web_services') ?? '';
      if (webServices.isNotEmpty) {
        final list = webServices
            .split(',')
            .where((s) => s.trim().isNotEmpty)
            .map((s) {
          try {
            return BleUuidParser.string(s.trim());
          } catch (_) {
            return s.trim();
          }
        }).toList();
        web = WebOptions(optionalServices: list);
      }
    }
    return PlatformConfig(
      android: AndroidOptions(scanMode: AndroidScanMode.lowLatency),
      web: web,
    );
  }
}
