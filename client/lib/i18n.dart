// Lightweight JSON localization loader and token replacer.
import 'dart:convert';

import 'package:flutter/services.dart';

/// Holds translated strings and performs token substitution.
class Localizer {
  Map<String, String> _strings = {};

  /// Exposes the raw translation map.
  Map<String, String> get strings => _strings;

  /// Translate a key, replacing `{token}` placeholders.
  String t(String key, {Map<String, String> vars = const {}}) {
    var value = _strings[key] ?? key;
    vars.forEach((token, replacement) {
      value = value.replaceAll('{$token}', replacement);
    });
    return value;
  }

  /// Load translations for the given language code.
  Future<void> load(String lang) async {
    final path = 'assets/i18n/$lang.json';
    final raw = await rootBundle.loadString(path);
    final data = jsonDecode(raw) as Map<String, dynamic>;
    _strings = data.map((key, value) => MapEntry(key, value.toString()));
  }
}
