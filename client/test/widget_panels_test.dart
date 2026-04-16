import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaz_tatar/app_state.dart';
import 'package:yaz_tatar/backend_client.dart';
import 'package:yaz_tatar/history_store.dart';
import 'package:yaz_tatar/i18n.dart';
import 'package:yaz_tatar/main.dart';
import 'package:yaz_tatar/models.dart';
import 'package:yaz_tatar/settings_store.dart';

class FakeBackendClient extends BackendClient {
  FakeBackendClient(this.stream) : super('http://localhost:3000');

  final Stream<SseEvent> stream;

  @override
  Stream<SseEvent> streamCorrect({
    required String text,
    required String lang,
    required String platform,
  }) {
    return stream;
  }
}

AppState _buildState({
  String baseUrl = 'http://localhost:3000',
  BackendClient? backend,
  Settings settings = const Settings.defaults(),
  List<HistoryItem> history = const [],
}) {
  return AppState(
    config: AppConfig(
      baseUrl: baseUrl,
      appName: 'Test App',
      reportEmail: '',
      reportTelegramUrl: '',
      appIdentifiers: const {},
      buildSha: '',
    ),
    settingsStore: SettingsStore(),
    historyStore: HistoryStore(),
    settings: settings,
    history: history,
    localizer: Localizer(),
    autoHydrate: false,
    backend: backend,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            return null;
          }
          return null;
        });
  });

  testWidgets('Feed renders history card', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final history = [
      HistoryItem(
        id: '1',
        original: 'orig',
        corrected: 'fixed',
        timestamp: DateTime.now(),
        latencyMs: 0,
        requestId: 'rid',
      ),
    ];
    final state = _buildState(history: history)..correctedText = 'fixed';

    await tester.pumpWidget(MyApp(appState: state));

    expect(find.text('orig'), findsOneWidget);
    expect(find.text('fixed'), findsWidgets);
  });

  testWidgets('Send button streams corrected text', (tester) async {
    final stream = Stream<SseEvent>.fromIterable([
      const SseEvent('meta', {'request_id': 'rid', 'model_backend': 'mock'}),
      const SseEvent('delta', {'text': 'he'}),
      const SseEvent('delta', {'text': 'llo'}),
      const SseEvent('done', {'latency_ms': 12}),
    ]);
    final backend = FakeBackendClient(stream);
    final settings = const Settings.defaults().copyWith(saveHistory: false);
    final state = _buildState(backend: backend, settings: settings);

    await tester.pumpWidget(MyApp(appState: state));
    await tester.enterText(find.byType(TextField), 'hello');
    await tester.tap(find.byIcon(Icons.auto_fix_high));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.text('hello'), findsWidgets);
  });

  testWidgets('Offline view shows error', (tester) async {
    final state = _buildState(baseUrl: '');

    await tester.pumpWidget(MyApp(appState: state));
    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.auto_fix_high));
    await tester.pump();

    expect(state.errorMessage?.isNotEmpty ?? false, isTrue);
  });

  testWidgets('Copy button shows feedback', (tester) async {
    final history = [
      HistoryItem(
        id: '1',
        original: 'orig',
        corrected: 'copied',
        timestamp: DateTime.now(),
        latencyMs: 0,
        requestId: 'rid',
      ),
    ];
    final state = _buildState(history: history)..correctedText = 'copied';

    await tester.pumpWidget(MyApp(appState: state));
    await tester.tap(find.byTooltip('actions.copy').first);
    await tester.pump();
    expect(find.text('actions.copied'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1000));
  });

  testWidgets('Stop button cancels stream and shows stopped label', (
    tester,
  ) async {
    final state = _buildState()
      ..isStreaming = true
      ..activeOriginal = 'hello';

    await tester.pumpWidget(MyApp(appState: state));

    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.stop_rounded));
    await tester.pump(const Duration(milliseconds: 50));

    expect(state.wasCanceled, isTrue);
  });

  testWidgets('Feedback toggle hides opposite icon', (tester) async {
    final history = [
      HistoryItem(
        id: '1',
        original: 'orig',
        corrected: 'fixed',
        timestamp: DateTime.now(),
        latencyMs: 0,
        requestId: 'rid',
      ),
    ];
    final state = _buildState(history: history)..correctedText = 'fixed';

    await tester.pumpWidget(MyApp(appState: state));
    expect(find.byIcon(Icons.thumb_up_alt_outlined), findsOneWidget);
    expect(find.byIcon(Icons.thumb_down_alt_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.thumb_up_alt_outlined));
    await tester.pump();

    expect(find.byIcon(Icons.thumb_up_alt), findsOneWidget);
    expect(find.byIcon(Icons.thumb_down_alt_outlined), findsNothing);

    await tester.tap(find.byIcon(Icons.thumb_up_alt));
    await tester.pump();

    expect(find.byIcon(Icons.thumb_up_alt_outlined), findsOneWidget);
    expect(find.byIcon(Icons.thumb_down_alt_outlined), findsOneWidget);
  });

  testWidgets('Report problem opens report sheet', (tester) async {
    final history = [
      HistoryItem(
        id: '1',
        original: 'orig',
        corrected: 'fixed',
        timestamp: DateTime.now(),
        latencyMs: 0,
        requestId: 'rid',
      ),
    ];
    final state = _buildState(history: history)..correctedText = 'fixed';

    await tester.pumpWidget(MyApp(appState: state));
    await tester.tap(find.text('actions.reportProblem'));
    await tester.pumpAndSettle();

    expect(find.text('report.title'), findsOneWidget);
  });
}
