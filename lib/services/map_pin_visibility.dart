import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MapPinVisibility extends ValueNotifier<Set<String>> {
  MapPinVisibility._() : super(const {});

  static final instance = MapPinVisibility._();
  static const _key = 'soil_hidden_map_measurements';
  Future<bool>? _write;

  Future<void> load() async {
    try {
      if (_write case final pending?) await pending;
      final prefs = await SharedPreferences.getInstance();
      value = Set.unmodifiable(prefs.getStringList(_key) ?? const []);
    } catch (_) {
      debugPrint('[MapPinVisibility] Could not load hidden map pins.');
    }
  }

  Future<bool> hide(Iterable<String> measurementIds) async {
    while (_write != null) {
      await _write;
    }
    final write = _save({...value, ...measurementIds});
    _write = write;
    try {
      return await write;
    } finally {
      _write = null;
    }
  }

  Future<bool> _save(Set<String> ids) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setStringList(_key, ids.toList())) return false;
      value = Set.unmodifiable(ids);
      return true;
    } catch (_) {
      return false;
    }
  }
}
