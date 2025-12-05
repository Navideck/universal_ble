import 'package:flutter/material.dart';
import 'package:package_info/package_info.dart';

class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  Widget icon = const Icon(Icons.info_outline);
  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          SizedBox(
            height: 110,
            child: DrawerHeader(
              padding: const EdgeInsets.only(top: 0, left: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
              ),
              child: Row(
                children: [
                  icon,
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Universal BLE',
                      maxLines: 2,
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onPrimary,
                                height: 1,
                              ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          FutureBuilder(
            future: PackageInfo.fromPlatform(),
            builder: (_, snapshot) => AboutListTile(
              icon: const Icon(Icons.info_outline),
              applicationIcon: const Icon(Icons.info_outline),
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
                        text: "Learn More",
                        style: Theme.of(context).textTheme.bodyMedium!,
                      ),
                      const WidgetSpan(
                        child: SizedBox(width: 9),
                      ),
                      TextSpan(
                        text: "https://github.com/Navideck/universal_ble",
                        style: Theme.of(context).textTheme.bodyMedium!,
                      ),
                      const WidgetSpan(
                        child: SizedBox(width: 9),
                      ),
                      // TextSpan(
                      //   style: Theme.of(context)
                      //       .textTheme
                      //       .bodyMedium!
                      //       .copyWith(fontWeight: FontWeight.bold),
                      //   text: "https://github.com/Navideck/universal_ble",
                      //   recognizer: TapGestureRecognizer()
                      //     ..onTap = () async => openUrl(controller.url),
                      // ),
                      const TextSpan(text: '.'),
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

class _DrawerTile extends StatelessWidget {
  final IconData? icon;
  final String title;
  final Widget? subtitle;
  final Function()? onTap;
  final Function()? onLongPress;
  final Widget? trailing;
  const _DrawerTile({
    super.key,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.onLongPress,
    this.icon,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: icon == null
          ? null
          : Padding(
              padding: const EdgeInsets.all(2.0),
              child: Icon(icon),
            ),
      title: Text(title),
      subtitle: subtitle,
      onTap: onTap,
      onLongPress: onLongPress,
      trailing: trailing,
    );
  }
}
