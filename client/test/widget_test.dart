// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:yaz_tatar/app_state.dart';
import 'package:yaz_tatar/history_store.dart';
import 'package:yaz_tatar/i18n.dart';
import 'package:yaz_tatar/main.dart';
import 'package:yaz_tatar/models.dart';
import 'package:yaz_tatar/settings_store.dart';

void main() {
  testWidgets('App renders workspace frame', (tester) async {
    final localizer = Localizer();
    final appState = AppState(
      config: const AppConfig(
        baseUrl: 'http://localhost:3000',
        appName: 'Test App',
        reportEmail: 'test@example.com',
        reportTelegramUrl: 'https://t.me/example',
        appIdentifiers: {},
        buildSha: '',
      ),
      settingsStore: SettingsStore(),
      historyStore: HistoryStore(),
      settings: const Settings.defaults(),
      history: const [],
      localizer: localizer,
      autoHydrate: false,
    );

    await tester.pumpWidget(MyApp(appState: appState));
    expect(find.text('YAZAM.TATAR'), findsOneWidget);
    expect(find.text('PANEL.ORIGINAL'), findsOneWidget);
  });
}
