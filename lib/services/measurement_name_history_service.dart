import 'package:shared_preferences/shared_preferences.dart';

import '../utils/measurement_name.dart';

/// Stores recently used measurement names on this device.
class MeasurementNameHistoryService {
  static const _key = 'soil_measurement_name_history';
  static const _maxNames = 30;

  Future<List<String>> load(Iterable<String> existingNames) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_key);
    if (stored != null) return _clean(stored);
    final names = _clean(existingNames);
    await _save(prefs, names);
    return names;
  }

  Future<List<String>> remember(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final updated = _clean([name, ...prefs.getStringList(_key) ?? const []]);
    await _save(prefs, updated);
    return updated;
  }

  Future<List<String>> remove(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final names = _clean(prefs.getStringList(_key) ?? const [])
      ..removeWhere((value) => value == name);
    await _save(prefs, names);
    return names;
  }

  Future<void> _save(SharedPreferences prefs, List<String> names) async {
    if (!await prefs.setStringList(_key, names)) {
      throw StateError('Unable to save measurement name history.');
    }
  }

  List<String> _clean(Iterable<String> values) {
    final seen = <String>{};
    return values
        .map((value) => value.trim())
        .where(
          (value) =>
              value.isNotEmpty &&
              value != dataHubSettingsCommand &&
              seen.add(value),
        )
        .take(_maxNames)
        .toList();
  }
}
