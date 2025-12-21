import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:universal_ble_example/home/scanner_screen.dart';
import 'package:universal_ble_example/home/system_devices_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  void _navigateToScreen(BuildContext context, Widget screen) {
    Navigator.pop(context);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Drawer(
      child: Column(
        children: [
          SizedBox(
            height: 110,
            child: DrawerHeader(
              padding: const EdgeInsets.only(top: 0, left: 16),
              decoration: BoxDecoration(
                color: colorScheme.primary,
              ),
              child: Row(
                children: [
                  Image.asset('assets/icon.png', width: 40, height: 40),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Universal BLE',
                      maxLines: 2,
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onPrimary,
                                height: 1,
                              ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.search),
            title: const Text('Scanner'),
            onTap: () => _navigateToScreen(context, const ScannerScreen()),
          ),
          if (BleCapabilities.supportsConnectedDevicesApi)
            ListTile(
              leading: const Icon(Icons.devices),
              title: const Text('System Devices'),
              onTap: () =>
                  _navigateToScreen(context, const SystemDevicesScreen()),
            ),
          const Divider(),
          FutureBuilder(
            future: PackageInfo.fromPlatform(),
            builder: (_, snapshot) => AboutListTile(
              icon: const Icon(Icons.info_outline),
              applicationIcon:
                  Image.asset('assets/icon.png', width: 40, height: 40),
              applicationName: 'Universal BLE',
              applicationVersion:
                  "${snapshot.data?.version} (${snapshot.data?.buildNumber})",
              applicationLegalese: '\u{a9} 2023 Navideck',
              aboutBoxChildren: [
                const SizedBox(height: 24),
                RichText(
                  textAlign: TextAlign.justify,
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: 'Learn More',
                        style: const TextStyle(
                          color: Colors.blue,
                          decoration: TextDecoration.underline,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () {
                            launchUrl(Uri.parse(
                                "https://github.com/Navideck/universal_ble"));
                          },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
