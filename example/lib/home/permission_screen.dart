import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:universal_ble_example/home/scanner_screen.dart';

class PermissionScreen extends StatefulWidget {
  const PermissionScreen({super.key});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen>
    with WidgetsBindingObserver {
  final bool _withAndroidFineLocation = false;
  bool _isChecking = true;
  bool _hasPermissions = false;
  bool _isRequesting = false;
  String? _errorMessage;

  void navigateToHome() {
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ScannerScreen()),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Re-check permissions when app resumes (user might have granted in settings)
    if (state == AppLifecycleState.resumed && !_hasPermissions) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    setState(() {
      _isChecking = true;
      _errorMessage = null;
    });

    try {
      // Check if permissions are required for this platform
      if (!BleCapabilities.requiresRuntimePermission) {
        // No permissions needed, go directly to home
        navigateToHome();
        return;
      }

      // Check if we already have permissions
      final hasPermissions = await UniversalBle.hasPermissions(
        withAndroidFineLocation: _withAndroidFineLocation,
      );

      setState(() {
        _isChecking = false;
        _hasPermissions = hasPermissions;
      });

      if (hasPermissions && mounted) {
        // Permissions already granted, go to home
        navigateToHome();
      }
    } catch (e) {
      setState(() {
        _isChecking = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _requestPermissions() async {
    setState(() {
      _isRequesting = true;
      _errorMessage = null;
    });

    try {
      await UniversalBle.requestPermissions(
        withAndroidFineLocation: _withAndroidFineLocation,
      );

      // Permissions granted, go to home
      if (mounted) {
        navigateToHome();
      }
    } catch (e) {
      setState(() {
        _isRequesting = false;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.security,
                    size: 80,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  'Bluetooth Permissions Required',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'This app needs Bluetooth permissions to scan and connect to nearby devices.',
                  style: TextStyle(
                    fontSize: 16,
                    color: colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                if (_isChecking)
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      colorScheme.primary,
                    ),
                  )
                else if (!_hasPermissions)
                  Column(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _isRequesting ? null : _requestPermissions,
                        icon: _isRequesting
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    colorScheme.onPrimary,
                                  ),
                                ),
                              )
                            : const Icon(Icons.check_circle),
                        label: Text(
                          _isRequesting
                              ? 'Requesting Permissions...'
                              : 'Get Started',
                          style: const TextStyle(fontSize: 16),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: colorScheme.error,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: TextStyle(
                                    color: colorScheme.onErrorContainer,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: _requestPermissions,
                          child: const Text('Try Again'),
                        ),
                      ],
                    ],
                  )
                else
                  const SizedBox.shrink(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
