import 'package:flutter/material.dart';

/// Wraps [child] and briefly highlights it when [trigger] changes.
/// Uses a semi-opaque overlay that fades to transparent over ~300ms.
class FlashOnUpdateWidget extends StatelessWidget {
  const FlashOnUpdateWidget({
    super.key,
    required this.trigger,
    required this.child,
    this.highlightColor,
  });

  /// When this value changes, the flash animation runs once.
  final Object trigger;

  final Widget child;

  /// If null, [Theme.colorScheme.primaryContainer] is used with opacity.
  final Color? highlightColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = highlightColor ??
        colorScheme.primaryContainer.withValues(alpha: 0.6);

    return TweenAnimationBuilder<double>(
      key: ValueKey(trigger),
      tween: Tween<double>(begin: 1, end: 0),
      duration: const Duration(milliseconds: 300),
      builder: (context, value, childWidget) {
        return Stack(
          children: [
            childWidget!,
            if (value > 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: color.withValues(alpha: value * 0.6),
                  ),
                ),
              ),
          ],
        );
      },
      child: child,
    );
  }
}
