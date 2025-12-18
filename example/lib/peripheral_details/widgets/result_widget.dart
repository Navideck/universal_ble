import 'package:flutter/material.dart';

class ResultWidget extends StatelessWidget {
  final List<String> results;
  final bool scrollable;
  final ScrollController scrollController;
  final void Function(int? index) onClearTap;
  const ResultWidget({
    required this.results,
    required this.onClearTap,
    this.scrollable = false,
    required this.scrollController,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: scrollable ? MainAxisSize.max : MainAxisSize.min,
          children: [
            _buildHeader(colorScheme),
            if (results.isEmpty)
              _buildEmptyState(colorScheme)
            else
              _buildLogsList(colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.history,
            color: colorScheme.primary,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            'Logs',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: colorScheme.onSurface,
            ),
          ),
          const Spacer(),
          if (results.isNotEmpty)
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
                '${results.length}',
                style: TextStyle(
                  color: colorScheme.onPrimaryContainer,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (results.isNotEmpty) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(
                Icons.clear_all,
                color: colorScheme.error,
                size: 20,
              ),
              onPressed: () => onClearTap(null),
              tooltip: 'Clear all logs',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 32,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    final emptyStateContent = Padding(
      padding: const EdgeInsets.all(32.0),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history_outlined,
              size: 48,
              color: colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No logs yet',
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );

    return scrollable ? Expanded(child: emptyStateContent) : emptyStateContent;
  }

  Widget _buildLogsList(ColorScheme colorScheme) {
    final listView = ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      controller: scrollController,
      itemCount: results.length,
      itemBuilder: (context, index) => _buildLogItem(colorScheme, index),
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: colorScheme.outline.withValues(alpha: 0.2),
      ),
    );

    if (scrollable) {
      return Expanded(child: listView);
    } else {
      return Container(
        constraints: const BoxConstraints(maxHeight: 300),
        child: listView,
      );
    }
  }

  Widget _buildLogItem(ColorScheme colorScheme, int index) {
    var reversedIndex = results.length - index - 1;
    final log = results[reversedIndex];
    return InkWell(
      onTap: () => onClearTap(reversedIndex),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.circle,
              size: 6,
              color: colorScheme.primary.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SelectableText(
                log,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.close,
              size: 16,
              color: colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }
}
