import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soil_app/services/measurement_name_history_service.dart';
import 'package:soil_app/utils/measurement_name.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('imports old names once and preserves deletions across loads', () async {
    final history = MeasurementNameHistoryService();
    const oldNames = [' A ', 'B', 'A', '', dataHubSettingsCommand];

    expect(await history.load(oldNames), ['A', 'B']);
    expect(await history.remove('A'), ['B']);
    expect(await MeasurementNameHistoryService().load(oldNames), ['B']);
    expect(await history.remove('B'), isEmpty);
    expect(await MeasurementNameHistoryService().load(oldNames), isEmpty);
  });

  test('moves reused names to the top and excludes the settings command', () async {
    final history = MeasurementNameHistoryService();
    await history.load(['A', 'B']);

    expect(await history.remember(' B '), ['B', 'A']);
    expect(await history.remember(dataHubSettingsCommand), ['B', 'A']);
    expect(await history.remember('C'), ['C', 'B', 'A']);
  });
}
