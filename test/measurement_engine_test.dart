import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soil_app/models/soil_measurement.dart';
import 'package:soil_app/services/device_identity_service.dart';
import 'package:soil_app/services/local_storage_service.dart';
import 'package:soil_app/services/measurement_engine.dart';

SoilSample sample(double value) => SoilSample(
  temperature: value,
  moisture: value + 1,
  ec: value + 2,
  salinity: value + 3,
  nitrogen: value + 4,
  phosphorus: value + 5,
  potassium: value + 6,
  ph: value + 0.5,
);

SoilMeasurement completedMeasurement(String id) {
  return SoilMeasurement.fromAveragedSamples(
    id: id,
    rawSamples: List.generate(10, (index) => sample(index.toDouble())),
    timestamp: DateTime.utc(2026, 1, 1),
    deviceId: 'installation-id',
    deviceMetadata: const {'platform': 'android'},
  );
}

void main() {
  group('MeasurementEngine', () {
    test(
      'completes after exactly 10 valid samples and averages all fields',
      () {
        final engine = MeasurementEngine();
        engine.start(onTimeout: () {});

        for (var index = 0; index < 9; index++) {
          expect(engine.addSample(sample(index.toDouble())), isNull);
        }
        final samples = engine.addSample(sample(9));

        expect(samples, hasLength(10));
        expect(engine.status, MeasurementEngineStatus.completed);
        final measurement = SoilMeasurement.fromAveragedSamples(
          id: 'M-1',
          rawSamples: samples!,
          timestamp: DateTime.utc(2026),
          deviceId: 'installation-id',
          deviceMetadata: const {},
        );
        expect(measurement.temperature, 4.5);
        expect(measurement.moisture, 5.5);
        expect(measurement.ec, 6.5);
        expect(measurement.ph, 5.0);
        engine.dispose();
      },
    );

    test('rejects incomplete samples without incrementing the count', () {
      final engine = MeasurementEngine();
      engine.start(onTimeout: () {});
      final incomplete = SoilSample(
        temperature: double.nan,
        moisture: 1,
        ec: 1,
        salinity: 1,
        nitrogen: 1,
        phosphorus: 1,
        potassium: 1,
        ph: 1,
      );
      expect(engine.addSample(incomplete), isNull);
      expect(engine.rawSamples, isEmpty);
      expect(engine.status, MeasurementEngineStatus.collecting);
      engine.dispose();
    });

    test(
      'duplicate START does not clear a measurement already in progress',
      () {
        final engine = MeasurementEngine();
        engine.start(onTimeout: () {});
        engine.addSample(sample(1));
        engine.start(onTimeout: () {});
        expect(engine.rawSamples, hasLength(1));
        expect(engine.status, MeasurementEngineStatus.collecting);
        engine.dispose();
      },
    );

    test('timeout stops an incomplete measurement safely', () async {
      var timedOut = false;
      final engine = MeasurementEngine(
        timeout: const Duration(milliseconds: 10),
      );
      engine.start(onTimeout: () => timedOut = true);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(timedOut, isTrue);
      expect(engine.status, MeasurementEngineStatus.timedOut);
      expect(engine.addSample(sample(1)), isNull);
      engine.dispose();
    });

    test('cancel stops an incomplete measurement safely', () {
      final engine = MeasurementEngine();
      engine.start(onTimeout: () {});
      engine.addSample(sample(1));
      engine.cancel();
      expect(engine.status, MeasurementEngineStatus.cancelled);
      expect(engine.addSample(sample(2)), isNull);
      engine.dispose();
    });
  });

  group('Measurement persistence', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('raw and average values round-trip through JSON', () {
      final original = completedMeasurement('M-JSON');
      final restored = SoilMeasurement.fromJson(original.toJson());
      expect(restored.id, original.id);
      expect(restored.rawSamples, hasLength(10));
      expect(restored.temperature, original.temperature);
      expect(restored.ph, original.ph);
      expect(restored.deviceId, 'installation-id');
    });

    test('old record JSON remains readable without fabricated raw samples', () {
      final restored = SoilMeasurement.fromJson({
        'id': 'OLD-1',
        'temperature': 25.1,
        'moisture': 33.2,
        'ec': 100,
        'salinity': 200,
        'nitrogen': 10,
        'phosphorus': 20,
        'potassium': 30,
        'ph': 6.8,
        'timestamp': '2026-01-01T00:00:00.000Z',
        'isSyncedToCloud': true,
      });
      expect(restored.id, 'OLD-1');
      expect(restored.rawSamples, isEmpty);
      expect(restored.measurementName, isEmpty);
      expect(restored.isSyncedToCloud, isTrue);
    });

    test('installation UUID persists across calls', () async {
      final prefs = await SharedPreferences.getInstance();
      final first = await DeviceIdentityService.getOrCreateInstallationId(
        prefs,
        createId: () => 'persisted-id',
      );
      final second = await DeviceIdentityService.getOrCreateInstallationId(
        prefs,
        createId: () => 'different-id',
      );
      expect(first, 'persisted-id');
      expect(second, 'persisted-id');
    });

    test(
      'saving a retry with the same measurement ID creates one record',
      () async {
        final storage = LocalStorageService();
        final measurement = completedMeasurement('M-ONE');
        final first = await storage.saveMeasurement(measurement, []);
        final second = await storage.saveMeasurement(measurement, first);
        expect(second, hasLength(1));
        expect(second.single.id, 'M-ONE');
      },
    );

    test('keeps offline records and persists a confirmed upload', () async {
      final storage = LocalStorageService(maxLogs: 1);
      final first = await storage.saveMeasurement(
        completedMeasurement('M-OFFLINE-1'),
        [],
      );
      await storage.saveMeasurement(completedMeasurement('M-OFFLINE-2'), first);

      final restored = await storage.loadMeasurements();
      expect(restored.map((record) => record.id), [
        'M-OFFLINE-2',
        'M-OFFLINE-1',
      ]);
      expect(restored.every((record) => !record.isSyncedToCloud), isTrue);

      await storage.updateSyncStatus('M-OFFLINE-1', true, restored);
      final afterUpload = await storage.loadMeasurements();
      expect(
        afterUpload.where((record) => !record.isSyncedToCloud).map((r) => r.id),
        ['M-OFFLINE-2'],
      );
    });
  });
}
