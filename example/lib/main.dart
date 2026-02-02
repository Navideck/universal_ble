import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:universal_ble_example/universal_ble_app.dart';

void main() async {
  // Initialize port for communication between TaskHandler and UI
  FlutterForegroundTask.initCommunicationPort();

  bool hasPermission = await initializeApp();
  runApp(UniversalBleApp(hasPermission: hasPermission));
}
