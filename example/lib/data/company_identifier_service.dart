import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';

/// Service for loading and querying company identifiers from YAML file
class CompanyIdentifierService {
  static CompanyIdentifierService? _instance;
  static CompanyIdentifierService get instance {
    _instance ??= CompanyIdentifierService._();
    return _instance!;
  }

  CompanyIdentifierService._();

  Map<int, String>? _companyIdToName;
  Map<String, int>? _companyNameToId;
  bool _isLoading = false;
  bool _isLoaded = false;

  /// Load company identifiers from YAML file
  Future<void> load() async {
    if (_isLoaded || _isLoading) return;
    _isLoading = true;

    try {
      final String yamlString =
          await rootBundle.loadString('lib/company_identifiers.yaml');
      final YamlMap yaml = loadYaml(yamlString) as YamlMap;
      final YamlList? companyIdentifiers =
          yaml['company_identifiers'] as YamlList?;

      if (companyIdentifiers == null) {
        _companyIdToName = {};
        _companyNameToId = {};
        _isLoaded = true;
        _isLoading = false;
        return;
      }

      _companyIdToName = {};
      _companyNameToId = {};

      for (var entry in companyIdentifiers) {
        if (entry is! YamlMap) continue;

        final value = entry['value'];
        final name = entry['name'];

        if (value == null || name == null) continue;

        // Parse hex value (format: "0x1053" or "0x004C")
        int? companyId;
        if (value is String) {
          final trimmed = value.trim();
          if (trimmed.toLowerCase().startsWith('0x')) {
            companyId = int.tryParse(trimmed.substring(2), radix: 16);
          } else {
            companyId = int.tryParse(trimmed, radix: 16);
          }
        } else if (value is int) {
          companyId = value;
        }

        if (companyId != null && name is String) {
          _companyIdToName![companyId] = name;
          // Store case-insensitive lookup for company names
          _companyNameToId![name.toLowerCase()] = companyId;
        }
      }

      _isLoaded = true;
    } catch (e) {
      // If loading fails, initialize with empty maps
      _companyIdToName = {};
      _companyNameToId = {};
      _isLoaded = true;
    } finally {
      _isLoading = false;
    }
  }

  /// Get company name from company ID
  String? getCompanyName(int companyId) {
    if (!_isLoaded) {
      // Try to load synchronously if not loaded (shouldn't happen in practice)
      return null;
    }
    return _companyIdToName?[companyId];
  }

  /// Get company name from hex string (e.g., "0x1053" or "0x004C")
  String? getCompanyNameFromHex(String hexString) {
    final trimmed = hexString.trim();
    int? companyId;
    if (trimmed.toLowerCase().startsWith('0x')) {
      companyId = int.tryParse(trimmed.substring(2), radix: 16);
    } else {
      companyId = int.tryParse(trimmed, radix: 16);
    }
    if (companyId == null) return null;
    return getCompanyName(companyId);
  }

  /// Get company ID from company name (case-insensitive)
  int? getCompanyIdFromName(String companyName) {
    if (!_isLoaded) {
      return null;
    }
    return _companyNameToId?[companyName.toLowerCase()];
  }

  /// Get all company names (for filtering/searching)
  List<String> getAllCompanyNames() {
    if (!_isLoaded) {
      return [];
    }
    return _companyIdToName?.values.toList() ?? [];
  }

  /// Check if a string matches a company name (case-insensitive partial match)
  bool matchesCompanyName(String query) {
    if (!_isLoaded) {
      return false;
    }
    final lowerQuery = query.toLowerCase();
    return _companyNameToId?.keys.any((name) => name.contains(lowerQuery)) ??
        false;
  }

  /// Find company IDs that match a company name query (case-insensitive partial match)
  List<int> findCompanyIdsByName(String query) {
    if (!_isLoaded) {
      return [];
    }
    final lowerQuery = query.toLowerCase();
    return _companyNameToId?.entries
            .where((entry) => entry.key.contains(lowerQuery))
            .map((entry) => entry.value)
            .toList() ??
        [];
  }
}
