import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soil_app/models/soil_measurement.dart';
import 'package:soil_app/services/local_storage_service.dart';
import 'package:soil_app/utils/history_filters.dart';

SoilMeasurement item(String id, String name, DateTime timestamp) => SoilMeasurement(
      id: id,
      measurementName: name,
      temperature: 20,
      moisture: 30,
      ec: 100,
      salinity: 200,
      nitrogen: 1,
      phosphorus: 2,
      potassium: 3,
      ph: 6.5,
      timestamp: timestamp,
    );

void main() {
  test('search, combined dates, end day and newest first', () {
    final records = [
      item('old', 'Earth', DateTime(2026, 11, 15, 10)),
      item('late', 'EARTH North', DateTime(2026, 11, 16, 23, 59, 59)),
      item('other', 'Water', DateTime(2026, 11, 16, 22)),
    ];
    expect(filterHistory(records, query: ' earth ').map((r) => r.id), ['late', 'old']);
    expect(filterHistory(records, query: 'earth', startDate: DateTime(2026, 11, 16), endDate: DateTime(2026, 11, 16)).map((r) => r.id), ['late']);
    expect(filterHistory(records, query: 'missing'), isEmpty);
    expect(filterHistory(records).first.id, 'late');
  });

  test('old JSON without raw samples or metadata remains readable', () {
    final old = SoilMeasurement.fromJson({
      'id': 'old', 'temperature': 20, 'moisture': 30, 'ec': 1, 'salinity': 2,
      'nitrogen': 3, 'phosphorus': 4, 'potassium': 5, 'ph': 6,
      'timestamp': '2020-01-01T00:00:00Z',
    });
    expect(old.rawSamples, isEmpty);
    expect(old.deviceMetadata, isEmpty);
  });

  test('clearHistory removes history and preserves unrelated preferences', () async {
    SharedPreferences.setMockInitialValues({'history_key': ['x'], 'installation': 'uuid'});
    final storage = LocalStorageService(prefKey: 'history_key');
    expect(await storage.clearHistory(), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('history_key'), isNull);
    expect(prefs.getString('installation'), 'uuid');
  });
}
