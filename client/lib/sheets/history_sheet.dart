// Modal sheet that lists saved correction entries with quick restore actions.
import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';

/// Scrollable history list for quick selection.
class HistorySheet extends StatelessWidget {
  const HistorySheet({required this.state, super.key});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.8;

    return SizedBox(
      height: maxHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.t('history.title'),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        state.t('history.subtitle'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: state.t('actions.close'),
                  onPressed: () => unawaited(Navigator.of(context).maybePop()),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: state.history.isEmpty
                  ? _EmptyHistory(state: state)
                  : _HistoryList(state: state),
            ),
            if (state.hasMoreHistory)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: state.isHistoryLoading
                      ? null
                      : () => unawaited(state.loadMoreHistory()),
                  icon: state.isHistoryLoading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.expand_more),
                  label: Text(
                    state.isHistoryLoading
                        ? state.t('history.loading')
                        : state.t('history.loadMore'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      padding: const EdgeInsets.all(18),
      child: Text(state.t('history.empty')),
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: state.history.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = state.history[index];
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            unawaited(state.loadHistoryItem(item));
            unawaited(Navigator.of(context).maybePop());
          },
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatTimestamp(item.timestamp),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  state.t('panel.original'),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _preview(item.original),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text(
                  state.t('panel.corrected'),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _preview(item.corrected),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

String _formatTimestamp(DateTime timestamp) {
  final local = timestamp.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$month-$day $hour:$minute';
}

String _preview(String value) {
  final oneLine = value.replaceAll('\n', ' ').trim();
  if (oneLine.length <= 180) {
    return oneLine;
  }
  return '${oneLine.substring(0, 177)}...';
}
