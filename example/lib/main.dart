import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:universal_ble_example/home/home.dart' show CentralHome;
import 'package:universal_ble_example/peripheral/peripheral_home.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await UniversalBle.setLogLevel(BleLogLevel.verbose);
  runApp(
    MaterialApp(
      title: 'Universal BLE',
      debugShowCheckedModeBanner: false,
      darkTheme: ThemeData.dark(),
      themeMode: ThemeMode.system,
      home: const _TabbedExample(),
    ),
  );
}

class _TabbedExample extends StatelessWidget {
  const _TabbedExample();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Universal BLE'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Central'),
              Tab(text: 'Peripheral'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            CentralHome(showAppBar: false),
            PeripheralHome(),
          ],
        ),
      ),
    );
  }
}
