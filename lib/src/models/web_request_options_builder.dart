import 'dart:typed_data';
import 'package:flutter_web_bluetooth/flutter_web_bluetooth.dart';
import 'package:universal_ble/universal_ble.dart';

class WebRequestOptionsBuilder {
  final bool _acceptAllDevices;
  final List<WebRequestFilterBuilder> _requestFilters;
  final List<WebRequestFilterBuilder>? _exclusionFilters;
  List<String>? _optionalServices;

  WebRequestOptionsBuilder(
    List<WebRequestFilterBuilder> requestFilters, {
    List<WebRequestFilterBuilder>? exclusionFilters,
    List<String>? optionalServices,
  })  : _optionalServices = optionalServices,
        _requestFilters = requestFilters,
        _exclusionFilters = exclusionFilters,
        _acceptAllDevices = false {
    if (_requestFilters.isEmpty) {
      throw StateError(
        'No filters have been set, consider using '
        'RequestOptionsBuilder.acceptAllDevices() instead.',
      );
    }
  }

  /// To accept all devices
  WebRequestOptionsBuilder.acceptAllDevices({
    List<String>? optionalServices,
  })  : _optionalServices = optionalServices,
        _acceptAllDevices = true,
        _requestFilters = [],
        _exclusionFilters = null;

  /// For internal use
  /// To convert UniversalBleRequestOptions to FlutterWebBluetoothRequestOptions
  RequestOptionsBuilder toRequestOptionsBuilder({ScanFilter? scanFilter}) {
    if (scanFilter != null) _applyScanFilter(scanFilter);

    if (_acceptAllDevices) {
      return RequestOptionsBuilder.acceptAllDevices(
        optionalServices: _optionalServices,
      );
    }

    return RequestOptionsBuilder(
      _requestFilters.map((e) => e.getRequestFilterBuilder()).toList(),
      exclusionFilters:
          _exclusionFilters?.map((e) => e.getRequestFilterBuilder()).toList(),
      optionalServices: _optionalServices,
    );
  }

  /// To apply scan filter
  void _applyScanFilter(ScanFilter scanFilter) {
    List<String> filterServices = scanFilter.withServices;
    _optionalServices ??= filterServices.toValidUUIDList();

    for (var requestFilter in _requestFilters) {
      // Apply services filter
      requestFilter.services ??= filterServices.toValidUUIDList();
    }
  }

  /// List of common services
  static List<String> get defaultServices {
    return BluetoothDefaultServiceUUIDS.values
        .map((e) => e.uuid.toString())
        .toList();
  }

  /// List of common services in 16 bit
  static List<String> get defaultServices16Bit {
    return BluetoothDefaultServiceUUIDS.values
        .map((e) => e.uuid16.toString())
        .toList();
  }
}

/// To filter by name, namePrefix, services, manufacturerData
class WebRequestFilterBuilder {
  String? name;
  String? namePrefix;
  List<String>? services;
  List<WebManufacturerDataFilterBuilder>? manufacturerData;

  WebRequestFilterBuilder({
    this.name,
    this.namePrefix,
    this.services,
    this.manufacturerData,
  });

  RequestFilterBuilder getRequestFilterBuilder() {
    return RequestFilterBuilder(
      name: name,
      namePrefix: namePrefix,
      services: services,
      manufacturerData: manufacturerData
          ?.map((e) => e.getManufacturerDataFilterBuilder())
          .toList(),
    );
  }
}

/// To filter by manufacturer data
class WebManufacturerDataFilterBuilder {
  int? companyIdentifier;
  Uint8List? dataPrefix;
  Uint8List? mask;
  WebManufacturerDataFilterBuilder({
    this.companyIdentifier,
    this.dataPrefix,
    this.mask,
  });

  ManufacturerDataFilterBuilder getManufacturerDataFilterBuilder() {
    return ManufacturerDataFilterBuilder(
      companyIdentifier: companyIdentifier,
      dataPrefix: dataPrefix,
      mask: mask,
    );
  }
}
