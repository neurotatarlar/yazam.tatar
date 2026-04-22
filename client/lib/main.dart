// Main Flutter UI for the Tatar GEC client.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_state.dart';
import 'models.dart';

const _brandColor = Color(0xFF4F46E5);
const _bg = Color(0xFFFAF8FF);
const _headerBg = Color(0xFFF8FAFC);
const _sidebarBg = Color(0xFFF1F5F9);
const _surface = Color(0xFFFFFFFF);
const _surfaceLow = Color(0xFFF2F3FF);
const _surfaceHigh = Color(0xFFE2E7FF);
const _text = Color(0xFF131B2E);
const _muted = Color(0xFF76777D);
const _outline = Color(0xFFC6C6CD);
const _shellBorder = Color(0x1F9CA6BA);

const _sidebarWidth = 256.0;
const _headerHeight = 64.0;
const _wordmark = 'YAZAM.TATAR';
const _tbankDonationUrl = 'https://www.tbank.ru/cf/5DeXHs3nnOy';
const _revolutDonationUrl = 'https://revolut.me/gaydmi';

enum _ShellSection { workspace, history }

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
            themeMode: ThemeMode.light,
            theme: _buildTheme(),
            home: const HomePage(),
          );
        },
      ),
    );
  }

  ThemeData _buildTheme() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: _brandColor,
        ).copyWith(
          surface: _surface,
          onSurface: _text,
          onSurfaceVariant: _muted,
          outline: _outline,
          outlineVariant: _surfaceHigh,
        );

    final baseText = ThemeData(brightness: Brightness.light).textTheme.apply(
      fontFamily: 'Inter',
      fontFamilyFallback: const [
        'Manrope',
        'Newsreader',
        'Noto Sans',
        'Noto Sans UI',
        'Segoe UI',
        'Roboto',
        'Arial',
        'sans-serif',
      ],
      bodyColor: _text,
      displayColor: _text,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: _bg,
      cardColor: _surface,
      dividerColor: _outline,
      textTheme: baseText.copyWith(
        titleLarge: baseText.titleLarge?.copyWith(
          fontFamily: 'Manrope',
          fontWeight: FontWeight.w800,
        ),
        titleMedium: baseText.titleMedium?.copyWith(
          fontFamily: 'Manrope',
          fontWeight: FontWeight.w700,
        ),
        titleSmall: baseText.titleSmall?.copyWith(
          fontFamily: 'Manrope',
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: baseText.bodyLarge?.copyWith(
          fontFamily: 'Newsreader',
          fontSize: 20,
          height: 1.55,
        ),
        labelSmall: baseText.labelSmall?.copyWith(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _outline),
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
        child: Column(
          children: [
            _HeaderBar(
              state: state,
              onBrandTap: _focusWorkspaceInput,
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Sidebar(
                    state: state,
                    section: _ShellSection.workspace,
                    onOpenHistory: _openHistoryPage,
                    onOpenSupport: (url) => _openExternal(context, state, url),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final workspaceHeight = (constraints.maxHeight * 0.42)
                            .clamp(280.0, 380.0);
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(
                                  height: workspaceHeight,
                                  child: _WorkspacePanel(
                                    state: state,
                                    inputController: _inputController,
                                    inputFocusNode: _inputFocusNode,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                _ActionBar(
                                  state: state,
                                  inputController: _inputController,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
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

  void _syncInputController(AppState state) {
    if (_inputController.text == state.originalText) {
      return;
    }
    _inputController.text = state.originalText;
    _inputController.selection = TextSelection.fromPosition(
      TextPosition(offset: _inputController.text.length),
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

  void _focusWorkspaceInput() {
    if (!mounted) {
      return;
    }
    _inputFocusNode.requestFocus();
  }

  void _openHistoryPage() {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/history'),
          builder: (_) => const HistoryPage(),
        ),
      ),
    );
  }
}

/// Dedicated read-only history page.
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_loadAllHistory());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _HeaderBar(
              state: state,
              onBrandTap: _goWorkspace,
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Sidebar(
                    state: state,
                    section: _ShellSection.history,
                    onOpenWorkspace: _goWorkspace,
                    onOpenSupport: (url) => _openExternal(context, state, url),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                      child: _HistoryPanel(state: state),
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

  Future<void> _loadAllHistory() async {
    final state = context.read<AppState>();
    while (mounted && state.hasMoreHistory) {
      final loaded = await state.loadMoreHistory();
      if (!loaded) {
        break;
      }
    }
  }

  void _goWorkspace() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
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

class _HeaderBar extends StatelessWidget {
  const _HeaderBar({required this.state, required this.onBrandTap});

  final AppState state;
  final VoidCallback onBrandTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _headerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: _headerBg,
        border: Border.fromBorderSide(BorderSide(color: _shellBorder)),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: onBrandTap,
            mouseCursor: SystemMouseCursors.click,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              child: Row(
                children: [
                  Image.asset(
                    'assets/brand/tulip.png',
                    width: 26,
                    height: 26,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _wordmark,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontFamily: 'Manrope',
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.8,
                    ),
                  ),
                ],
              ),
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
    Widget code(String lang, String label) {
      final selected = state.settings.language == lang;
      return InkWell(
        onTap: () => unawaited(state.setLanguage(lang)),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: selected ? _brandColor : _muted,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            letterSpacing: 0.4,
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: _surfaceLow,
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          code('tt', 'TT'),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Text('/', style: TextStyle(color: _outline)),
          ),
          code('en', 'EN'),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Text('/', style: TextStyle(color: _outline)),
          ),
          code('ru', 'RU'),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.state,
    required this.section,
    required this.onOpenSupport,
    this.onOpenWorkspace,
    this.onOpenHistory,
  });

  final AppState state;
  final _ShellSection section;
  final Future<void> Function(String url) onOpenSupport;
  final VoidCallback? onOpenWorkspace;
  final VoidCallback? onOpenHistory;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _sidebarWidth,
      decoration: const BoxDecoration(
        color: _sidebarBg,
        border: Border.fromBorderSide(BorderSide(color: _shellBorder)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 26),
          const Padding(
            padding: EdgeInsets.only(left: 20, right: 210, bottom: 14),
            child: SizedBox(
              height: 2,
              child: DecoratedBox(
                decoration: BoxDecoration(color: _brandColor),
              ),
            ),
          ),
          _SidebarItem(
            icon: Icons.edit_note,
            label: state.t('nav.workspace'),
            selected: section == _ShellSection.workspace,
            onTap: section == _ShellSection.workspace ? null : onOpenWorkspace,
          ),
          _SidebarItem(
            icon: Icons.history,
            label: state.t('history.title'),
            selected: section == _ShellSection.history,
            onTap: section == _ShellSection.history ? null : onOpenHistory,
          ),
          _SupportItem(
            state: state,
            onOpenSupport: onOpenSupport,
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.t('partners.title').toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: _muted,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 10),
                const _PartnerLogo(
                  assetPath: 'assets/partners/minmol.png',
                ),
                const SizedBox(height: 8),
                const _PartnerLogo(
                  assetPath: 'assets/partners/tatfor.png',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PartnerLogo extends StatelessWidget {
  const _PartnerLogo({required this.assetPath});

  final String assetPath;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 68,
      child: FittedBox(
        alignment: Alignment.centerLeft,
        fit: BoxFit.scaleDown,
        child: Image.asset(
          assetPath,
          height: 64,
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? _brandColor : _text.withValues(alpha: 0.72);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          decoration: BoxDecoration(
            color: selected ? _surfaceHigh : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 18, color: fg),
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

class _SupportItem extends StatelessWidget {
  const _SupportItem({required this.state, required this.onOpenSupport});

  final AppState state;
  final Future<void> Function(String url) onOpenSupport;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            const Icon(
              Icons.favorite,
              size: 18,
              color: Color(0xFFF43F5E),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                state.t('nav.support'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _text.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _DonationImageGlyph(
              assetPath: 'assets/support/tbank_shield.png',
              tooltip: state.t('support.tbank'),
              onTap: () => unawaited(onOpenSupport(_tbankDonationUrl)),
            ),
            const SizedBox(width: 6),
            _DonationImageGlyph(
              assetPath: 'assets/support/revolut_r.png',
              tooltip: state.t('support.revolut'),
              onTap: () => unawaited(onOpenSupport(_revolutDonationUrl)),
            ),
          ],
        ),
      ),
    );
  }
}

class _DonationImageGlyph extends StatelessWidget {
  const _DonationImageGlyph({
    required this.assetPath,
    required this.tooltip,
    required this.onTap,
  });

  final String assetPath;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 20,
          height: 20,
          child: Image.asset(
            assetPath,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}

class _HistoryPanel extends StatelessWidget {
  const _HistoryPanel({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    if (state.history.isEmpty) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _shellBorder),
          color: _surface,
        ),
        padding: const EdgeInsets.all(20),
        child: Text(
          state.t('history.empty'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: _muted,
          ),
        ),
      );
    }

    final groups = _groupHistoryByDay(state.history);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _shellBorder),
        color: _surface,
      ),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: groups.length,
        separatorBuilder: (_, _) => const SizedBox(height: 18),
        itemBuilder: (context, index) {
          final group = groups[index];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                group.day,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: _muted,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < group.items.length; i++) ...[
                _HistoryCard(
                  item: group.items[i],
                  state: state,
                ),
                if (i != group.items.length - 1) const SizedBox(height: 10),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.item, required this.state});

  final HistoryItem item;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: _surfaceLow,
        border: Border.all(color: _shellBorder),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatEuropeanTimestamp(item.timestamp),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: _muted,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            item.original.trim(),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: _muted,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            item.corrected.trim(),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: _brandColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryDayGroup {
  const _HistoryDayGroup({required this.day, required this.items});

  final String day;
  final List<HistoryItem> items;
}

List<_HistoryDayGroup> _groupHistoryByDay(List<HistoryItem> items) {
  final grouped = <String, List<HistoryItem>>{};
  for (final item in items) {
    final day = _formatEuropeanDate(item.timestamp);
    grouped.putIfAbsent(day, () => []).add(item);
  }
  return grouped.entries
      .map((entry) => _HistoryDayGroup(day: entry.key, items: entry.value))
      .toList();
}

String _formatEuropeanDate(DateTime timestamp) {
  final local = timestamp.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final year = local.year.toString().padLeft(4, '0');
  return '$day.$month.$year';
}

String _formatEuropeanTimestamp(DateTime timestamp) {
  final local = timestamp.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final year = local.year.toString().padLeft(4, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day.$month.$year $hour:$minute';
}

class _WorkspacePanel extends StatelessWidget {
  const _WorkspacePanel({
    required this.state,
    required this.inputController,
    required this.inputFocusNode,
  });

  final AppState state;
  final TextEditingController inputController;
  final FocusNode inputFocusNode;

  @override
  Widget build(BuildContext context) {
    final correctionText = state.correctedText;

    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth >= 960;

        final originalPane = Container(
          color: _surface,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                state.t('panel.original').toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: _muted,
                  letterSpacing: 1.2,
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
                  textAlignVertical: TextAlignVertical.top,
                  decoration: InputDecoration(
                    hintText: state.t('input.placeholder'),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ],
          ),
        );

        final correctionPane = Container(
          color: _surfaceLow,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    state.t('panel.corrected').toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: _brandColor,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Spacer(),
                  if (state.isStreaming)
                    Row(
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF10B981),
                            backgroundColor: Color(0x3310B981),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          state.t('status.correcting').toUpperCase(),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: const Color(0xFF10B981),
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
            ],
          ),
        );

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _shellBorder),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: horizontal
                ? Row(
                    children: [
                      Expanded(child: originalPane),
                      const SizedBox(
                        width: 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: _shellBorder),
                        ),
                      ),
                      Expanded(child: correctionPane),
                    ],
                  )
                : Column(
                    children: [
                      SizedBox(
                        height: constraints.maxHeight * 0.48,
                        child: originalPane,
                      ),
                      const SizedBox(
                        height: 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: _shellBorder),
                        ),
                      ),
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
      return Align(
        alignment: Alignment.topLeft,
        child: Text(
          state.errorMessage!,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Theme.of(context).colorScheme.error,
          ),
        ),
      );
    }

    if (state.isStreaming && correctionText.isEmpty) {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(
          state.t('status.correcting'),
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }

    if (correctionText.isNotEmpty) {
      return Align(
        alignment: Alignment.topLeft,
        child: SelectableText(
          correctionText,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }

    return Align(
      alignment: Alignment.topLeft,
      child: Text(
        state.t('empty.title'),
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: _muted),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.state, required this.inputController});

  final AppState state;
  final TextEditingController inputController;

  @override
  Widget build(BuildContext context) {
    final sourceText = inputController.text;
    final correctionText = state.correctedText;
    final words = _wordCount(sourceText);
    final chars = sourceText.characters.length;

    final canSubmit = sourceText.trim().isNotEmpty && !state.isStreaming;
    final canCopy = correctionText.trim().isNotEmpty;

    final actions = [
      if (state.isStreaming)
        OutlinedButton.icon(
          onPressed: state.stopStreaming,
          icon: const Icon(Icons.stop_rounded),
          label: Text(state.t('actions.stopped')),
        )
      else
        FilledButton.icon(
          onPressed: canSubmit ? state.submit : null,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          iconAlignment: IconAlignment.end,
          icon: const Icon(Icons.auto_fix_high, size: 16),
          label: Text(state.t('actions.correctText')),
        ),
      const SizedBox(width: 14),
      const SizedBox(
        width: 1,
        height: 32,
        child: DecoratedBox(decoration: BoxDecoration(color: _outline)),
      ),
      const SizedBox(width: 10),
      IconButton(
        tooltip: state.t('actions.copy'),
        onPressed: canCopy
            ? () => _copyToClipboard(context, state, correctionText)
            : null,
        icon: Icon(
          Icons.content_copy,
          size: 18,
          color: _text.withValues(alpha: 0.72),
        ),
      ),
      IconButton(
        onPressed: () {
          inputController.clear();
          state.updateOriginalText('');
        },
        tooltip: state.t('actions.clearOriginal'),
        icon: const Icon(Icons.delete, size: 18, color: Color(0xFFDC2626)),
      ),
    ];

    Widget metricsRow() => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          state.t('metrics.words', vars: {'count': '$words'}).toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: _muted,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 24),
        Text(
          state
              .t('metrics.characters', vars: {'count': '$chars'})
              .toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: _muted,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: _surfaceHigh,
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: actions),
                    ),
                    const SizedBox(height: 8),
                    metricsRow(),
                  ],
                )
              : SizedBox(
                  height: 42,
                  child: Row(
                    children: [
                      ...actions,
                      const Spacer(),
                      metricsRow(),
                    ],
                  ),
                ),
        );
      },
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

int _wordCount(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return 0;
  }
  return trimmed.split(RegExp(r'\s+')).length;
}
