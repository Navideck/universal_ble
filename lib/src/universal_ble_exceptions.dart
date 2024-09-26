import 'package:flutter/services.dart';

class ConnectionException implements Exception {
  late String message;

  ConnectionException([dynamic error]) {
    message = _errorParser(error);
  }

  @override
  String toString() => message;
}

class PairException implements Exception {
  late String message;

  PairException([dynamic error]) {
    message = _errorParser(error);
  }

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
