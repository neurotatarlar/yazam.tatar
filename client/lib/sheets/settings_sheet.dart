// Settings modal for theme, typography, and data controls.
import 'package:flutter/material.dart';

import '../app_state.dart';

/// Settings sheet for theme, font size, and persistence controls.
class SettingsSheet extends StatelessWidget {
  const SettingsSheet({required this.state, super.key});

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
                  child: Text(
                    state.t('settings.title'),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: state.t('actions.close'),
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  _SettingsCard(
                    title: state.t('settings.appearance'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ThemeSelector(state: state),
                        const SizedBox(height: 16),
                        _FontSizeSelector(state: state),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SettingsCard(
                    title: state.t('settings.behavior'),
                    child: Column(
                      children: [
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: state.settings.autoScroll,
                          title: Text(state.t('settings.autoScroll')),
                          onChanged: (value) => state.updateSettings(
                            state.settings.copyWith(autoScroll: value),
                          ),
                        ),
                        const Divider(height: 1),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: state.settings.saveHistory,
                          title: Text(state.t('settings.saveHistory')),
                          onChanged: (value) => state.updateSettings(
                            state.settings.copyWith(saveHistory: value),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SettingsCard(
                    title: state.t('settings.data'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () => _confirmClearHistory(context, state),
                          icon: const Icon(Icons.delete_sweep),
                          label: Text(state.t('settings.clearHistory')),
                        ),
                        if (state.config.buildSha.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            state.t(
                              'settings.build',
                              vars: {'sha': _shortSha(state.config.buildSha)},
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
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
        const SizedBox(height: 8),
        SegmentedButton<ThemeMode>(
          segments: [
            ButtonSegment(
              value: ThemeMode.light,
              label: Text(state.t('settings.light')),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              label: Text(state.t('settings.dark')),
            ),
            ButtonSegment(
              value: ThemeMode.system,
              label: Text(state.t('settings.system')),
            ),
          ],
          selected: {state.settings.themeMode},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => state.updateSettings(
            state.settings.copyWith(themeMode: selection.first),
          ),
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
        const SizedBox(height: 8),
        SegmentedButton<double>(
          segments: [
            ButtonSegment(value: 0.9, label: Text(state.t('settings.small'))),
            ButtonSegment(value: 1, label: Text(state.t('settings.medium'))),
            ButtonSegment(value: 1.1, label: Text(state.t('settings.large'))),
          ],
          selected: {state.settings.fontScale},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => state.updateSettings(
            state.settings.copyWith(fontScale: selection.first),
          ),
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
