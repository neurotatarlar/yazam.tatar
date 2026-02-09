// Flutter app entrypoint and primary chat-style UI.
//
// This module wires theming, keyboard shortcuts, split-panel behavior,
// and deferred loading of bottom-sheet tools used by the home screen.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'sheets/history_sheet.dart' deferred as history_sheet;
import 'sheets/report_sheet.dart' deferred as report_sheet;
import 'sheets/settings_sheet.dart' deferred as settings_sheet;

const _seedColor = Color(0xFF4C6A5C);
const _surfaceLight = Color(0xFFFBFAF7);
const _canvasLight = Color(0xFFF1EEE7);
const _mutedLight = Color(0xFF8A8578);
const _borderLight = Color(0xFFE2DDD3);
const _originalLight = Color(0xFFF6F4EE);
const _correctedLight = Color(0xFFEFF4EF);

const _surfaceDark = Color(0xFF1C1F1C);
const _canvasDark = Color(0xFF121412);
const _borderDark = Color(0xFF2C322D);
const _originalDark = Color(0xFF1D201E);
const _correctedDark = Color(0xFF1F2A23);

/// Computes side padding that keeps content centered on wide screens.
double _sidePadding(BuildContext context) {
  final width = MediaQuery.of(context).size.width;
  if (width <= 900) {
    return 20;
  }
  return (width - 900) / 2;
}

/// Keyboard intent to focus the composer input.
class _FocusComposerIntent extends Intent {
  const _FocusComposerIntent();
}

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
            theme: _buildTheme(state, Brightness.light),
            darkTheme: _buildTheme(state, Brightness.dark),
            builder: (context, child) {
              final media = MediaQuery.of(context);
              final baseScale = media.textScaler.scale(1);
              return MediaQuery(
                data: media.copyWith(
                  textScaler: TextScaler.linear(
                    baseScale * state.settings.fontScale,
                  ),
                ),
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: const HomePage(),
          );
        },
      ),
    );
  }

  /// Builds the light/dark theme palette from app settings.
  ThemeData _buildTheme(AppState state, Brightness brightness) {
    final base = ThemeData(
      brightness: brightness,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seedColor,
        brightness: brightness,
      ),
      scaffoldBackgroundColor: brightness == Brightness.dark
          ? _canvasDark
          : _canvasLight,
      cardColor: brightness == Brightness.dark ? _surfaceDark : _surfaceLight,
      dividerColor: brightness == Brightness.dark ? _borderDark : _borderLight,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brightness == Brightness.dark ? _surfaceDark : _surfaceLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: brightness == Brightness.dark ? _borderDark : _borderLight,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: brightness == Brightness.dark ? _borderDark : _borderLight,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _seedColor, width: 1.2),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );

    final textTheme = base.textTheme.apply(
      fontFamily: kIsWeb ? 'system-ui' : null,
      fontFamilyFallback: const [
        'Noto Sans',
        'Noto Sans UI',
        'Segoe UI',
        'Roboto',
        'Helvetica Neue',
        'Arial',
        'sans-serif',
      ],
    );

    return base.copyWith(textTheme: textTheme);
  }
}

/// Home screen that hosts the chat-style UI.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

/// State controller for the home screen interactions.
class _HomePageState extends State<HomePage> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _feedController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();
  DateTime _lastInteraction = DateTime.fromMillisecondsSinceEpoch(0);
  bool _allowBlur = false;
  bool _isFillingHistory = false;

  @override
  void initState() {
    super.initState();
    _feedController.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(context.read<AppState>().hydrate());
      }
      _scrollToBottom();
      unawaited(_fillHistoryToViewport());
      _focusComposer();
    });
    _inputFocusNode.addListener(_handleInputFocusChange);
  }

  @override
  void dispose() {
    _inputController.dispose();
    _feedController
      ..removeListener(_handleScroll)
      ..dispose();
    _inputFocusNode
      ..removeListener(_handleInputFocusChange)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    _syncInputController(state);

    return Listener(
      onPointerDown: _handlePointerDown,
      child: Shortcuts(
        shortcuts: <LogicalKeySet, Intent>{
          LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyK):
              const _FocusComposerIntent(),
          LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyK):
              const _FocusComposerIntent(),
        },
        child: Actions(
          actions: {
            _FocusComposerIntent: CallbackAction<_FocusComposerIntent>(
              onInvoke: (_) {
                _inputFocusNode.requestFocus();
                return null;
              },
            ),
          },
          child: Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  _TopBar(
                    state: state,
                    onLogoTap: () {
                      _scrollToBottom();
                      _focusComposer();
                    },
                  ),
                  Expanded(
                    child: _FeedList(state: state, controller: _feedController),
                  ),
                  _Composer(
                    state: state,
                    controller: _inputController,
                    focusNode: _inputFocusNode,
                    onIntentionalBlur: _markIntentionalBlur,
                  ),
                  _FooterActions(state: state),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Keep the text controller aligned with app state updates.
  void _syncInputController(AppState state) {
    if (_inputController.text != state.originalText) {
      _inputController.text = state.originalText;
      _inputController.selection = TextSelection.fromPosition(
        TextPosition(offset: _inputController.text.length),
      );
    }
  }

  /// Jump the feed list to the newest item.
  void _scrollToBottom() {
    if (!_feedController.hasClients) {
      return;
    }
    _feedController.jumpTo(_feedController.position.minScrollExtent);
  }

  /// Request focus for the input field when nothing else is focused.
  void _focusComposer() {
    if (_inputFocusNode.hasFocus) {
      return;
    }
    if (FocusManager.instance.primaryFocus != null) {
      return;
    }
    _inputFocusNode.requestFocus();
  }

  /// Load more history when the user approaches the end of the list.
  void _handleScroll() {
    if (!_feedController.hasClients) {
      return;
    }
    final position = _feedController.position;
    if (position.maxScrollExtent == 0) {
      return;
    }
    if (position.pixels >= position.maxScrollExtent - 120) {
      final state = context.read<AppState>();
      if (!state.isHistoryLoading && state.hasMoreHistory) {
        unawaited(
          state.loadMoreHistory().then((loaded) {
            if (loaded) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  unawaited(_fillHistoryToViewport());
                }
              });
            }
          }),
        );
      }
    }
  }

  /// Ensure enough history items exist to fill the visible area.
  Future<void> _fillHistoryToViewport() async {
    if (_isFillingHistory) {
      return;
    }
    _isFillingHistory = true;
    final state = context.read<AppState>();
    while (mounted) {
      if (!_feedController.hasClients) {
        break;
      }
      if (state.isHistoryLoading || !state.hasMoreHistory) {
        break;
      }
      final maxExtent = _feedController.position.maxScrollExtent;
      if (maxExtent > 80) {
        break;
      }
      final loaded = await state.loadMoreHistory();
      if (!mounted) {
        break;
      }
      if (!loaded) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (!mounted) {
        break;
      }
    }
    _isFillingHistory = false;
  }

  /// Track pointer interactions to avoid fighting intentional blurs.
  void _handlePointerDown(PointerDownEvent event) {
    _lastInteraction = DateTime.now();
    _allowBlur = true;
  }

  /// Mark that the user explicitly unfocused the composer.
  void _markIntentionalBlur() {
    _lastInteraction = DateTime.now();
    _allowBlur = true;
  }

  /// Restore focus unless the user just interacted elsewhere.
  void _handleInputFocusChange() {
    if (_inputFocusNode.hasFocus) {
      _allowBlur = false;
      return;
    }
    final sinceInteraction = DateTime.now()
        .difference(_lastInteraction)
        .inMilliseconds;
    if (_allowBlur && sinceInteraction < 800) {
      _allowBlur = false;
      return;
    }
    _restoreInputFocus();
  }

  /// Re-focus the composer after a short delay.
  void _restoreInputFocus() {
    Future<void>.delayed(const Duration(milliseconds: 80), () {
      if (!mounted) {
        return;
      }
      if (_inputFocusNode.hasFocus) {
        return;
      }
      _inputFocusNode.requestFocus();
    });
  }
}

/// Header row with language selector and actions.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.state, this.onLogoTap});

  final AppState state;
  final VoidCallback? onLogoTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: _sidePadding(context),
        vertical: 12,
      ),
      child: Row(
        children: [
          _LogoButton(title: state.config.appName, onTap: onLogoTap),
          const Spacer(),
          DropdownButton<String>(
            value: state.settings.language,
            underline: const SizedBox.shrink(),
            focusColor: Colors.transparent,
            items: [
              DropdownMenuItem(
                value: 'en',
                child: Text(state.t('language.en')),
              ),
              DropdownMenuItem(
                value: 'tt',
                child: Text(state.t('language.tt')),
              ),
              DropdownMenuItem(
                value: 'ru',
                child: Text(state.t('language.ru')),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              unawaited(state.setLanguage(value));
              FocusManager.instance.primaryFocus?.unfocus();
            },
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => _openHistory(context, state),
            child: Text(state.t('history.title')),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _openSettings(context, state),
          ),
        ],
      ),
    );
  }

  /// Open history sheet dialog or bottom sheet depending on screen size.
  Future<void> _openHistory(BuildContext context, AppState state) async {
    await history_sheet.loadLibrary();
    if (!context.mounted) {
      return;
    }
    final isMobile = MediaQuery.of(context).size.width < 900;
    if (isMobile) {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => history_sheet.HistorySheet(state: state),
      );
    } else {
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(child: history_sheet.HistorySheet(state: state)),
      );
    }
  }

  /// Open settings sheet as a modal bottom sheet.
  Future<void> _openSettings(BuildContext context, AppState state) async {
    await settings_sheet.loadLibrary();
    if (!context.mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => settings_sheet.SettingsSheet(state: state),
    );
  }
}

/// Scrollable feed of current and historical corrections.
class _FeedList extends StatelessWidget {
  const _FeedList({required this.state, required this.controller});

  final AppState state;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final hasActive =
        state.activeOriginal.isNotEmpty ||
        state.isStreaming ||
        state.correctedText.isNotEmpty;
    final itemCount = state.history.length + (hasActive ? 1 : 0);

    if (itemCount == 0) {
      return ListView(
        controller: controller,
        padding: EdgeInsets.fromLTRB(
          _sidePadding(context),
          24,
          _sidePadding(context),
          24,
        ),
        children: [
          _EmptyState(state: state),
          if (state.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: _InlineError(message: state.errorMessage!),
            ),
        ],
      );
    }

    return ListView.builder(
      controller: controller,
      reverse: true,
      padding: EdgeInsets.fromLTRB(
        _sidePadding(context),
        16,
        _sidePadding(context),
        16,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        final showDivider = index < itemCount - 1;
        if (hasActive && index == 0) {
          return Column(
            children: [
              _ChatPair(
                original: state.activeOriginal,
                corrected: state.correctedText,
                isStreaming: state.isStreaming,
                errorMessage: state.errorMessage,
                timestamp: state.activeTimestamp,
                feedbackChoice: state.activeFeedback,
                onFeedbackChange: state.toggleActiveFeedback,
                onReport: () => _openReportSheet(context, state),
                reportLabel: state.t('actions.reportProblem'),
                onCopyOriginal: state.activeOriginal.isNotEmpty
                    ? (anchor) =>
                          _copyToClipboard(anchor, state, state.activeOriginal)
                    : null,
                onCopyCorrected:
                    state.correctedText.isNotEmpty || state.errorMessage != null
                    ? (anchor) => _copyToClipboard(
                        anchor,
                        state,
                        state.correctedText.isNotEmpty
                            ? state.correctedText
                            : (state.errorMessage ?? ''),
                      )
                    : null,
                onRetry: state.errorMessage != null ? state.retry : null,
                retryLabel: state.t('actions.retry'),
                wasCanceled: state.wasCanceled,
                stoppedLabel: state.t('actions.stopped'),
                showFeedback: !state.isStreaming,
              ),
              if (showDivider)
                _ChatDivider(color: Theme.of(context).dividerColor),
            ],
          );
        }
        final item = state.history[index - (hasActive ? 1 : 0)];
        return Column(
          children: [
            _ChatPair(
              original: item.original,
              corrected: item.corrected,
              timestamp: item.timestamp,
              stoppedLabel: state.t('actions.stopped'),
              showFeedback: true,
              feedbackChoice: state.feedbackForItem(item),
              onFeedbackChange: (choice) {
                state.toggleHistoryFeedback(item.id, choice);
              },
              onReport: () => _openReportSheet(context, state),
              reportLabel: state.t('actions.reportProblem'),
              onCopyOriginal: (anchor) =>
                  _copyToClipboard(anchor, state, item.original),
              onCopyCorrected: (anchor) =>
                  _copyToClipboard(anchor, state, item.corrected),
            ),
            if (showDivider)
              _ChatDivider(color: Theme.of(context).dividerColor),
          ],
        );
      },
    );
  }
}

/// Placeholder content when no history exists.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? Colors.grey.shade400 : _mutedLight;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            state.t('empty.title'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            state.t('empty.body'),
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }
}

/// App logo and title button.
class _LogoButton extends StatelessWidget {
  const _LogoButton({required this.title, this.onTap});

  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textStyle = theme.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: 0.2,
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: scheme.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                'Ә',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: scheme.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(title, style: textStyle),
          ],
        ),
      ),
    );
  }
}

/// Inline error banner for failed requests.
class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

/// One pair of user + assistant messages.
class _ChatPair extends StatelessWidget {
  const _ChatPair({
    required this.original,
    required this.corrected,
    this.isStreaming = false,
    this.errorMessage,
    this.wasCanceled = false,
    this.stoppedLabel,
    this.showFeedback = false,
    this.feedbackChoice = FeedbackChoice.none,
    this.onFeedbackChange,
    this.onReport,
    this.reportLabel,
    this.timestamp,
    this.onCopyOriginal,
    this.onCopyCorrected,
    this.onRetry,
    this.retryLabel,
  });

  final String original;
  final String corrected;
  final bool isStreaming;
  final String? errorMessage;
  final bool wasCanceled;
  final String? stoppedLabel;
  final bool showFeedback;
  final FeedbackChoice feedbackChoice;
  final void Function(FeedbackChoice choice)? onFeedbackChange;
  final VoidCallback? onReport;
  final String? reportLabel;
  final DateTime? timestamp;
  final Future<void> Function(BuildContext)? onCopyOriginal;
  final Future<void> Function(BuildContext)? onCopyCorrected;
  final VoidCallback? onRetry;
  final String? retryLabel;

  @override
  Widget build(BuildContext context) {
    final showAssistant =
        corrected.isNotEmpty ||
        isStreaming ||
        errorMessage != null ||
        wasCanceled;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MessageBubble(
            text: original,
            isUser: true,
            timestamp: timestamp,
            onCopy: onCopyOriginal,
          ),
          if (showAssistant) ...[
            const SizedBox(height: 12),
            _MessageBubble(
              text: corrected.isNotEmpty ? corrected : (errorMessage ?? ''),
              isUser: false,
              isStreaming: isStreaming,
              isError: errorMessage != null,
              wasCanceled: wasCanceled,
              stoppedLabel: stoppedLabel,
              showFeedback: showFeedback,
              feedbackChoice: feedbackChoice,
              onFeedbackChange: onFeedbackChange,
              onReport: onReport,
              reportLabel: reportLabel,
              timestamp: timestamp,
              onCopy: onCopyCorrected,
              onRetry: errorMessage != null ? onRetry : null,
              retryLabel: retryLabel,
            ),
          ],
        ],
      ),
    );
  }
}

/// Divider used between chat pairs.
class _ChatDivider extends StatelessWidget {
  const _ChatDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Divider(
        height: 1,
        thickness: 1,
        color: color.withValues(alpha: 0.35),
        indent: 80,
        endIndent: 80,
      ),
    );
  }
}

/// Single chat bubble with metadata row.
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.text,
    required this.isUser,
    this.isStreaming = false,
    this.isError = false,
    this.wasCanceled = false,
    this.stoppedLabel,
    this.showFeedback = false,
    this.feedbackChoice = FeedbackChoice.none,
    this.onFeedbackChange,
    this.onReport,
    this.reportLabel,
    this.timestamp,
    this.onCopy,
    this.onRetry,
    this.retryLabel,
  });

  final String text;
  final bool isUser;
  final bool isStreaming;
  final bool isError;
  final bool wasCanceled;
  final String? stoppedLabel;
  final bool showFeedback;
  final FeedbackChoice feedbackChoice;
  final void Function(FeedbackChoice choice)? onFeedbackChange;
  final VoidCallback? onReport;
  final String? reportLabel;
  final DateTime? timestamp;
  final Future<void> Function(BuildContext)? onCopy;
  final VoidCallback? onRetry;
  final String? retryLabel;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bubbleColor = isError
        ? Theme.of(context).colorScheme.errorContainer
        : isUser
        ? (isDark ? _originalDark : _originalLight)
        : (isDark ? _correctedDark : _correctedLight);
    final textColor = isError
        ? Theme.of(context).colorScheme.onErrorContainer
        : null;
    final metaColor = isDark ? Colors.grey.shade400 : _mutedLight;
    final showTyping = isStreaming && text.isEmpty && !isError;
    final displayText = text.isNotEmpty ? text : '';

    final showTimestamp = timestamp != null && isUser;
    final showFeedbackRow = !isUser && !isStreaming && showFeedback;
    final showUp = feedbackChoice != FeedbackChoice.down;
    final showDown = feedbackChoice != FeedbackChoice.up;
    final isUpSelected = feedbackChoice == FeedbackChoice.up;
    final isDownSelected = feedbackChoice == FeedbackChoice.down;
    final showMetaRow = showTimestamp || onCopy != null || showFeedbackRow;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.6),
                ),
              ),
              child: showTyping
                  ? _TypingIndicator(color: metaColor)
                  : SelectableText(
                      displayText,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        height: 1.5,
                        color: textColor,
                      ),
                    ),
            ),
            if (showMetaRow)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showTimestamp)
                      Text(
                        _formatTimestamp(timestamp!),
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: metaColor),
                      ),
                    if (showTimestamp && onCopy != null)
                      const SizedBox(width: 6),
                    if (onCopy != null)
                      Builder(
                        builder: (iconContext) => IconButton(
                          onPressed: () async => onCopy!(iconContext),
                          icon: _CopyGlyph(
                            color: metaColor,
                            background: Theme.of(
                              context,
                            ).scaffoldBackgroundColor,
                          ),
                          tooltip: 'Copy',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          iconSize: 16,
                          color: metaColor,
                        ),
                      ),
                    if (showFeedbackRow) ...[
                      if (onCopy != null || showTimestamp)
                        const SizedBox(width: 6),
                      if (showUp)
                        IconButton(
                          onPressed: onFeedbackChange == null
                              ? null
                              : () => onFeedbackChange!(FeedbackChoice.up),
                          icon: Icon(
                            isUpSelected
                                ? Icons.thumb_up_alt
                                : Icons.thumb_up_alt_outlined,
                          ),
                          iconSize: 18,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          color: isUpSelected
                              ? Theme.of(context).colorScheme.primary
                              : metaColor,
                        ),
                      if (showDown)
                        IconButton(
                          onPressed: onFeedbackChange == null
                              ? null
                              : () => onFeedbackChange!(FeedbackChoice.down),
                          icon: Icon(
                            isDownSelected
                                ? Icons.thumb_down_alt
                                : Icons.thumb_down_alt_outlined,
                          ),
                          iconSize: 18,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          color: isDownSelected
                              ? Theme.of(context).colorScheme.primary
                              : metaColor,
                        ),
                      if (onReport != null) ...[
                        const SizedBox(width: 6),
                        TextButton(
                          onPressed: onReport,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(0, 28),
                          ),
                          child: Text(
                            reportLabel ?? '',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: metaColor,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            if (isError && onRetry != null)
              Align(
                alignment: isUser
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(retryLabel ?? 'Retry'),
                ),
              ),
            if (wasCanceled && !isStreaming)
              Align(
                alignment: isUser
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    stoppedLabel ?? 'Stopped',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: metaColor,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Animated typing indicator for streaming responses.
class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator({required this.color});

  final Color color;

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

/// Lightweight toast used for clipboard feedback.
class _CopyToast extends StatelessWidget {
  const _CopyToast({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark ? const Color(0xFF2A2E2B) : Colors.white;
    final border = isDark ? const Color(0xFF3B403C) : const Color(0xFFE0DAD0);
    final textColor = isDark ? Colors.white : const Color(0xFF2D2D2D);

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          message,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: textColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Custom painter-based copy glyph used in the toolbar.
class _CopyGlyph extends StatelessWidget {
  const _CopyGlyph({required this.color, required this.background});

  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()..rotateY(math.pi),
      child: CustomPaint(
        size: const Size(19, 19),
        painter: _CopyGlyphPainter(color, background),
      ),
    );
  }
}

/// Draws the overlapping-square copy icon.
class _CopyGlyphPainter extends CustomPainter {
  _CopyGlyphPainter(this.color, this.background);

  final Color color;
  final Color background;

  @override
  /// Paint the two overlapping rounded rectangles.
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = background
      ..style = PaintingStyle.fill;
    const backRect = Rect.fromLTWH(2.2, 2.2, 10.6, 10.6);
    const frontRect = Rect.fromLTWH(6.2, 6.2, 10.6, 10.6);
    final back = RRect.fromRectAndRadius(backRect, const Radius.circular(3.6));
    final front = RRect.fromRectAndRadius(
      frontRect,
      const Radius.circular(3.6),
    );
    canvas
      ..drawRRect(back, stroke)
      ..drawRRect(front, fill)
      ..drawRRect(front, stroke);
  }

  @override
  /// Repaint when colors change.
  bool shouldRepaint(covariant _CopyGlyphPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.background != background;
  }
}

/// Animates the typing indicator dots.
class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<Animation<double>> _dotAnimations;

  @override
  /// Initialize the looping dot animations.
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    unawaited(_controller.repeat());
    _dotAnimations = List.generate(3, (index) {
      final start = index * 0.2;
      final end = start + 0.6;
      return CurvedAnimation(
        parent: _controller,
        curve: Interval(start, end, curve: Curves.easeInOut),
      );
    });
  }

  @override
  /// Dispose of the animation controller.
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  /// Build the animated dot row.
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return FadeTransition(
          opacity: _dotAnimations[index],
          child: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// Input row with composer and send/stop controls.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.state,
    required this.controller,
    required this.focusNode,
    this.onIntentionalBlur,
  });

  final AppState state;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback? onIntentionalBlur;

  @override
  Widget build(BuildContext context) {
    final canSend = controller.text.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        _sidePadding(context),
        0,
        _sidePadding(context),
        12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Focus(
              onKeyEvent: (_, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.escape) {
                  onIntentionalBlur?.call();
                  focusNode.unfocus();
                  return KeyEventResult.handled;
                }
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.enter &&
                    !HardwareKeyboard.instance.isShiftPressed) {
                  if (canSend) {
                    unawaited(state.submit());
                  }
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: true,
                minLines: 1,
                maxLines: 6,
                onChanged: state.updateOriginalText,
                decoration: InputDecoration(
                  hintText: state.t('input.placeholder'),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 48,
            width: 48,
            child: state.isStreaming
                ? OutlinedButton(
                    onPressed: state.stopStreaming,
                    style: OutlinedButton.styleFrom(
                      shape: const CircleBorder(),
                      padding: EdgeInsets.zero,
                    ),
                    child: const Icon(Icons.stop_rounded),
                  )
                : ElevatedButton(
                    onPressed: canSend ? state.submit : null,
                    style: ElevatedButton.styleFrom(
                      shape: const CircleBorder(),
                      padding: EdgeInsets.zero,
                    ),
                    child: const Icon(Icons.arrow_upward),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Footer area for transient status text.
class _FooterActions extends StatelessWidget {
  const _FooterActions({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final status = state.statusText;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? Colors.grey.shade400 : _mutedLight;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        _sidePadding(context),
        0,
        _sidePadding(context),
        12,
      ),
      child: Row(
        children: [
          if (status.isNotEmpty)
            Text(
              status,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: muted),
            ),
        ],
      ),
    );
  }
}

/// Copy text to clipboard and show a toast.
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
    _showCopyToast(context, state.t('actions.copied'));
  } on Object catch (_) {
    if (!context.mounted) {
      return;
    }
    _showCopyToast(context, state.t('errors.copyFailed'));
  }
}

/// Open the report problem sheet for the current request.
Future<void> _openReportSheet(BuildContext context, AppState state) async {
  await report_sheet.loadLibrary();
  if (!context.mounted) {
    return;
  }
  final isMobile = MediaQuery.of(context).size.width < 900;
  if (isMobile) {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => report_sheet.ReportSheet(state: state),
    );
  } else {
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(child: report_sheet.ReportSheet(state: state)),
    );
  }
}

/// Format a timestamp as HH:mm.
String _formatTimestamp(DateTime timestamp) {
  final local = timestamp.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

/// Show a small toast above the tapped element.
void _showCopyToast(BuildContext context, String message) {
  final overlay = Overlay.of(context);
  final renderBox = context.findRenderObject() as RenderBox?;
  final overlayBox = overlay.context.findRenderObject() as RenderBox?;
  if (renderBox == null || overlayBox == null) {
    return;
  }

  final target = renderBox.localToGlobal(Offset.zero, ancestor: overlayBox);
  const double toastWidth = 72;
  const double toastHeight = 28;
  const double toastPadding = 8;
  const double toastGap = 6;
  final left = math.max(
    toastPadding,
    math.min(
      target.dx + renderBox.size.width / 2 - toastWidth / 2,
      overlayBox.size.width - toastWidth - toastPadding,
    ),
  );
  final top = math.max(
    toastPadding,
    math.min(
      target.dy - toastHeight - toastGap,
      overlayBox.size.height - toastHeight - toastPadding,
    ),
  );

  final entry = OverlayEntry(
    builder: (context) => Positioned(
      left: left,
      top: top,
      child: _CopyToast(message: message),
    ),
  );
  overlay.insert(entry);
  Future<void>.delayed(const Duration(milliseconds: 900), entry.remove);
}
