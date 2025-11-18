import 'package:flutter/material.dart';

class RssiSignalIndicator extends StatelessWidget {
  final int rssi;
  const RssiSignalIndicator({super.key, required this.rssi});

  @override
  Widget build(BuildContext context) {
    final bool isPositive = rssi >= 0;
    final Color barColor = isPositive ? Colors.green : Colors.red;
    // BLE RSSI ranges (in dBm):
    // -30 to 0: Excellent signal (4 bars)
    // -50 to -30: Good signal (3 bars)
    // -70 to -50: Fair signal (2 bars)
    // -90 to -70: Weak signal (1 bar)
    // Below -90: Very weak signal (0 bars)
    // Positive values: Extremely strong (4 bars)
    int bars;
    if (isPositive) {
      bars = 4; // Positive RSSI is extremely strong
    } else {
      if (rssi >= -30) {
        bars = 4; // Excellent
      } else if (rssi >= -50) {
        bars = 3; // Good
      } else if (rssi >= -70) {
        bars = 2; // Fair
      } else if (rssi >= -90) {
        bars = 1; // Weak
      } else {
        bars = 0; // Very weak
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 24,
          height: 16,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(4, (index) {
              final barHeight = (index + 1) * 3.0 + 2.0;
              final isActive = index < bars;
              return Container(
                width: 3,
                height: barHeight,
                decoration: BoxDecoration(
                  color: isActive ? barColor : Colors.grey.withAlpha(30),
                  borderRadius: BorderRadius.circular(1.5),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 4),
        Text('$rssi'),
      ],
    );
  }
}
