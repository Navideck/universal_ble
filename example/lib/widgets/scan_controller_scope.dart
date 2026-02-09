import 'package:flutter/material.dart';
import 'package:universal_ble_example/data/scan_controller.dart';

/// Provides [ScanController] to the widget tree so the scan button
/// can be shown on both the scanner and detail screens.
class ScanControllerScope extends InheritedWidget {
  const ScanControllerScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final ScanController controller;

  static ScanController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ScanControllerScope>();
    assert(scope != null, 'No ScanControllerScope found in context');
    return scope!.controller;
  }

  @override
  bool updateShouldNotify(ScanControllerScope oldWidget) {
    return controller != oldWidget.controller;
  }
}
