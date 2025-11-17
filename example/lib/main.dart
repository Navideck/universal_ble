import 'package:flutter/material.dart';
import 'package:universal_ble_example/data/storage_service.dart';
import 'package:universal_ble_example/home/home.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageService.instance.init();

  runApp(
    MaterialApp(
      title: 'Universal BLE',
      debugShowCheckedModeBanner: false,
      darkTheme: ThemeData.dark(),
      themeMode: ThemeMode.system,
      home: const MyApp(),
    ),
  );
}
