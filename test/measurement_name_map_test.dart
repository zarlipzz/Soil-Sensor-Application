import 'package:flutter_test/flutter_test.dart';
import 'package:soil_app/models/soil_measurement.dart';
import 'package:soil_app/utils/measurement_map_utils.dart';
import 'package:soil_app/utils/measurement_name.dart';

SoilMeasurement measurement({
  required String id,
  required String name,
  double? latitude = 13.7563,
  double? longitude = 100.5018,
  DateTime? timestamp,
}) {
  return SoilMeasurement(
    id: id,
    measurementName: name,
    temperature: 25,
    moisture: 30,
    ec: 100,
    salinity: 200,
    nitrogen: 10,
    phosphorus: 20,
    potassium: 30,
    ph: 6.5,
    timestamp: timestamp ?? DateTime.utc(2026),
    latitude: latitude,
    longitude: longitude,
  );
}

void main() {
  group('measurement name', () {
    test('rejects empty and whitespace-only names', () {
      expect(normalizedMeasurementName(''), isNull);
      expect(normalizedMeasurementName('  \t  '), isNull);
    });

    test('trims and preserves Thai and English names', () {
      expect(normalizedMeasurementName('  แปลงผัก A  '), 'แปลงผัก A');
      expect(normalizedMeasurementName('  Field North  '), 'Field North');
    });

    test('name persists in measurement JSON', () {
      final original = measurement(id: 'M-name', name: 'แปลงทดลอง A');
      final restored = SoilMeasurement.fromJson(original.toJson());
      expect(restored.measurementName, 'แปลงทดลอง A');
    });
  });

  group('measurement markers', () {
    test('same normalized name becomes one marker group without changing records', () {
      final older = measurement(
        id: 'M-old',
        name: '  Field A ',
        latitude: 13.0,
        longitude: 100.0,
        timestamp: DateTime.utc(2026, 1, 1),
      );
      final newer = measurement(
        id: 'M-new',
        name: 'Field A',
        latitude: 14.0,
        longitude: 101.0,
        timestamp: DateTime.utc(2026, 1, 2),
      );
      final noGps = measurement(
        id: 'M-no-gps',
        name: 'Field A',
        latitude: null,
        longitude: null,
        timestamp: DateTime.utc(2026, 1, 3),
      );
      final groups = measurementMarkerGroups([older, newer, noGps]);
      final points = measurementGroupMarkerPoints(groups);

      expect(groups, hasLength(1));
      expect(groups.single.measurements.map((item) => item.id), ['M-no-gps', 'M-new', 'M-old']);
      expect(points[groups.single.key]!.latitude, 13.0);
      expect(points[groups.single.key]!.longitude, 100.0);
      expect(older.latitude, 13.0);
      expect(newer.latitude, 14.0);
    });

    test('different names stay separate even at nearby locations', () {
      final groups = measurementMarkerGroups([
        measurement(id: 'M-1', name: 'A'),
        measurement(id: 'M-2', name: 'B', latitude: 13.75631, longitude: 100.50181),
      ]);
      expect(groups.map((group) => group.name), containsAll(['A', 'B']));
      expect(measurementGroupMarkerPoints(groups), hasLength(2));
    });

    test('one GPS-enabled measurement produces one marker point', () {
      final points = measurementMarkerPoints([
        measurement(id: 'M-1', name: 'Field A'),
      ]);
      expect(points, hasLength(1));
      expect(points['M-1'], isNotNull);
    });

    test('nearby measurements remain separate', () {
      final points = measurementMarkerPoints([
        measurement(id: 'M-1', name: 'A', latitude: 13.7563, longitude: 100.5018),
        measurement(id: 'M-2', name: 'B', latitude: 13.75631, longitude: 100.50181),
      ]);
      expect(points.keys, containsAll(['M-1', 'M-2']));
      expect(points, hasLength(2));
    });

    test('exactly overlapping measurements receive separate selectable points', () {
      final points = measurementMarkerPoints([
        measurement(id: 'M-1', name: 'A'),
        measurement(id: 'M-2', name: 'B'),
      ]);
      expect(points, hasLength(2));
      expect(points['M-1'], isNot(points['M-2']));
    });

    test('measurements without GPS create no marker point', () {
      final items = [
        measurement(id: 'M-gps', name: 'With GPS'),
        measurement(id: 'M-none', name: 'No GPS', latitude: null, longitude: null),
      ];
      expect(gpsEnabledMeasurements(items).map((item) => item.id), ['M-gps']);
      expect(measurementMarkerPoints(items).containsKey('M-none'), isFalse);
    });
  });
}
