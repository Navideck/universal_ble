import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:universal_ble_example/home/scanner_screen.dart';
import 'package:universal_ble_example/home/system_devices_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class AppDrawer extends StatefulWidget {
  final QueueType? queueType;
  final Function(QueueType)? onQueueTypeChanged;
  
  const AppDrawer({
    super.key,
    this.queueType,
    this.onQueueTypeChanged,
  });

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
          if (widget.queueType != null && widget.onQueueTypeChanged != null)
            ExpansionTile(
              leading: const Icon(Icons.queue),
              title: const Text('Queue Type'),
              subtitle: Text(
                _getQueueTypeLabel(widget.queueType!),
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    children: [
                      _buildQueueOption(
                        context,
                        QueueType.global,
                        'Global',
                        'All commands from all devices execute sequentially in a single queue',
                        Icons.queue,
                      ),
                      const SizedBox(height: 8),
                      _buildQueueOption(
                        context,
                        QueueType.perDevice,
                        'Per Device',
                        'Commands for each device execute in separate queues',
                        Icons.devices,
                      ),
                      const SizedBox(height: 8),
                      _buildQueueOption(
                        context,
                        QueueType.none,
                        'None',
                        'All commands execute in parallel without queuing',
                        Icons.all_inclusive,
                      ),
                    ],
                  ),
                ),
              ],
            ),
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
                      TextSpan(text: "Universal BLE is "),
                      TextSpan(
                        text: 'open source',
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
                      TextSpan(text: "."),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                RichText(
                  textAlign: TextAlign.justify,
                  text: TextSpan(
                    children: [
                      TextSpan(text: "Need help with your project? "),
                      TextSpan(
                        text: 'Hire us',
                        style: const TextStyle(
                          color: Colors.blue,
                          decoration: TextDecoration.underline,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () {
                            launchUrl(Uri.parse('mailto:info@navideck.com'));
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

  String _getQueueTypeLabel(QueueType queueType) {
    switch (queueType) {
      case QueueType.global:
        return 'Global';
      case QueueType.perDevice:
        return 'Per Device';
      case QueueType.none:
        return 'None';
    }
  }

  Widget _buildQueueOption(
    BuildContext context,
    QueueType value,
    String title,
    String description,
    IconData icon,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = widget.queueType == value;
    return InkWell(
      onTap: () {
        widget.onQueueTypeChanged?.call(value);
        Navigator.pop(context);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.outline.withValues(alpha: 0.2),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurface,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isSelected
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 11,
                      color: isSelected
                          ? colorScheme.onPrimaryContainer
                              .withValues(alpha: 0.7)
                          : colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: colorScheme.primary,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}
