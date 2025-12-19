import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:universal_ble_example/data/storage_service.dart';
import 'package:universal_ble_example/home/permission_screen.dart';
import 'package:universal_ble_example/home/scanner_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageService.instance.init();
  // await UniversalBle.setLogLevel(BleLogLevel.verbose);
  bool hasPermission = await UniversalBle.hasPermissions(
    withAndroidFineLocation: false,
  );

  runApp(MyApp(
    hasPermission: hasPermission,
  ));
}

class MyApp extends StatelessWidget {
  final bool hasPermission;
  const MyApp({super.key, required this.hasPermission});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Universal BLE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,
      home: hasPermission ? ScannerScreen() : const PermissionScreen(),
    );
  }
}
