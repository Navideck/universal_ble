import 'package:flutter/services.dart';

class ConnectionException implements Exception {
  late String message;

  ConnectionException([dynamic error]) {
    message = _errorParser(error);
  }

  @override
  String toString() => message;
}

class PairingException implements Exception {
  late String message;

  PairingException([dynamic error]) {
    message = _errorParser(error);
  }

  @override
  String toString() => message;
}

class WebBluetoothGloballyDisabled implements Exception {
  String message;
  WebBluetoothGloballyDisabled(this.message);

  @override
  String toString() => message;
}

class NotFoundException implements Exception {}

class ServiceNotFoundException implements NotFoundException {
  String message;
  ServiceNotFoundException(this.message);

  @override
  String toString() => message;
}

class CharacteristicNotFoundException implements NotFoundException {
  String message;
  CharacteristicNotFoundException(this.message);

  @override
  String toString() => message;
}

String _errorParser(dynamic error) {
  if (error == null) {
    return "Failed";
  } else if (error is PlatformException) {
    return error.message ?? error.details ?? error.code;
  } else if (error is String) {
    return error;
  } else {
    return error.toString();
  }
}
