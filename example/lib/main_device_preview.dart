import 'dart:io';

import 'package:device_preview_screenshot/device_preview_screenshot.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:universal_ble_example/universal_ble_app.dart';

void main() async {
  bool hasPermission = await initializeApp();

  // On macOS: ~/Library/Containers/com.navideck.universalble/Data/Documents/screenshots
  final screenshotsDir = await getScreenshotsDirectory();
  debugPrint('Screenshots will be saved to: ${screenshotsDir.path}');

  runApp(
    DevicePreview(
      enabled: true,
      builder: (context) => UniversalBleApp(
        hasPermission: hasPermission,
        locale: DevicePreview.locale(context),
        builder: DevicePreview.appBuilder,
      ),
      devices: [
        createCustomDevice(
          name: 'App Store 1242x2688',
          physicalWidth: 1242,
          physicalHeight: 2688,
        ),
        createCustomDevice(
          name: 'App Store iPad 2752x2064',
          physicalWidth: 2752,
          physicalHeight: 2064,
          deviceType: DeviceType.tablet,
        ),
      ],
      tools: [
        ...DevicePreview.defaultTools,
        DevicePreviewScreenshot(
          onScreenshot: screenshotAsFiles(screenshotsDir),
        ),
      ],
    ),
  );
}

/// Gets or creates the screenshots directory in the app's documents directory.
Future<Directory> getScreenshotsDirectory() async {
  final appDocumentsDir = await getApplicationDocumentsDirectory();
  final screenshotsDir = Directory('${appDocumentsDir.path}/screenshots');

  if (!await screenshotsDir.exists()) {
    await screenshotsDir.create(recursive: true);
  }

  return screenshotsDir;
}

/// Creates a custom device with the specified physical pixel dimensions.
DeviceInfo createCustomDevice({
  required String name,
  required double physicalWidth,
  required double physicalHeight,
  double pixelRatio = 3.0,
  DeviceType deviceType = DeviceType.phone,
}) {
  final logicalWidth = physicalWidth / pixelRatio;
  final logicalHeight = physicalHeight / pixelRatio;

  return DeviceInfo(
    identifier: DeviceIdentifier(
      TargetPlatform.iOS,
      deviceType,
      name,
    ),
    name: name,
    pixelRatio: pixelRatio,
    safeAreas: EdgeInsets.zero,
    rotatedSafeAreas: EdgeInsets.zero,
    screenPath: Path()
      ..addRect(Rect.fromLTWH(0.0, 0.0, logicalWidth, logicalHeight)),
    frameSize: Size(logicalWidth, logicalHeight),
    screenSize: Size(logicalWidth, logicalHeight),
    framePainter: const _EmptyFramePainter(),
  );
}

class _EmptyFramePainter extends CustomPainter {
  const _EmptyFramePainter();

  @override
  void paint(Canvas canvas, Size size) {}

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
