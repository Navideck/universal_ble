import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:universal_ble_example/data/storage_service.dart';
import 'package:universal_ble_example/home/home.dart';
import 'package:universal_ble_example/home/permission_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageService.instance.init();
  bool hasPermission = await UniversalBle.hasPermissions(
    withAndroidFineLocation: false,
  );

  runApp(
    MaterialApp(
      title: 'Universal BLE',
      debugShowCheckedModeBanner: false,
      darkTheme: ThemeData.dark(),
      themeMode: ThemeMode.system,
      home: hasPermission ? const Home() : const PermissionScreen(),
    ),
  );
}
