import 'dart:async';

import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';

class BleAvailabilityIcon extends StatefulWidget {
  final Function(AvailabilityState) onAvailabilityStateChanged;
  const BleAvailabilityIcon({
    super.key,
    required this.onAvailabilityStateChanged,
  });

  @override
  State<BleAvailabilityIcon> createState() => _BleAvailabilityIconState();
}

class _BleAvailabilityIconState extends State<BleAvailabilityIcon> {
  AvailabilityState? bleAvailabilityState;
  StreamSubscription<AvailabilityState>? _availabilitySubscription;

  @override
  void initState() {
    super.initState();
    UniversalBle.getBluetoothAvailabilityState()
        .then(_handleAvailabilityStateChanged);
    _availabilitySubscription =
        UniversalBle.availabilityStream.listen(_handleAvailabilityStateChanged);
  }

  void _handleAvailabilityStateChanged(AvailabilityState state) {
    if (mounted) setState(() => bleAvailabilityState = state);
    widget.onAvailabilityStateChanged(state);
  }

  @override
  void dispose() {
    _availabilitySubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (bleAvailabilityState == null) {
      return const SizedBox.shrink();
    }
    return switch (bleAvailabilityState!) {
      AvailabilityState.resetting => Icon(
          Icons.bluetooth_searching,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      AvailabilityState.poweredOn => Icon(
          Icons.bluetooth_connected,
          color: Theme.of(context).colorScheme.primary,
        ),
      AvailabilityState.poweredOff => Icon(
          Icons.bluetooth_disabled,
          color: Theme.of(context).colorScheme.error,
        ),
      AvailabilityState.unauthorized => Icon(
          Icons.bluetooth_disabled,
          color: Theme.of(context).colorScheme.error,
        ),
      AvailabilityState.unsupported => Icon(
          Icons.bluetooth_disabled,
          color: Theme.of(context).colorScheme.outline,
        ),
      AvailabilityState.unknown => Icon(
          Icons.bluetooth_searching,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        ),
    };
  }
}
