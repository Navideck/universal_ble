import 'dart:async';
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_ble/universal_ble.dart';

/// The callback function should always be a top-level or static function.
@pragma('vm:entry-point')
void startBleMonitorCallback() {
  FlutterForegroundTask.setTaskHandler(BleMonitorTaskHandler());
}

/// Task handler for background BLE device monitoring.
/// Periodically scans for monitored devices and updates the notification.
class BleMonitorTaskHandler extends TaskHandler {
  static const String _monitoredDevicesKey = 'monitored_devices';
  static const int _scanDurationSeconds = 5;

  List<String> _monitoredDeviceIds = [];
  Set<String> _foundDevices = {};
  StreamSubscription<BleDevice>? _scanSubscription;
  bool _isScanning = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Load monitored devices from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    _monitoredDeviceIds = prefs.getStringList(_monitoredDevicesKey) ?? [];

    // Set up scan result listener
    _scanSubscription = UniversalBle.scanStream.listen(_onScanResult);

    FlutterForegroundTask.updateService(
      notificationTitle: 'BLE Monitor Active',
      notificationText: 'Monitoring ${_monitoredDeviceIds.length} device(s)',
    );
  }

  void _onScanResult(BleDevice device) {
    if (_monitoredDeviceIds.contains(device.deviceId)) {
      _foundDevices.add(device.deviceId);
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) async {
    if (_isScanning) return;

    // Reload monitored devices in case they changed
    final prefs = await SharedPreferences.getInstance();
    _monitoredDeviceIds = prefs.getStringList(_monitoredDevicesKey) ?? [];

    if (_monitoredDeviceIds.isEmpty) {
      FlutterForegroundTask.updateService(
        notificationTitle: 'BLE Monitor Active',
        notificationText: 'No devices to monitor',
      );
      return;
    }

    _isScanning = true;
    _foundDevices.clear();

    try {
      // Start scanning
      await UniversalBle.startScan();

      // Wait for scan duration
      await Future.delayed(const Duration(seconds: _scanDurationSeconds));

      // Stop scanning
      await UniversalBle.stopScan();
    } catch (e) {
      // Handle scan errors (e.g., Bluetooth off)
      FlutterForegroundTask.updateService(
        notificationTitle: 'BLE Monitor',
        notificationText: 'Scan error: ${e.toString().substring(0, 50)}',
      );
      _isScanning = false;
      return;
    }

    _isScanning = false;

    // Update notification with results
    final foundCount = _foundDevices.length;
    final totalCount = _monitoredDeviceIds.length;

    String notificationText;
    if (foundCount == 0) {
      notificationText = 'Monitoring $totalCount device(s) - none nearby';
    } else if (foundCount == totalCount) {
      notificationText = 'All $totalCount monitored device(s) found nearby';
    } else {
      notificationText = '$foundCount of $totalCount device(s) found nearby';
    }

    FlutterForegroundTask.updateService(
      notificationTitle: 'BLE Monitor Active',
      notificationText: notificationText,
    );

    // Send data to main isolate
    FlutterForegroundTask.sendDataToMain({
      'foundDevices': _foundDevices.toList(),
      'monitoredDevices': _monitoredDeviceIds,
      'timestamp': timestamp.millisecondsSinceEpoch,
    });
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _scanSubscription?.cancel();
    _scanSubscription = null;

    if (_isScanning) {
      try {
        await UniversalBle.stopScan();
      } catch (_) {}
    }
  }

  @override
  void onReceiveData(Object data) {
    // Handle data from main isolate if needed
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'stop') {
      FlutterForegroundTask.stopService();
    }
  }

  @override
  void onNotificationPressed() {
    // Launch app when notification is pressed
    FlutterForegroundTask.launchApp();
  }

  @override
  void onNotificationDismissed() {
    // Notification dismissed - service continues running
  }
}

/// Helper class to manage the BLE monitor service from the UI.
class BleMonitorManager {
  BleMonitorManager._();
  static final BleMonitorManager instance = BleMonitorManager._();

  /// Initialize the foreground task service.
  void init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'ble_monitor_channel',
        channelName: 'BLE Device Monitor',
        channelDescription: 'Monitors BLE devices in the background',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(30000), // 30 seconds
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// Check if the monitor service is running.
  Future<bool> isRunning() async {
    return await FlutterForegroundTask.isRunningService;
  }

  /// Start the background monitor service.
  Future<void> start() async {
    // Check if already running
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.restartService();
      return;
    }

    // Request notification permission on Android 13+
    if (Platform.isAndroid) {
      final notificationPermission =
          await FlutterForegroundTask.checkNotificationPermission();
      if (notificationPermission != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
    }

    await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: 'BLE Monitor Starting...',
      notificationText: 'Initializing background scan',
      notificationButtons: [
        const NotificationButton(id: 'stop', text: 'Stop'),
      ],
      callback: startBleMonitorCallback,
    );
  }

  /// Stop the background monitor service.
  Future<void> stop() async {
    await FlutterForegroundTask.stopService();
  }

  /// Add a callback to receive data from the background service.
  void addDataCallback(void Function(Object data) callback) {
    FlutterForegroundTask.addTaskDataCallback(callback);
  }

  /// Remove a data callback.
  void removeDataCallback(void Function(Object data) callback) {
    FlutterForegroundTask.removeTaskDataCallback(callback);
  }
}
