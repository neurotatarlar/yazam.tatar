import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaz_tatar/models.dart';

void main() {
  test('AppConfig.fromJson applies defaults', () {
    final config = AppConfig.fromJson(const {});

    expect(config.baseUrl, isEmpty);
    expect(config.appName, 'Yaz.Tatar!');
    expect(config.reportEmail, isEmpty);
    expect(config.reportTelegramUrl, isEmpty);
    expect(config.appIdentifiers, isEmpty);
  });

  test('AppConfig.fromJson parses identifiers', () {
    final config = AppConfig.fromJson({
      'baseUrl': '/app/api',
      'appName': 'Test',
      'reportEmail': 'test@example.com',
      'reportTelegramUrl': 'https://t.me/test',
      'appIdentifiers': {'android': 'com.example.app', 'web': 123},
    });

    expect(config.baseUrl, '/app/api');
    expect(config.appName, 'Test');
    expect(config.reportEmail, 'test@example.com');
    expect(config.reportTelegramUrl, 'https://t.me/test');
    expect(config.appIdentifiers['android'], 'com.example.app');
    expect(config.appIdentifiers['web'], '123');
  });

  test('Settings.copyWith keeps unspecified values', () {
    const settings = Settings.defaults();
    final updated = settings.copyWith(
      fontScale: 1.2,
      layoutMode: LayoutMode.vertical,
    );

    expect(updated.fontScale, 1.2);
    expect(updated.layoutMode, LayoutMode.vertical);
    expect(updated.themeMode, ThemeMode.system);
    expect(updated.autoScroll, isTrue);
    expect(updated.saveHistory, isTrue);
    expect(updated.language, 'tt');
  });

  test('HistoryItem roundtrip preserves fields', () {
    final timestamp = DateTime.parse('2024-01-02T03:04:05Z');
    final item = HistoryItem(
      id: '1',
      original: 'orig',
      corrected: 'corr',
      timestamp: timestamp,
      latencyMs: 123,
      requestId: 'rid',
    );

    final restored = HistoryItem.fromJson(item.toJson());

    expect(restored.id, '1');
    expect(restored.original, 'orig');
    expect(restored.corrected, 'corr');
    expect(restored.timestamp.toUtc(), timestamp.toUtc());
    expect(restored.latencyMs, 123);
    expect(restored.requestId, 'rid');
  });
}
