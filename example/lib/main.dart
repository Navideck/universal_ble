import 'package:flutter/material.dart';
import 'package:universal_ble_example/data/scan_controller.dart';
import 'package:universal_ble_example/universal_ble_app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  bool hasPermission = await initializeApp();
  final scanController = ScanController();
  await scanController.syncState();
  runApp(UniversalBleApp(
    hasPermission: hasPermission,
    scanController: scanController,
  ));
}
