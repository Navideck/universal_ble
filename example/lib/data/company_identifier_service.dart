import 'package:flutter/foundation.dart';
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

  final Map<int, String> _companyIdToName = {};
  final Map<String, int> _companyNameToId = {};
  bool _isLoading = false;
  bool _isLoaded = false;

  /// Parse company ID from a value (String hex or int)
  /// Supports formats: "0x1053", "0x004C", "1053", or integer value
  int? _parseCompanyId(dynamic value) {
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.toLowerCase().startsWith('0x')) {
        return int.tryParse(trimmed.substring(2), radix: 16);
      } else {
        return int.tryParse(trimmed, radix: 16);
      }
    } else if (value is int) {
      return value;
    }
    return null;
  }

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
        _companyIdToName.clear();
        _companyNameToId.clear();
        _isLoaded = true;
        _isLoading = false;
        return;
      }

      _companyIdToName.clear();
      _companyNameToId.clear();

      for (var entry in companyIdentifiers) {
        if (entry is! YamlMap) continue;

        final value = entry['value'];
        final name = entry['name'];

        if (value == null || name == null) continue;

        final companyId = _parseCompanyId(value);

        if (companyId != null && name is String) {
          _companyIdToName[companyId] = name;
          // Store case-insensitive lookup for company names
          _companyNameToId[name.toLowerCase()] = companyId;
        }
      }

      _isLoaded = true;
    } on PlatformException catch (e) {
      // Handle file loading errors (e.g., file not found, permission issues)
      debugPrint(
        'CompanyIdentifierService: Failed to load company identifiers file: ${e.message}',
      );
      _companyIdToName.clear();
      _companyNameToId.clear();
      _isLoaded = true;
    } on YamlException catch (e) {
      // Handle YAML parsing errors (e.g., invalid YAML syntax)
      debugPrint(
        'CompanyIdentifierService: Failed to parse YAML: ${e.message}',
      );
      _companyIdToName.clear();
      _companyNameToId.clear();
      _isLoaded = true;
    } catch (e, stackTrace) {
      // Handle any other unexpected errors
      debugPrint(
        'CompanyIdentifierService: Unexpected error loading company identifiers: $e',
      );
      debugPrint('Stack trace: $stackTrace');
      _companyIdToName.clear();
      _companyNameToId.clear();
      _isLoaded = true;
    } finally {
      _isLoading = false;
    }
  }

  /// Get company name from company ID
  String? getCompanyName(int companyId) {
    if (!_isLoaded) {
      // Data not loaded, return null. The `load` method should be called on app startup.
      return null;
    }
    return _companyIdToName[companyId];
  }

  /// Get company name from hex string (e.g., "0x1053" or "0x004C")
  String? getCompanyNameFromHex(String hexString) {
    final companyId = _parseCompanyId(hexString);
    if (companyId == null) return null;
    return getCompanyName(companyId);
  }

  /// Get company ID from company name (case-insensitive)
  int? getCompanyIdFromName(String companyName) {
    if (!_isLoaded) {
      return null;
    }
    return _companyNameToId[companyName.toLowerCase()];
  }

  /// Get all company names (for filtering/searching)
  List<String> getAllCompanyNames() {
    if (!_isLoaded) {
      return [];
    }
    return _companyIdToName.values.toList();
  }

  /// Check if a string matches a company name (case-insensitive partial match)
  bool matchesCompanyName(String query) {
    if (!_isLoaded) {
      return false;
    }
    final lowerQuery = query.toLowerCase();
    return _companyNameToId.keys.any((name) => name.contains(lowerQuery));
  }

  /// Find company IDs that match a company name query (case-insensitive partial match)
  List<int> findCompanyIdsByName(String query) {
    if (!_isLoaded) {
      return [];
    }
    final lowerQuery = query.toLowerCase();
    return _companyNameToId.entries
        .where((entry) => entry.key.contains(lowerQuery))
        .map((entry) => entry.value)
        .toList();
  }

  /// Parse a company identifier from a string (either by name or by ID)
  ///
  /// This method first tries to find the company by name (case-insensitive).
  /// If not found, it attempts to parse the string as a company ID:
  /// - Supports hex format with "0x" prefix (e.g., "0x004C")
  /// - Supports hex format without prefix if it contains hex characters (e.g., "4C")
  /// - Falls back to decimal parsing if no hex characters are present (e.g., "76")
  ///
  /// Returns the company ID if found/parsed successfully, null otherwise.
  int? parseCompanyIdentifier(String value) {
    final trimmed = value.trim();

    // First, try to find by company name (case-insensitive)
    final companyId = getCompanyIdFromName(trimmed);
    if (companyId != null) {
      return companyId;
    }

    // If not found by name, try parsing as company ID
    if (trimmed.toLowerCase().startsWith('0x')) {
      return int.tryParse(trimmed.substring(2), radix: 16);
    } else {
      // Try parsing as hex first (if it contains letters), then decimal
      if (trimmed.contains(RegExp(r'[a-fA-F]'))) {
        return int.tryParse(trimmed, radix: 16);
      } else {
        return int.tryParse(trimmed);
      }
    }
  }
}
