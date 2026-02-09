// Loads app configuration from bundled JSON assets.
import 'dart:convert';

import 'package:flutter/services.dart';

import 'models.dart';

/// Utility for reading `assets/config.json` into AppConfig.
class AppConfigLoader {
  /// Load configuration, falling back to defaults on failure.
  static Future<AppConfig> load({AssetBundle? bundle}) async {
    final loader = bundle ?? rootBundle;
    try {
      final raw = await loader.loadString('assets/config.json');
      if (raw.trim().isEmpty) {
        return AppConfig.fromJson(const {});
      }
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return AppConfig.fromJson(data);
    } on Object catch (_) {
      return AppConfig.fromJson(const {});
    }
  }
}
