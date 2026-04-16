import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yaz_tatar/app_state.dart';
import 'package:yaz_tatar/backend_client.dart';
import 'package:yaz_tatar/history_store.dart';
import 'package:yaz_tatar/i18n.dart';
import 'package:yaz_tatar/models.dart';
import 'package:yaz_tatar/settings_store.dart';

class FakeBackendClient extends BackendClient {
  FakeBackendClient() : super('http://localhost:3000');

  final StreamController<SseEvent> controller = StreamController<SseEvent>();

  @override
  Stream<SseEvent> streamCorrect({
    required String text,
    required String lang,
    required String platform,
  }) {
    return controller.stream;
  }

  void emit(SseEvent event) {
    controller.add(event);
  }

  Future<void> finish() async {
    await controller.close();
  }
}

class FakeHistoryStore extends HistoryStore {
  FakeHistoryStore(this.items);

  final List<HistoryItem> items;
  final List<HistoryItem> added = [];
  bool cleared = false;
  int? lastOffset;
  int? lastLimit;

  @override
  Future<List<HistoryItem>> loadPage({
    required int offset,
    required int limit,
  }) async {
    lastOffset = offset;
    lastLimit = limit;
    if (limit <= 0) {
      return [];
    }
    final ordered = items.reversed.toList();
    if (offset >= ordered.length) {
      return [];
    }
    final end = (offset + limit).clamp(0, ordered.length);
    return ordered.sublist(offset, end);
  }

  @override
  Future<int> count() async {
    return items.length;
  }

  @override
  Future<void> add(HistoryItem item) async {
    added.add(item);
    items.add(item);
  }

  @override
  Future<void> clear() async {
    items.clear();
    cleared = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AppState buildState({
    BackendClient? backend,
    HistoryStore? historyStore,
    Settings settings = const Settings.defaults(),
    List<HistoryItem> history = const [],
    bool? hasMoreHistory,
    int? loadedHistoryCount,
  }) {
    return AppState(
      config: const AppConfig(
        baseUrl: 'http://localhost:3000',
        appName: 'Test App',
        reportEmail: '',
        reportTelegramUrl: '',
        appIdentifiers: {},
        buildSha: '',
      ),
      settingsStore: SettingsStore(),
      historyStore: historyStore ?? HistoryStore(),
      settings: settings,
      history: List<HistoryItem>.from(history),
      localizer: Localizer(),
      backend: backend,
      hasMoreHistory: hasMoreHistory,
      loadedHistoryCount: loadedHistoryCount,
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('toggleExpand cycles panel state', () {
    final state = buildState();

    expect(state.expandedPanel, ExpandedPanel.none);

    state.toggleExpand(ExpandedPanel.original);
    expect(state.expandedPanel, ExpandedPanel.original);

    state.toggleExpand(ExpandedPanel.original);
    expect(state.expandedPanel, ExpandedPanel.none);

    state.toggleExpand(ExpandedPanel.corrected);
    expect(state.expandedPanel, ExpandedPanel.corrected);
  });

  test('setSplitRatio updates ratio', () {
    final state = buildState()..setSplitRatio(0.7);
    expect(state.splitRatio, 0.7);
  });

  test('setLayout resets split ratio', () {
    final state = buildState()
      ..splitRatio = 0.7
      ..setLayout(LayoutMode.vertical);
    expect(state.settings.layoutMode, LayoutMode.vertical);
    expect(state.splitRatio, 0.5);
  });

  test('toggleActiveFeedback cycles selection', () {
    final state = buildState();

    expect(state.activeFeedback, FeedbackChoice.none);

    state.toggleActiveFeedback(FeedbackChoice.up);
    expect(state.activeFeedback, FeedbackChoice.up);

    state.toggleActiveFeedback(FeedbackChoice.up);
    expect(state.activeFeedback, FeedbackChoice.none);

    state.toggleActiveFeedback(FeedbackChoice.down);
    expect(state.activeFeedback, FeedbackChoice.down);
  });

  test('toggleHistoryFeedback stores per-item state', () {
    final state = buildState();

    expect(
      state.feedbackForItem(
        HistoryItem(
          id: '1',
          original: '',
          corrected: '',
          timestamp: DateTime.fromMillisecondsSinceEpoch(0),
          latencyMs: 0,
          requestId: '',
        ),
      ),
      FeedbackChoice.none,
    );

    state.toggleHistoryFeedback('1', FeedbackChoice.up);
    expect(
      state.feedbackForItem(
        HistoryItem(
          id: '1',
          original: '',
          corrected: '',
          timestamp: DateTime.fromMillisecondsSinceEpoch(0),
          latencyMs: 0,
          requestId: '',
        ),
      ),
      FeedbackChoice.up,
    );

    state.toggleHistoryFeedback('1', FeedbackChoice.up);
    expect(
      state.feedbackForItem(
        HistoryItem(
          id: '1',
          original: '',
          corrected: '',
          timestamp: DateTime.fromMillisecondsSinceEpoch(0),
          latencyMs: 0,
          requestId: '',
        ),
      ),
      FeedbackChoice.none,
    );
  });

  test('stopStreaming marks canceled', () async {
    final state = buildState();
    await (state..isStreaming = true).stopStreaming();

    expect(state.isStreaming, false);
    expect(state.wasCanceled, true);
  });

  test('submit updates history on done event', () async {
    final backend = FakeBackendClient();
    final historyStore = FakeHistoryStore([]);
    final state = buildState(backend: backend, historyStore: historyStore);

    await (state..updateOriginalText('hello')).submit();

    expect(state.isStreaming, true);
    expect(state.statusText, 'status.correcting');
    expect(state.activeOriginal, 'hello');
    expect(state.originalText, 'hello');

    backend
      ..emit(
        const SseEvent('meta', {
          'request_id': 'req-1',
          'model_backend': 'gemini',
        }),
      )
      ..emit(const SseEvent('delta', {'text': 'Hi '}))
      ..emit(const SseEvent('delta', {'text': 'there'}))
      ..emit(const SseEvent('done', {'latency_ms': 120}));
    await backend.finish();
    await Future<void>.delayed(Duration.zero);

    expect(state.isStreaming, false);
    expect(state.statusText, '');
    expect(state.history.length, 1);
    expect(state.history.first.original, 'hello');
    expect(state.history.first.corrected, 'Hi there');
    expect(state.history.first.requestId, 'req-1');
    expect(state.history.first.latencyMs, 120);
    expect(state.modelBackend, 'gemini');
    expect(historyStore.added.length, 1);
  });

  test('submit does not persist history when disabled', () async {
    final backend = FakeBackendClient();
    final historyStore = FakeHistoryStore([]);
    final settings = const Settings.defaults().copyWith(saveHistory: false);
    final state = buildState(
      backend: backend,
      historyStore: historyStore,
      settings: settings,
    );

    await (state..updateOriginalText('hello')).submit();

    backend
      ..emit(const SseEvent('meta', {'request_id': 'req-2'}))
      ..emit(const SseEvent('delta', {'text': 'Fixed'}))
      ..emit(const SseEvent('done', {'latency_ms': 0}));
    await backend.finish();
    await Future<void>.delayed(Duration.zero);

    expect(state.history.length, 1);
    expect(historyStore.added, isEmpty);
  });

  test('error event updates error state', () async {
    final backend = FakeBackendClient();
    final state = buildState(backend: backend);

    await (state..updateOriginalText('hello')).submit();

    backend.emit(const SseEvent('error', {'message': 'boom'}));
    await backend.finish();
    await Future<void>.delayed(Duration.zero);

    expect(state.isStreaming, false);
    expect(state.wasCanceled, false);
    expect(state.statusText, 'status.error');
    expect(state.errorMessage, 'boom');
    expect(state.history, isEmpty);
  });

  test('loadMoreHistory appends older items', () async {
    final items = List.generate(
      8,
      (index) => HistoryItem(
        id: '${index + 1}',
        original: 'o${index + 1}',
        corrected: 'c${index + 1}',
        timestamp: DateTime.fromMillisecondsSinceEpoch(index + 1),
        latencyMs: 0,
        requestId: '',
      ),
    );
    final historyStore = FakeHistoryStore(items);
    final initial = await historyStore.loadPage(
      offset: 0,
      limit: AppState.historyPageSize,
    );
    final state = buildState(
      historyStore: historyStore,
      history: initial,
      hasMoreHistory: true,
      loadedHistoryCount: initial.length,
    );

    final loaded = await state.loadMoreHistory();

    expect(loaded, true);
    expect(historyStore.lastOffset, initial.length);
    expect(historyStore.lastLimit, AppState.historyPageSize);
    expect(state.history.length, 8);
    expect(state.history.first.id, '8');
    expect(state.history.last.id, '1');
    expect(state.hasMoreHistory, false);
  });
}
