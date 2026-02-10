import 'dart:convert';

/// A saved scan filter preset (name + the three filter field values).
class SavedScanFilter {
  const SavedScanFilter({
    required this.name,
    required this.services,
    required this.namePrefix,
    required this.manufacturerData,
  });

  final String name;
  final String services;
  final String namePrefix;
  final String manufacturerData;

  Map<String, dynamic> toJson() => {
        'name': name,
        'services': services,
        'namePrefix': namePrefix,
        'manufacturerData': manufacturerData,
      };

  factory SavedScanFilter.fromJson(Map<String, dynamic> json) {
    return SavedScanFilter(
      name: json['name'] as String? ?? '',
      services: json['services'] as String? ?? '',
      namePrefix: json['namePrefix'] as String? ?? '',
      manufacturerData: json['manufacturerData'] as String? ?? '',
    );
  }

  static List<SavedScanFilter> fromJsonList(String? jsonString) {
    if (jsonString == null || jsonString.isEmpty) return [];
    try {
      final list = jsonDecode(jsonString) as List<dynamic>?;
      if (list == null) return [];
      return list
          .map((e) => SavedScanFilter.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static String toJsonList(List<SavedScanFilter> filters) {
    return jsonEncode(filters.map((e) => e.toJson()).toList());
  }

  SavedScanFilter copyWith({
    String? name,
    String? services,
    String? namePrefix,
    String? manufacturerData,
  }) {
    return SavedScanFilter(
      name: name ?? this.name,
      services: services ?? this.services,
      namePrefix: namePrefix ?? this.namePrefix,
      manufacturerData: manufacturerData ?? this.manufacturerData,
    );
  }
}
