// Main Flutter UI for the Tatar GEC client.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_state.dart';
import 'sheets/history_sheet.dart' deferred as history_sheet;
import 'sheets/report_sheet.dart' deferred as report_sheet;
import 'sheets/settings_sheet.dart' deferred as settings_sheet;

const _brandColor = Color(0xFF4F46E5);
const _bgLight = Color(0xFFF8FAFC);
const _surfaceLight = Color(0xFFFFFFFF);
const _textLight = Color(0xFF0F172A);
const _mutedLight = Color(0xFF64748B);
const _borderLight = Color(0xFFE2E8F0);

const _bgDark = Color(0xFF0F172A);
const _surfaceDark = Color(0xFF131B2E);
const _textDark = Color(0xFFF8FAFC);
const _mutedDark = Color(0xFF94A3B8);
const _borderDark = Color(0xFF334155);

const _sidebarWidth = 252.0;
const _topBarHeight = 64.0;

const _tbankDonationUrl = 'https://www.tbank.ru/cf/5DeXHs3nnOy';
const _revolutDonationUrl = 'https://revolut.me/gaydmi';

/// App entry point that boots configuration and state.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appState = await bootstrapAppState();
  runApp(MyApp(appState: appState));
}

/// Root widget that wires state, theming, and routing.
class MyApp extends StatelessWidget {
  const MyApp({required this.appState, super.key});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: appState,
      child: Consumer<AppState>(
        builder: (context, state, _) {
          return MaterialApp(
            title: state.config.appName,
            debugShowCheckedModeBanner: false,
            themeMode: state.settings.themeMode,
            theme: _buildTheme(Brightness.light),
            darkTheme: _buildTheme(Brightness.dark),
            home: const HomePage(),
          );
        },
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: _brandColor,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? _bgDark : _bgLight,
      cardColor: isDark ? _surfaceDark : _surfaceLight,
      dividerColor: isDark ? _borderDark : _borderLight,
      textTheme:
          ThemeData(
            brightness: brightness,
          ).textTheme.apply(
            fontFamily: 'Inter',
            fontFamilyFallback: const [
              'Manrope',
              'Noto Sans',
              'Noto Sans UI',
              'Segoe UI',
              'Roboto',
              'Arial',
              'sans-serif',
            ],
            bodyColor: isDark ? _textDark : _textLight,
            displayColor: isDark ? _textDark : _textLight,
          ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? _surfaceDark : _surfaceLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: isDark ? _borderDark : _borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: isDark ? _borderDark : _borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _brandColor, width: 1.4),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// Main workspace page.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(context.read<AppState>().hydrate());
      }
      _inputFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    _syncInputController(state);

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 1100;
            if (!isDesktop) {
              return _CompactLayout(
                state: state,
                inputController: _inputController,
                inputFocusNode: _inputFocusNode,
                onOpenHistory: () => _openHistory(context, state),
                onOpenSettings: () => _openSettings(context, state),
                onOpenReport: () => _openReportSheet(context, state),
                onOpenSupport: (url) => _openExternal(context, state, url),
              );
            }
            return _DesktopLayout(
              state: state,
              inputController: _inputController,
              inputFocusNode: _inputFocusNode,
              width: constraints.maxWidth,
              onOpenHistory: () => _openHistory(context, state),
              onOpenSettings: () => _openSettings(context, state),
              onOpenReport: () => _openReportSheet(context, state),
              onOpenSupport: (url) => _openExternal(context, state, url),
            );
          },
        ),
      ),
    );
  }

  void _syncInputController(AppState state) {
    if (_inputController.text == state.originalText) {
      return;
    }
    _inputController.text = state.originalText;
    _inputController.selection = TextSelection.fromPosition(
      TextPosition(offset: _inputController.text.length),
    );
  }

  Future<void> _openHistory(BuildContext context, AppState state) async {
    await history_sheet.loadLibrary();
    if (!context.mounted) {
      return;
    }
    final isDesktop = MediaQuery.of(context).size.width >= 1100;
    if (isDesktop) {
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          child: SizedBox(
            width: 820,
            child: history_sheet.HistorySheet(state: state),
          ),
        ),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => history_sheet.HistorySheet(state: state),
    );
  }

  Future<void> _openSettings(BuildContext context, AppState state) async {
    await settings_sheet.loadLibrary();
    if (!context.mounted) {
      return;
    }
    final isDesktop = MediaQuery.of(context).size.width >= 1100;
    if (isDesktop) {
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          child: SizedBox(
            width: 560,
            child: settings_sheet.SettingsSheet(state: state),
          ),
        ),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => settings_sheet.SettingsSheet(state: state),
    );
  }

  Future<void> _openReportSheet(BuildContext context, AppState state) async {
    await report_sheet.loadLibrary();
    if (!context.mounted) {
      return;
    }
    final isDesktop = MediaQuery.of(context).size.width >= 1100;
    if (isDesktop) {
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          child: SizedBox(
            width: 620,
            child: report_sheet.ReportSheet(state: state),
          ),
        ),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => report_sheet.ReportSheet(state: state),
    );
  }

  Future<void> _openExternal(
    BuildContext context,
    AppState state,
    String url,
  ) async {
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(state.t('errors.openLink'))),
      );
    }
  }
}

class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout({
    required this.state,
    required this.inputController,
    required this.inputFocusNode,
    required this.width,
    required this.onOpenHistory,
    required this.onOpenSettings,
    required this.onOpenReport,
    required this.onOpenSupport,
  });

  final AppState state;
  final TextEditingController inputController;
  final FocusNode inputFocusNode;
  final double width;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenReport;
  final Future<void> Function(String url) onOpenSupport;

  @override
  Widget build(BuildContext context) {
    final showHistoryRail = width >= 1480;

    return Row(
      children: [
        _Sidebar(
          state: state,
          onOpenHistory: onOpenHistory,
          onOpenSettings: onOpenSettings,
          onOpenSupport: onOpenSupport,
        ),
        Expanded(
          child: Column(
            children: [
              _TopBar(state: state),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            Expanded(
                              child: _WorkspacePanel(
                                state: state,
                                inputController: inputController,
                                inputFocusNode: inputFocusNode,
                                onOpenReport: onOpenReport,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _ActionBar(
                              state: state,
                              inputController: inputController,
                            ),
                          ],
                        ),
                      ),
                      if (showHistoryRail) ...[
                        const SizedBox(width: 20),
                        SizedBox(
                          width: 320,
                          child: _HistoryRail(state: state),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CompactLayout extends StatelessWidget {
  const _CompactLayout({
    required this.state,
    required this.inputController,
    required this.inputFocusNode,
    required this.onOpenHistory,
    required this.onOpenSettings,
    required this.onOpenReport,
    required this.onOpenSupport,
  });

  final AppState state;
  final TextEditingController inputController;
  final FocusNode inputFocusNode;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenReport;
  final Future<void> Function(String url) onOpenSupport;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _TopBar(state: state),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Expanded(
                  child: _WorkspacePanel(
                    state: state,
                    inputController: inputController,
                    inputFocusNode: inputFocusNode,
                    onOpenReport: onOpenReport,
                    forceVertical: true,
                  ),
                ),
                const SizedBox(height: 12),
                _ActionBar(state: state, inputController: inputController),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onOpenHistory,
                    icon: const Icon(Icons.history),
                    label: Text(state.t('history.title')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onOpenSettings,
                    icon: const Icon(Icons.settings),
                    label: Text(state.t('settings.title')),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  onPressed: () => unawaited(onOpenSupport(_tbankDonationUrl)),
                  icon: const Icon(Icons.favorite),
                  tooltip: state.t('nav.support'),
                ),
                const SizedBox(width: 6),
                IconButton.outlined(
                  onPressed: () =>
                      unawaited(onOpenSupport(_revolutDonationUrl)),
                  icon: const Icon(Icons.currency_exchange),
                  tooltip: state.t('nav.support'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.state,
    required this.onOpenHistory,
    required this.onOpenSettings,
    required this.onOpenSupport,
  });

  final AppState state;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenSettings;
  final Future<void> Function(String url) onOpenSupport;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? _surfaceDark : _surfaceLight;
    final border = isDark ? _borderDark : _borderLight;
    final muted = isDark ? _mutedDark : _mutedLight;

    return Container(
      width: _sidebarWidth,
      decoration: BoxDecoration(
        color: surface,
        border: Border(right: BorderSide(color: border)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _brandColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.edit_note, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    state.config.appName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          _SidebarItem(
            icon: Icons.edit_note,
            label: state.t('nav.workspace'),
            selected: true,
            onTap: () {},
          ),
          _SidebarItem(
            icon: Icons.history,
            label: state.t('history.title'),
            onTap: onOpenHistory,
          ),
          _SidebarItem(
            icon: Icons.settings,
            label: state.t('settings.title'),
            onTap: onOpenSettings,
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: _brandColor.withValues(alpha: 0.08),
                border: Border.all(color: _brandColor.withValues(alpha: 0.25)),
              ),
              child: Column(
                children: [
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.favorite, color: _brandColor),
                    title: Text(
                      state.t('support.tbank'),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    onTap: () => unawaited(onOpenSupport(_tbankDonationUrl)),
                  ),
                  Divider(height: 1, color: _brandColor.withValues(alpha: 0.2)),
                  ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.currency_exchange,
                      color: _brandColor,
                    ),
                    title: Text(
                      state.t('support.revolut'),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    onTap: () => unawaited(onOpenSupport(_revolutDonationUrl)),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.t('partners.title'),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'assets/partners/minmol.jpeg',
                    fit: BoxFit.contain,
                    height: 50,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'assets/partners/tatfor.jpeg',
                    fit: BoxFit.contain,
                    height: 50,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? _brandColor.withValues(alpha: 0.12)
        : Colors.transparent;
    final fg = selected
        ? _brandColor
        : Theme.of(context).textTheme.bodyMedium?.color;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Icon(icon, color: fg),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: fg,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? _borderDark : _borderLight;
    final muted = isDark ? _mutedDark : _mutedLight;

    return Container(
      height: _topBarHeight,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Text(
            state.t('nav.workspace'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 14),
          Text(
            state.t('panel.flow'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: muted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          _LanguagePill(state: state),
        ],
      ),
    );
  }
}

class _LanguagePill extends StatelessWidget {
  const _LanguagePill({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? _borderDark : _borderLight;

    Widget item(String code, String label) {
      final selected = state.settings.language == code;
      return Expanded(
        child: InkWell(
          onTap: () => unawaited(state.setLanguage(code)),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: selected ? _brandColor.withValues(alpha: 0.12) : null,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: selected ? _brandColor : null,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      width: 210,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          item('tt', 'TT'),
          item('en', 'EN'),
          item('ru', 'RU'),
        ],
      ),
    );
  }
}

class _WorkspacePanel extends StatelessWidget {
  const _WorkspacePanel({
    required this.state,
    required this.inputController,
    required this.inputFocusNode,
    required this.onOpenReport,
    this.forceVertical = false,
  });

  final AppState state;
  final TextEditingController inputController;
  final FocusNode inputFocusNode;
  final VoidCallback onOpenReport;
  final bool forceVertical;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? _borderDark : _borderLight;
    final muted = isDark ? _mutedDark : _mutedLight;

    final correctionText = state.correctedText;

    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = !forceVertical && constraints.maxWidth >= 920;
        final divider = Container(width: 1, color: border);

        final originalPane = Container(
          padding: const EdgeInsets.all(24),
          color: isDark ? _surfaceDark : _surfaceLight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                state.t('panel.original'),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: muted,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: TextField(
                  controller: inputController,
                  focusNode: inputFocusNode,
                  onChanged: state.updateOriginalText,
                  expands: true,
                  maxLines: null,
                  decoration: InputDecoration(
                    hintText: state.t('input.placeholder'),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    height: 1.55,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
        );

        final correctionPane = Container(
          padding: const EdgeInsets.all(24),
          color: isDark
              ? _surfaceDark.withValues(alpha: 0.92)
              : _surfaceLight.withValues(alpha: 0.92),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    state.t('panel.corrected'),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: _brandColor,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  if (state.isStreaming)
                    Row(
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          state.t('status.correcting'),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: muted,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _CorrectionBody(
                  state: state,
                  correctionText: correctionText,
                ),
              ),
              if (!state.isStreaming && correctionText.isNotEmpty)
                _FeedbackRow(state: state, onOpenReport: onOpenReport),
            ],
          ),
        );

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                blurRadius: 16,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: horizontal
                ? Row(
                    children: [
                      Expanded(child: originalPane),
                      divider,
                      Expanded(child: correctionPane),
                    ],
                  )
                : Column(
                    children: [
                      SizedBox(
                        height: constraints.maxHeight * 0.48,
                        child: originalPane,
                      ),
                      Container(height: 1, color: border),
                      Expanded(child: correctionPane),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _CorrectionBody extends StatelessWidget {
  const _CorrectionBody({required this.state, required this.correctionText});

  final AppState state;
  final String correctionText;

  @override
  Widget build(BuildContext context) {
    if (state.errorMessage != null && state.errorMessage!.isNotEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                state.errorMessage!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
            TextButton(
              onPressed: state.retry,
              child: Text(state.t('actions.retry')),
            ),
          ],
        ),
      );
    }

    if (state.isStreaming && correctionText.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          state.t('status.correcting'),
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }

    if (correctionText.isNotEmpty) {
      return SelectableText(
        correctionText,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          height: 1.55,
          fontSize: 18,
        ),
      );
    }

    return Text(
      state.t('empty.title'),
      style: Theme.of(
        context,
      ).textTheme.bodyLarge?.copyWith(color: Theme.of(context).hintColor),
    );
  }
}

class _FeedbackRow extends StatelessWidget {
  const _FeedbackRow({required this.state, required this.onOpenReport});

  final AppState state;
  final VoidCallback onOpenReport;

  @override
  Widget build(BuildContext context) {
    final feedback = state.activeFeedback;
    final showUp = feedback != FeedbackChoice.down;
    final showDown = feedback != FeedbackChoice.up;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 460;
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              if (showUp)
                IconButton(
                  onPressed: () =>
                      state.toggleActiveFeedback(FeedbackChoice.up),
                  icon: Icon(
                    feedback == FeedbackChoice.up
                        ? Icons.thumb_up_alt
                        : Icons.thumb_up_alt_outlined,
                  ),
                ),
              if (showDown)
                IconButton(
                  onPressed: () =>
                      state.toggleActiveFeedback(FeedbackChoice.down),
                  icon: Icon(
                    feedback == FeedbackChoice.down
                        ? Icons.thumb_down_alt
                        : Icons.thumb_down_alt_outlined,
                  ),
                ),
              const Spacer(),
              if (compact)
                IconButton(
                  onPressed: onOpenReport,
                  icon: const Icon(Icons.flag_outlined),
                  tooltip: state.t('actions.reportProblem'),
                )
              else
                TextButton.icon(
                  onPressed: onOpenReport,
                  icon: const Icon(Icons.flag_outlined),
                  label: Text(state.t('actions.reportProblem')),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.state, required this.inputController});

  final AppState state;
  final TextEditingController inputController;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? _borderDark : _borderLight;
    final muted = isDark ? _mutedDark : _mutedLight;

    final sourceText = inputController.text;
    final correctionText = state.correctedText;
    final words = _wordCount(sourceText);
    final chars = sourceText.characters.length;

    final canSubmit = sourceText.trim().isNotEmpty && !state.isStreaming;
    final canCopy = correctionText.trim().isNotEmpty;
    final canReplace = correctionText.trim().isNotEmpty;

    final actionControls = [
      if (state.isStreaming)
        OutlinedButton.icon(
          onPressed: state.stopStreaming,
          icon: const Icon(Icons.stop_rounded),
          label: Text(state.t('actions.stopped')),
        )
      else
        FilledButton.icon(
          onPressed: canSubmit ? state.submit : null,
          icon: const Icon(Icons.auto_fix_high),
          label: Text(state.t('actions.correctText')),
        ),
      const SizedBox(width: 8),
      IconButton(
        tooltip: state.t('actions.copy'),
        onPressed: canCopy
            ? () => _copyToClipboard(context, state, correctionText)
            : null,
        icon: const Icon(Icons.content_copy),
      ),
      IconButton(
        onPressed: () {
          inputController.clear();
          state.updateOriginalText('');
        },
        icon: const Icon(Icons.delete_sweep),
        tooltip: state.t('actions.clearOriginal'),
      ),
      IconButton(
        onPressed: canReplace
            ? () {
                final next = correctionText;
                inputController.text = next;
                inputController.selection = TextSelection.fromPosition(
                  TextPosition(offset: next.length),
                );
                state.updateOriginalText(next);
              }
            : null,
        icon: const Icon(Icons.swap_horiz),
        tooltip: state.t('actions.replaceOriginal'),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
            color: Theme.of(context).cardColor,
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: actionControls),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 14,
                      runSpacing: 4,
                      children: [
                        Text(
                          state.t('metrics.words', vars: {'count': '$words'}),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: muted,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        Text(
                          state.t(
                            'metrics.characters',
                            vars: {'count': '$chars'},
                          ),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: muted,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    ...actionControls,
                    const Spacer(),
                    Text(
                      state.t('metrics.words', vars: {'count': '$words'}),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Text(
                      state.t('metrics.characters', vars: {'count': '$chars'}),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _HistoryRail extends StatelessWidget {
  const _HistoryRail({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? _borderDark : _borderLight;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
        color: Theme.of(context).cardColor,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Text(
                  state.t('history.title'),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                const Icon(Icons.history, size: 18),
              ],
            ),
          ),
          Divider(height: 1, color: border),
          Expanded(
            child: state.history.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Text(state.t('history.empty')),
                    ),
                  )
                : ListView.builder(
                    itemCount: state.history.length,
                    itemBuilder: (context, index) {
                      final item = state.history[index];
                      return InkWell(
                        onTap: () => unawaited(state.loadHistoryItem(item)),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _formatTimestamp(item.timestamp),
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(color: _brandColor),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _shortPreview(item.original),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _shortPreview(item.corrected),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

Future<void> _copyToClipboard(
  BuildContext context,
  AppState state,
  String text,
) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(state.t('actions.copied'))),
    );
  } on Object catch (_) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(state.t('errors.copyFailed'))),
    );
  }
}

String _formatTimestamp(DateTime timestamp) {
  final local = timestamp.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

int _wordCount(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return 0;
  }
  return trimmed.split(RegExp(r'\s+')).length;
}

String _shortPreview(String value) {
  final oneLine = value.replaceAll('\n', ' ').trim();
  if (oneLine.length <= 110) {
    return oneLine;
  }
  return '${oneLine.substring(0, 107)}...';
}
