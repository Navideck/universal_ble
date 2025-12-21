import 'package:flutter/material.dart';
import 'package:universal_ble_example/universal_ble_app.dart';

void main() async {
  bool hasPermission = await initializeApp();
  runApp(UniversalBleApp(hasPermission: hasPermission));
}
