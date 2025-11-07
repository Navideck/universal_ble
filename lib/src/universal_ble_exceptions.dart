import 'package:flutter/services.dart';
import 'package:universal_ble/src/universal_ble_pigeon/universal_ble.g.dart';
import 'package:universal_ble/src/utils/error_mapper.dart';

/// Base exception class for all BLE errors with typed error codes
abstract class UniversalBleException implements Exception {
  /// The unified error code
  final UniversalBleErrorCode code;

  /// Human-readable error message
  final String message;

  /// Platform-specific error details (if available)
  final dynamic details;

  UniversalBleException({
    required this.code,
    required this.message,
    this.details,
  });

  @override
  String toString() => message;

  /// Creates an exception from a PlatformException
  /// For Pigeon-based platforms, the error code should be in details as UniversalBleErrorCode
  factory UniversalBleException.fromPlatformException(
    PlatformException error,
  ) {
    UniversalBleErrorCode errorCode;

    int? errorCodeInt = int.tryParse(error.code);
    if (errorCodeInt != null) {
      errorCode = UniversalBleErrorCode.values[errorCodeInt];
    } else if (error.details is int) {
      try {
        errorCode = UniversalBleErrorCode.values[error.details as int];
      } catch (e) {
        errorCode = ErrorMapper.fromPlatformException(error);
      }
    }
    // TODO: improve this
    else {
      // Fallback to parsing for non-Pigeon platforms (Linux, Web)
      errorCode = ErrorMapper.fromPlatformException(error);
    }

    final message = error.message ?? (error.details?.toString()) ?? error.code;
    return _createExceptionFromCode(
      errorCode,
      message,
      error.details,
    );
  }

  /// Creates an exception from an error code and message
  factory UniversalBleException.fromErrorCode(
    UniversalBleErrorCode code,
    String message, {
    dynamic details,
  }) {
    return _createExceptionFromCode(code, message, details);
  }

  /// Creates an exception from a dynamic error
  factory UniversalBleException.fromError(dynamic error) {
    if (error is PlatformException) {
      return UniversalBleException.fromPlatformException(error);
    } else if (error is UniversalBleException) {
      return error;
    } else if (error is String) {
      final code = ErrorMapper.fromStringCode(error);
      return _createExceptionFromCode(code, error, null);
    } else {
      return _createExceptionFromCode(
        UniversalBleErrorCode.unknownError,
        error?.toString() ?? 'Unknown error',
        error,
      );
    }
  }

  static UniversalBleException _createExceptionFromCode(
    UniversalBleErrorCode code,
    String message,
    dynamic details,
  ) {
    // Route to specific exception types based on error code
    switch (code) {
      case UniversalBleErrorCode.deviceDisconnected:
      case UniversalBleErrorCode.connectionTimeout:
      case UniversalBleErrorCode.connectionFailed:
      case UniversalBleErrorCode.connectionRejected:
      case UniversalBleErrorCode.connectionTerminated:
      case UniversalBleErrorCode.connectionInProgress:
        return ConnectionException._(
          code: code,
          message: message,
          details: details,
        );

      case UniversalBleErrorCode.notPaired:
      case UniversalBleErrorCode.notPairable:
      case UniversalBleErrorCode.alreadyPaired:
      case UniversalBleErrorCode.pairingFailed:
      case UniversalBleErrorCode.pairingCancelled:
      case UniversalBleErrorCode.pairingTimeout:
      case UniversalBleErrorCode.pairingNotAllowed:
      case UniversalBleErrorCode.authenticationFailure:
      // case UniversalBleErrorCode.authenticationTimeout:
      // case UniversalBleErrorCode.authenticationNotAllowed:
      case UniversalBleErrorCode.unpairingFailed:
      case UniversalBleErrorCode.alreadyUnpaired:
        return PairingException._(
          code: code,
          message: message,
          details: details,
        );

      case UniversalBleErrorCode.serviceNotFound:
        return ServiceNotFoundException(
          code: code,
          message: message,
          details: details,
        );

      case UniversalBleErrorCode.characteristicNotFound:
        return CharacteristicNotFoundException(
          code: code,
          message: message,
          details: details,
        );

      case UniversalBleErrorCode.webBluetoothGloballyDisabled:
        return WebBluetoothGloballyDisabled._(
          code: code,
          message: message,
          details: details,
        );

      default:
        return UniversalBleExceptionImpl(
          code: code,
          message: message,
          details: details,
        );
    }
  }
}

/// Generic BLE exception implementation
class UniversalBleExceptionImpl extends UniversalBleException {
  UniversalBleExceptionImpl({
    required super.code,
    required super.message,
    super.details,
  });
}

/// Exception thrown when connection-related errors occur
class ConnectionException extends UniversalBleException {
  ConnectionException._({
    required super.code,
    required super.message,
    super.details,
  });

  /// Legacy constructor for backward compatibility
  ConnectionException([dynamic error])
      : this._(
          code: error is PlatformException
              ? ErrorMapper.fromPlatformException(error)
              : ErrorMapper.fromStringCode(
                  error?.toString() ?? 'Failed',
                  message: error?.toString(),
                ),
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
          code: error is PlatformException
              ? ErrorMapper.fromPlatformException(error)
              : ErrorMapper.fromStringCode(
                  error?.toString() ?? 'Failed',
                  message: error?.toString(),
                ),
          message: _errorParser(error),
          details: error,
        );
}

/// Exception thrown when Web Bluetooth API is globally disabled
class WebBluetoothGloballyDisabled extends UniversalBleException {
  WebBluetoothGloballyDisabled._({
    required super.code,
    required super.message,
    super.details,
  });

  /// Legacy constructor for backward compatibility
  WebBluetoothGloballyDisabled(String message)
      : this._(
          code: UniversalBleErrorCode.webBluetoothGloballyDisabled,
          message: message,
        );
}

/// Base exception for not found errors
abstract class NotFoundException extends UniversalBleException {
  NotFoundException({
    required super.code,
    required super.message,
    super.details,
  });
}

/// Exception thrown when a service is not found
class ServiceNotFoundException extends NotFoundException {
  ServiceNotFoundException({
    required super.code,
    required super.message,
    super.details,
  });

  /// Legacy constructor for backward compatibility
  ServiceNotFoundException.fromMessage(String message)
      : this(
          code: UniversalBleErrorCode.serviceNotFound,
          message: message,
        );
}

/// Exception thrown when a characteristic is not found
class CharacteristicNotFoundException extends NotFoundException {
  CharacteristicNotFoundException({
    required super.code,
    required super.message,
    super.details,
  });

  /// Legacy constructor for backward compatibility
  CharacteristicNotFoundException.fromMessage(String message)
      : this(
          code: UniversalBleErrorCode.characteristicNotFound,
          message: message,
        );
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
