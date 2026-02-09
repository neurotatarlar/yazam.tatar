// History persistence with local fallback and pruning rules.
//
// Keeps saved corrections within item-count and encoded-size limits,
// and serves paged reads from newest to oldest for infinite scrolling.
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Stores history in SharedPreferences with size limits.
class HistoryStore {
  static const int maxItems = 200;
  static const int maxBytes = 1000000;
  static const _historyKey = 'history_items';
  bool _initialized = false;
  bool _useMemoryFallback = false;
  final List<Map<String, dynamic>> _memory = [];

  /// Lazily initialize shared preferences or fallback storage.
  Future<void> _ensureInit() async {
    if (_initialized) return;
    try {
      await SharedPreferences.getInstance();
    } on Object catch (_) {
      _useMemoryFallback = true;
    }
    _initialized = true;
  }

  /// Load raw history entries from storage.
  Future<List<Map<String, dynamic>>> _loadValues({
    bool pruneIfNeeded = false,
  }) async {
    await _ensureInit();
    if (_useMemoryFallback) {
      final values = List<Map<String, dynamic>>.from(_memory);
      if (pruneIfNeeded) {
        final trimmed = _trimValues(values);
        if (!identical(trimmed, values)) {
          _memory
            ..clear()
            ..addAll(trimmed);
          return trimmed;
        }
      }
      return values;
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null || raw.isEmpty) {
      return [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return [];
      }
      final values = decoded
          .whereType<Map<dynamic, dynamic>>()
          .map(
            (entry) => Map<String, dynamic>.fromEntries(
              entry.entries.map(
                (item) => MapEntry(item.key.toString(), item.value),
              ),
            ),
          )
          .toList(growable: false);
      if (pruneIfNeeded) {
        final trimmed = _trimValues(values);
        if (!identical(trimmed, values)) {
          await _saveValues(trimmed);
          return trimmed;
        }
      }
      return values;
    } on Object catch (_) {
      return [];
    }
  }

  /// Persist raw history entries to storage.
  Future<void> _saveValues(List<Map<String, dynamic>> values) async {
    await _ensureInit();
    if (_useMemoryFallback) {
      _memory
        ..clear()
        ..addAll(values);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_historyKey, jsonEncode(values));
  }

  /// Trim history to stay within count and size caps.
  List<Map<String, dynamic>> _trimValues(List<Map<String, dynamic>> values) {
    var trimmed = values;
    var changed = false;
    if (trimmed.length > maxItems) {
      trimmed = trimmed.sublist(trimmed.length - maxItems);
      changed = true;
    }
    if (maxBytes > 0) {
      var size = _encodedSize(trimmed);
      while (size > maxBytes && trimmed.length > 1) {
        trimmed = trimmed.sublist(1);
        changed = true;
        size = _encodedSize(trimmed);
      }
    }
    return changed ? List<Map<String, dynamic>>.from(trimmed) : values;
  }

  /// Return the JSON-encoded byte size of the history list.
  int _encodedSize(List<Map<String, dynamic>> values) {
    return utf8.encode(jsonEncode(values)).length;
  }

  /// Load all available history items.
  Future<List<HistoryItem>> loadAll() async {
    await _ensureInit();
    final total = await count();
    return loadPage(offset: 0, limit: total);
  }

  /// Append a new history item, pruning as needed.
  Future<void> add(HistoryItem item) async {
    await _ensureInit();
    if (_useMemoryFallback) {
      final next = List<Map<String, dynamic>>.from(_memory)..add(item.toJson());
      final trimmed = _trimValues(next);
      _memory
        ..clear()
        ..addAll(trimmed);
      return;
    }
    final values = await _loadValues(pruneIfNeeded: true);
    final next = List<Map<String, dynamic>>.from(values)..add(item.toJson());
    final trimmed = _trimValues(next);
    await _saveValues(trimmed);
  }

  /// Return the number of persisted history items.
  Future<int> count() async {
    await _ensureInit();
    if (_useMemoryFallback) {
      return _memory.length;
    }
    final values = await _loadValues(pruneIfNeeded: true);
    return values.length;
  }

  /// Load a page of history items from newest to oldest.
  Future<List<HistoryItem>> loadPage({
    required int offset,
    required int limit,
  }) async {
    await _ensureInit();
    if (limit <= 0) {
      return [];
    }
    final values = await _loadValues(pruneIfNeeded: true);
    final total = values.length;
    if (total == 0 || offset >= total) {
      return [];
    }
    final start = (total - offset - limit).clamp(0, total);
    final end = (total - offset).clamp(0, total);
    final slice = values.sublist(start, end).reversed;
    return slice.map(HistoryItem.fromJson).toList();
  }

  /// Clear all persisted history items.
  Future<void> clear() async {
    await _ensureInit();
    if (_useMemoryFallback) {
      _memory.clear();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }
}
