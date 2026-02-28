import 'package:flutter/services.dart';
import 'package:universal_ble/src/universal_ble_pigeon/universal_ble.g.dart';
import 'package:universal_ble/src/utils/universal_ble_error_parser.dart';

/// Base exception class for all BLE errors with typed error codes
class UniversalBleException implements Exception {
  final UniversalBleErrorCode code;
  final String message;
  final dynamic details;

  UniversalBleException({
    required this.code,
    required this.message,
    this.details,
  });

  @override
  String toString() =>
      "UniversalBleException: Code: $code, Message: $message, Details: $details";

  factory UniversalBleException.fromError(dynamic error) {
    String message = error.toString();
    dynamic details = error;
    if (error is PlatformException) {
      message = error.message ?? error.details?.toString() ?? error.code;
      details = error.details;
    }
    return UniversalBleException(
      code: UniversalBleErrorParser.getCode(error),
      message: message,
      details: details,
    );
  }
}

/// Exception thrown when connection-related errors occur
class ConnectionException extends UniversalBleException {
  ConnectionException._({
    required super.code,
    required super.message,
    super.details,
  });

  ConnectionException([dynamic error])
    : this._(
        code: UniversalBleErrorParser.getCode(error),
        message: _errorParser(error),
        details: error,
      );
}

/// Exception thrown when pairing-related errors occur
class PairingException extends UniversalBleException {
  PairingException._({
    required super.code,
    required super.message,
    super.details,
  });

  /// Legacy constructor for backward compatibility
  PairingException([dynamic error])
    : this._(
        code: UniversalBleErrorParser.getCode(error),
        message: _errorParser(error),
        details: error,
      );
}

/// Exception thrown when Web Bluetooth API is globally disabled
class WebBluetoothGloballyDisabled extends UniversalBleException {
  WebBluetoothGloballyDisabled({
    super.code = UniversalBleErrorCode.webBluetoothGloballyDisabled,
    required super.message,
    super.details,
  });
}

/// Legacy error parser for backward compatibility
String _errorParser(dynamic error) {
  if (error == null) {
    return "Failed";
  } else if (error is PlatformException) {
    return error.message ?? error.details ?? error.code ?? 'Unknown error';
  } else if (error is String) {
    return error;
  } else {
    return error.toString();
  }
}
