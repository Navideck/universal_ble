import 'package:flutter/material.dart';

/// Wraps [child] and briefly shows an outline when [trigger] changes.
/// Draws only a stroked border that fades out smoothly; does not block interaction.
class FlashOnUpdateWidget extends StatefulWidget {
  const FlashOnUpdateWidget({
    super.key,
    required this.trigger,
    required this.child,
    this.highlightColor,
    this.borderRadius = 16,
  });

  /// When this value changes, the outline animation runs (or restarts).
  final Object trigger;

  final Widget child;

  /// If null, [Theme.colorScheme.primaryContainer] is used for the outline.
  final Color? highlightColor;

  /// Border radius of the outline to match the child (e.g. Card) corners.
  final double borderRadius;

  @override
  State<FlashOnUpdateWidget> createState() => _FlashOnUpdateWidgetState();
}

class _FlashOnUpdateWidgetState extends State<FlashOnUpdateWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 450),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
  }

  @override
  void didUpdateWidget(FlashOnUpdateWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger != oldWidget.trigger) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = widget.highlightColor ?? colorScheme.primaryContainer;

    return Stack(
      children: [
        widget.child,
        AnimatedBuilder(
          animation: _animation,
          builder: (context, _) {
            final opacity = 1 - _animation.value;
            if (opacity <= 0) return const SizedBox.shrink();
            return Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _OutlinePainter(
                    color: color,
                    opacity: opacity,
                    borderRadius: widget.borderRadius,
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _OutlinePainter extends CustomPainter {
  _OutlinePainter({
    required this.color,
    required this.opacity,
    required this.borderRadius,
  });

  static const double _strokeWidth = 2;

  final Color color;
  final double opacity;
  final double borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    final paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth;
    final half = _strokeWidth / 2;
    final rect = Rect.fromLTWH(half, half, size.width - _strokeWidth, size.height - _strokeWidth);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius - half));
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(_OutlinePainter oldDelegate) {
    return oldDelegate.opacity != opacity ||
        oldDelegate.color != color ||
        oldDelegate.borderRadius != borderRadius;
  }
}
