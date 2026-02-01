// Persistence layer for user settings.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Stores user settings in SharedPreferences.
class SettingsStore {
  static const _themeKey = 'theme_mode';
  static const _fontScaleKey = 'font_scale';
  static const _autoScrollKey = 'auto_scroll';
  static const _saveHistoryKey = 'save_history';
  static const _languageKey = 'language';
  static const _layoutKey = 'layout_mode';

  /// Load persisted settings, falling back to defaults.
  Future<Settings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final theme = prefs.getString(_themeKey) ?? 'system';
    final fontScale = prefs.getDouble(_fontScaleKey) ?? 1.0;
    final autoScroll = prefs.getBool(_autoScrollKey) ?? true;
    final saveHistory = prefs.getBool(_saveHistoryKey) ?? true;
    final language = prefs.getString(_languageKey) ?? 'en';
    final layout = prefs.getString(_layoutKey) ?? 'horizontal';

    return Settings(
      themeMode: _themeFromString(theme),
      fontScale: fontScale,
      autoScroll: autoScroll,
      saveHistory: saveHistory,
      language: language,
      layoutMode: layout == 'vertical'
          ? LayoutMode.vertical
          : LayoutMode.horizontal,
    );
  }

  /// Persist the supplied settings values.
  Future<void> save(Settings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, _themeToString(settings.themeMode));
    await prefs.setDouble(_fontScaleKey, settings.fontScale);
    await prefs.setBool(_autoScrollKey, settings.autoScroll);
    await prefs.setBool(_saveHistoryKey, settings.saveHistory);
    await prefs.setString(_languageKey, settings.language);
    await prefs.setString(
      _layoutKey,
      settings.layoutMode == LayoutMode.vertical ? 'vertical' : 'horizontal',
    );
  }

  /// Convert serialized theme strings into ThemeMode values.
  ThemeMode _themeFromString(String value) {
    if (value == 'light') {
      return ThemeMode.light;
    }
    if (value == 'dark') {
      return ThemeMode.dark;
    }
    return ThemeMode.system;
  }

  /// Convert ThemeMode values into serialized strings.
  String _themeToString(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
  }
}
