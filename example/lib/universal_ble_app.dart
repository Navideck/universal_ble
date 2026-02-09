import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:universal_ble_example/data/scan_controller.dart';
import 'package:universal_ble_example/data/storage_service.dart';
import 'package:universal_ble_example/home/permission_screen.dart';
import 'package:universal_ble_example/home/scanner_screen.dart';
import 'package:universal_ble_example/widgets/scan_controller_scope.dart';

/// Initializes the app services and checks permissions.
/// Returns whether the app has the required permissions.
Future<bool> initializeApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageService.instance.init();
  await UniversalBle.setLogLevel(BleLogLevel.verbose);
  return await UniversalBle.hasPermissions(
    withAndroidFineLocation: false,
  );
}

class UniversalBleApp extends StatelessWidget {
  final bool hasPermission;
  final ScanController scanController;
  final Locale? locale;
  final Widget Function(BuildContext, Widget?)? builder;

  const UniversalBleApp({
    super.key,
    required this.hasPermission,
    required this.scanController,
    this.locale,
    this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return ScanControllerScope(
      controller: scanController,
      child: MaterialApp(
      title: 'Universal BLE',
      debugShowCheckedModeBanner: false,
      locale: locale,
      builder: builder,
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
      ),
    );
  }
}
