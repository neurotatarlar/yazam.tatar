// Sheet that lists saved history items.
import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';

/// Scrollable history list for quick selection.
class HistorySheet extends StatelessWidget {
  const HistorySheet({required this.state, super.key});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    if (state.history.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(state.t('history.empty')),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: state.history.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = state.history[index];
        return ListTile(
          title: Text(
            item.original,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(item.timestamp.toLocal().toString()),
          onTap: () {
            unawaited(state.loadHistoryItem(item));
            unawaited(Navigator.of(context).maybePop());
          },
        );
      },
    );
  }
}
