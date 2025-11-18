import 'package:flutter/material.dart';

class ScannedDevicesPlaceholderWidget extends StatelessWidget {
  const ScannedDevicesPlaceholderWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.bluetooth_searching,
              size: 80,
              color: colorScheme.primary.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No Devices Found',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              'Tap "Start Scan" to discover nearby Bluetooth devices',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
