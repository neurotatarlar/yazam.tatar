// Sheet that exposes user settings controls.
import 'package:flutter/material.dart';

import '../app_state.dart';

/// Settings sheet for theme, font size, and persistence controls.
class SettingsSheet extends StatelessWidget {
  const SettingsSheet({required this.state, super.key});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            state.t('settings.title'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          _ThemeSelector(state: state),
          const SizedBox(height: 12),
          _FontSizeSelector(state: state),
          const SizedBox(height: 12),
          SwitchListTile(
            value: state.settings.autoScroll,
            title: Text(state.t('settings.autoScroll')),
            onChanged: (value) => state.updateSettings(
              state.settings.copyWith(autoScroll: value),
            ),
          ),
          SwitchListTile(
            value: state.settings.saveHistory,
            title: Text(state.t('settings.saveHistory')),
            onChanged: (value) => state.updateSettings(
              state.settings.copyWith(saveHistory: value),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => _confirmClearHistory(context, state),
            child: Text(state.t('settings.clearHistory')),
          ),
          if (state.config.buildSha.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Build: ${_shortSha(state.config.buildSha)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  /// Confirm and clear history using a dialog.
  Future<void> _confirmClearHistory(
    BuildContext context,
    AppState state,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(state.t('settings.clearHistoryTitle')),
        content: Text(state.t('settings.clearHistoryBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(state.t('actions.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(state.t('actions.clear')),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await state.clearHistory();
    }
  }
}

/// Theme selection UI.
class _ThemeSelector extends StatelessWidget {
  const _ThemeSelector({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(state.t('settings.theme')),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: Text(state.t('settings.light')),
              selected: state.settings.themeMode == ThemeMode.light,
              onSelected: (_) => state.updateSettings(
                state.settings.copyWith(themeMode: ThemeMode.light),
              ),
            ),
            ChoiceChip(
              label: Text(state.t('settings.dark')),
              selected: state.settings.themeMode == ThemeMode.dark,
              onSelected: (_) => state.updateSettings(
                state.settings.copyWith(themeMode: ThemeMode.dark),
              ),
            ),
            ChoiceChip(
              label: Text(state.t('settings.system')),
              selected: state.settings.themeMode == ThemeMode.system,
              onSelected: (_) => state.updateSettings(
                state.settings.copyWith(themeMode: ThemeMode.system),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Font size selection UI.
class _FontSizeSelector extends StatelessWidget {
  const _FontSizeSelector({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(state.t('settings.fontSize')),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: Text(state.t('settings.small')),
              selected: state.settings.fontScale == 0.9,
              onSelected: (_) =>
                  state.updateSettings(state.settings.copyWith(fontScale: 0.9)),
            ),
            ChoiceChip(
              label: Text(state.t('settings.medium')),
              selected: state.settings.fontScale == 1.0,
              onSelected: (_) =>
                  state.updateSettings(state.settings.copyWith(fontScale: 1)),
            ),
            ChoiceChip(
              label: Text(state.t('settings.large')),
              selected: state.settings.fontScale == 1.1,
              onSelected: (_) =>
                  state.updateSettings(state.settings.copyWith(fontScale: 1.1)),
            ),
          ],
        ),
      ],
    );
  }
}

/// Shorten a full git SHA to a readable snippet.
String _shortSha(String sha) {
  if (sha.isEmpty) {
    return '';
  }
  return sha.length <= 8 ? sha : sha.substring(0, 8);
}
