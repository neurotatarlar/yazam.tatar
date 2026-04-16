// Central application state and interaction orchestration.
//
// Coordinates settings hydration, request streaming, history paging,
// feedback state, and view-level status updates for the client UI.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_config.dart';
import 'backend_client.dart';
import 'history_store.dart';
import 'i18n.dart';
import 'models.dart';
import 'settings_store.dart';

/// Represents user feedback on a correction.
enum FeedbackChoice { none, up, down }

/// ChangeNotifier that coordinates UI state, history, and streaming.
class AppState extends ChangeNotifier {
  AppState({
    required this.config,
    required this.settingsStore,
    required this.historyStore,
    required this.settings,
    required this.history,
    required Localizer localizer,
    this.autoHydrate = true,
    BackendClient? backend,
    bool? hasMoreHistory,
    int? loadedHistoryCount,
  }) : _localizer = localizer,
       _backend = backend ?? BackendClient(config.baseUrl),
       hasMoreHistory = hasMoreHistory ?? false,
       _loadedPersisted = loadedHistoryCount ?? history.length;

  final AppConfig config;
  final SettingsStore settingsStore;
  final HistoryStore historyStore;
  final Localizer _localizer;
  final BackendClient _backend;
  final bool autoHydrate;

  Settings settings;
  List<HistoryItem> history;
  String originalText = '';
  String correctedText = '';
  String? requestId;
  String? modelBackend;
  bool isStreaming = false;
  String statusText = '';
  String? errorMessage;
  bool wasCanceled = false;
  FeedbackChoice activeFeedback = FeedbackChoice.none;
  ExpandedPanel expandedPanel = ExpandedPanel.none;
  double splitRatio = 0.5;
  bool isHistoryLoading = false;
  bool hasMoreHistory;

  StreamSubscription<SseEvent>? _subscription;
  String activeOriginal = '';
  DateTime? activeTimestamp;
  int _loadedPersisted;
  final Map<String, FeedbackChoice> _historyFeedback = {};
  bool _didHydrate = false;
  bool _isHydrating = false;

  static const int historyPageSize = 6;

  /// Translate a string key using the loaded locale.
  String t(String key, {Map<String, String> vars = const {}}) =>
      _localizer.t(key, vars: vars);

  /// Switch the UI language and persist the selection.
  Future<void> setLanguage(String lang) async {
    await _localizer.load(lang);
    settings = settings.copyWith(language: lang);
    await settingsStore.save(settings);
    notifyListeners();
  }

  /// Load persisted settings and translations on startup.
  Future<void> hydrate() async {
    if (!autoHydrate || _didHydrate || _isHydrating) {
      return;
    }
    _isHydrating = true;
    try {
      final loaded = await settingsStore.load();
      final shouldLoadLocale =
          _localizer.strings.isEmpty || settings.language != loaded.language;
      settings = loaded;
      if (shouldLoadLocale) {
        await _localizer.load(loaded.language);
      }
    } on Object catch (_) {
      // Keep defaults on startup failure.
    } finally {
      _didHydrate = true;
      _isHydrating = false;
    }
    notifyListeners();
  }

  /// Replace settings and persist them.
  Future<void> updateSettings(Settings updated) async {
    settings = updated;
    await settingsStore.save(settings);
    notifyListeners();
  }

  /// Update the layout mode and reset the split ratio.
  void setLayout(LayoutMode mode) {
    settings = settings.copyWith(layoutMode: mode);
    unawaited(settingsStore.save(settings));
    resetSplit();
    notifyListeners();
  }

  /// Update the split ratio used by split layouts.
  void setSplitRatio(double ratio) {
    splitRatio = ratio.clamp(0.2, 0.8);
    notifyListeners();
  }

  /// Expand/collapse the requested panel.
  void toggleExpand(ExpandedPanel panel) {
    if (expandedPanel == panel) {
      expandedPanel = ExpandedPanel.none;
    } else {
      expandedPanel = panel;
    }
    notifyListeners();
  }

  /// Reset split ratio to the default midpoint.
  void resetSplit() {
    splitRatio = 0.5;
  }

  /// Update the input text and clear transient status.
  void updateOriginalText(String text) {
    originalText = text;
    if (statusText.isNotEmpty) {
      statusText = '';
    }
    errorMessage = null;
    notifyListeners();
  }

  /// Load a previous history entry into the composer.
  Future<void> loadHistoryItem(HistoryItem item) async {
    originalText = item.original;
    notifyListeners();
  }

  /// Clear all persisted and in-memory history.
  Future<void> clearHistory() async {
    history = [];
    await historyStore.clear();
    hasMoreHistory = false;
    _loadedPersisted = 0;
    _historyFeedback.clear();
    notifyListeners();
  }

  /// Look up feedback state for a given history item.
  FeedbackChoice feedbackForItem(HistoryItem item) {
    return _historyFeedback[item.id] ?? FeedbackChoice.none;
  }

  /// Update feedback for the active response.
  void toggleActiveFeedback(FeedbackChoice choice) {
    activeFeedback = _toggleFeedback(activeFeedback, choice);
    notifyListeners();
  }

  /// Update feedback state for a history item.
  void toggleHistoryFeedback(String id, FeedbackChoice choice) {
    final current = _historyFeedback[id] ?? FeedbackChoice.none;
    final next = _toggleFeedback(current, choice);
    if (next == FeedbackChoice.none) {
      _historyFeedback.remove(id);
    } else {
      _historyFeedback[id] = next;
    }
    notifyListeners();
  }

  /// Stop the current stream and mark it as canceled.
  Future<void> stopStreaming() async {
    isStreaming = false;
    statusText = '';
    wasCanceled = true;
    notifyListeners();
    await _subscription?.cancel();
    _subscription = null;
  }

  /// Load the next page of history for infinite scrolling.
  Future<bool> loadMoreHistory() async {
    if (isHistoryLoading || !hasMoreHistory) {
      return false;
    }
    isHistoryLoading = true;
    notifyListeners();
    final page = await historyStore.loadPage(
      offset: _loadedPersisted,
      limit: historyPageSize,
    );
    if (page.isNotEmpty) {
      history.addAll(page);
      _loadedPersisted += page.length;
    }
    if (page.length < historyPageSize) {
      hasMoreHistory = false;
    }
    isHistoryLoading = false;
    notifyListeners();
    return page.isNotEmpty;
  }

  /// Submit the current input for correction.
  Future<void> submit() async {
    final text = originalText.trim();
    if (text.isEmpty) {
      return;
    }
    await _startStream(text, resetTimestamp: true);
  }

  /// Retry correction for the active text.
  Future<void> retry() async {
    final text = activeOriginal.trim();
    if (text.isEmpty) {
      return;
    }
    await _startStream(text, resetTimestamp: false);
  }

  /// Start a new streaming correction request.
  Future<void> _startStream(String text, {required bool resetTimestamp}) async {
    if (config.baseUrl.isEmpty) {
      await _subscription?.cancel();
      _subscription = null;
      errorMessage = _localizer.t('errors.noBackendUrl');
      statusText = '';
      isStreaming = false;
      notifyListeners();
      return;
    }
    await _subscription?.cancel();

    activeOriginal = text;
    activeTimestamp = resetTimestamp
        ? DateTime.now()
        : (activeTimestamp ?? DateTime.now());
    correctedText = '';
    requestId = null;
    statusText = t('status.correcting');
    errorMessage = null;
    modelBackend = null;
    isStreaming = true;
    wasCanceled = false;
    activeFeedback = FeedbackChoice.none;
    notifyListeners();

    _subscription = _backend
        .streamCorrect(text: text, lang: 'tt', platform: 'flutter')
        .listen(_handleEvent, onError: _handleError, onDone: _handleDone);
  }

  /// Handle streamed SSE events from the backend.
  void _handleEvent(SseEvent event) {
    if (event.event == 'meta') {
      requestId = event.data['request_id']?.toString();
      modelBackend = event.data['model_backend']?.toString();
      notifyListeners();
      return;
    }
    if (event.event == 'delta') {
      correctedText += event.data['text']?.toString() ?? '';
      notifyListeners();
      return;
    }
    if (event.event == 'done') {
      final rawLatency = event.data['latency_ms'];
      final latency = rawLatency is int
          ? rawLatency
          : int.tryParse(rawLatency?.toString() ?? '') ?? 0;
      wasCanceled = false;
      unawaited(_finishStream(latency: latency));
    }
    if (event.event == 'error') {
      errorMessage = event.data['message']?.toString() ?? t('errors.stream');
      statusText = t('status.error');
      isStreaming = false;
      wasCanceled = false;
      notifyListeners();
    }
  }

  /// Handle transport-level stream errors.
  void _handleError(Object error) {
    errorMessage = error.toString();
    statusText = t('status.error');
    isStreaming = false;
    wasCanceled = false;
    notifyListeners();
  }

  /// Handle stream completion when no final event arrives.
  void _handleDone() {
    if (isStreaming) {
      wasCanceled = false;
      unawaited(_finishStream(latency: 0));
    }
  }

  /// Finalize a stream and persist history.
  Future<void> _finishStream({required int latency}) async {
    isStreaming = false;
    statusText = '';
    notifyListeners();

    final timestamp = activeTimestamp ?? DateTime.now();
    final item = HistoryItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      original: activeOriginal,
      corrected: correctedText,
      timestamp: timestamp,
      latencyMs: latency,
      requestId: requestId ?? '',
    );
    history.insert(0, item);
    if (history.length > HistoryStore.maxItems) {
      history.removeRange(HistoryStore.maxItems, history.length);
    }
    if (settings.saveHistory) {
      await historyStore.add(item);
      final total = await historyStore.count();
      _loadedPersisted = math.min(_loadedPersisted + 1, total);
      hasMoreHistory = history.length < total;
    }
    activeOriginal = item.original;
    activeTimestamp = null;
    // Preserve the latest correction in the output pane until next run.
    correctedText = item.corrected;
    activeFeedback = FeedbackChoice.none;
    notifyListeners();
  }

  /// Toggle feedback between the selected choice and none.
  FeedbackChoice _toggleFeedback(FeedbackChoice current, FeedbackChoice next) {
    if (current == next) {
      return FeedbackChoice.none;
    }
    return next;
  }

  @override
  void dispose() {
    final subscription = _subscription;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }
}

/// Load configuration and stores, then construct the app state.
Future<AppState> bootstrapAppState() async {
  final config = await AppConfigLoader.load();
  final settingsStore = SettingsStore();
  final historyStore = HistoryStore();
  const settings = Settings.defaults();
  final localizer = Localizer();

  return AppState(
    config: config,
    settingsStore: settingsStore,
    historyStore: historyStore,
    settings: settings,
    history: [],
    hasMoreHistory: true,
    loadedHistoryCount: 0,
    localizer: localizer,
  );
}
