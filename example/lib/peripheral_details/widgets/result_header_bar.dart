import 'package:flutter/material.dart';

/// Shared header row for result-style cards (e.g. Logs, Received advertisements).
/// Layout: [icon] [title] [copy?] [Spacer] [count?] [clear?]
/// Copy, count badge, and clear button are shown only when [count] > 0.
class ResultHeaderBar extends StatelessWidget {
  const ResultHeaderBar({
    super.key,
    required this.icon,
    required this.title,
    required this.count,
    this.onCopy,
    this.copyTooltip = 'Copy',
    this.onClear,
    this.clearTooltip = 'Clear all',
    this.titleFontSize = 16,
  });

  final IconData icon;
  final String title;
  final int count;
  final VoidCallback? onCopy;
  final String copyTooltip;
  final VoidCallback? onClear;
  final String clearTooltip;
  final double titleFontSize;

  bool get _hasItems => count > 0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(
          icon,
          color: colorScheme.primary,
          size: 20,
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: titleFontSize,
            color: colorScheme.onSurface,
          ),
        ),
        if (_hasItems && onCopy != null) ...[
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              Icons.copy,
              color: colorScheme.primary,
              size: 20,
            ),
            onPressed: onCopy,
            tooltip: copyTooltip,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 32,
              minHeight: 32,
            ),
          ),
        ],
        const Spacer(),
        if (_hasItems)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                color: colorScheme.onPrimaryContainer,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (_hasItems && onClear != null) ...[
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              Icons.close,
              color: colorScheme.error,
              size: 20,
            ),
            onPressed: onClear,
            tooltip: clearTooltip,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 32,
              minHeight: 32,
            ),
          ),
        ],
      ],
    );
  }
}
