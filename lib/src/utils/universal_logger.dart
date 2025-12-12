import 'dart:developer';
import 'package:universal_ble/src/models/ble_log_level.dart';

class UniversalLogger {
  static BleLogLevel _currentLogLevel = BleLogLevel.none;

  static BleLogLevel get currentLogLevel => _currentLogLevel;

  static void setLogLevel(BleLogLevel logLevel) {
    _currentLogLevel = logLevel;
  }

  static void logError(
    String message, {
    bool withTimestamp = false,
  }) {
    if (!_allows(BleLogLevel.error)) return;
    if (withTimestamp) {
      final ts = DateTime.now().toIso8601String();
      message = "[$ts] $message";
    }
    log(
      '\x1B[31m$message\x1B[0m',
      name: 'UniversalBle:ERROR',
    );
  }

  static void logWarning(String message, {bool withTimestamp = false}) {
    if (!_allows(BleLogLevel.warning)) return;
    if (withTimestamp) {
      final ts = DateTime.now().toIso8601String();
      message = "[$ts] $message";
    }
    log(
      '\x1B[33m$message\x1B[0m',
      name: 'UniversalBle:WARN',
    );
  }

  static void logInfo(String message, {bool withTimestamp = false}) {
    if (!_allows(BleLogLevel.info)) return;
    if (withTimestamp) {
      final ts = DateTime.now().toIso8601String();
      message = "[$ts] $message";
    }
    log(
      message.toString(),
      name: 'UniversalBle:INFO',
    );
  }

  static void logDebug(String message, {bool withTimestamp = false}) {
    if (!_allows(BleLogLevel.debug)) return;
    if (withTimestamp) {
      final ts = DateTime.now().toIso8601String();
      message = "[$ts] $message";
    }
    log(
      message.toString(),
      name: 'UniversalBle:DEBUG',
    );
  }

  static void logVerbose(String message, {bool withTimestamp = false}) {
    if (!_allows(BleLogLevel.verbose)) return;
    if (withTimestamp) {
      final ts = DateTime.now().toIso8601String();
      message = "[$ts] $message";
    }
    log(
      message.toString(),
      name: 'UniversalBle:VERBOSE',
    );
  }

  static bool _allows(BleLogLevel level) {
    return level.index <= _currentLogLevel.index &&
        _currentLogLevel != BleLogLevel.none;
  }
}
