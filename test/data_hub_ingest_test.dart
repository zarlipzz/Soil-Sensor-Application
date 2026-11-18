import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soil_app/models/soil_measurement.dart';
import 'package:soil_app/services/home_assistant_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('posts one Data Hub batch with eight named numeric readings', () async {
    SharedPreferences.setMockInitialValues({});
    http.Request? captured;
    final service = HomeAssistantService(
      client: MockClient((request) async {
        captured = request;
        return http.Response('{}', 202);
      }),
    );
    addTearDown(service.dispose);
    const endpoint = 'http://example.test:8099/api/ingest';
    await service.saveSettings(
      const DataHubSettings(url: endpoint, apiKey: 'test-key'),
    );
    final result = await service.uploadMeasurement(
      SoilMeasurement(
        id: 'measurement-1',
        deviceId: 'soil-01',
        measurementName: 'Plot A',
        temperature: 22.239,
        moisture: 30.504,
        ec: 100,
        salinity: 200,
        nitrogen: 12,
        phosphorus: 13,
        potassium: 14,
        ph: 7.1,
        timestamp: DateTime.parse('2026-11-17T14:30:00+07:00'),
        latitude: 18.74,
        longitude: 98.98,
      ),
    );

    expect(result, DataHubUploadResult.uploaded);
    final request = captured!;
    expect(request.method, 'POST');
    expect(request.url, Uri.parse(endpoint));
    expect(request.headers['authorization'], 'Bearer test-key');
    expect(request.headers['content-type'], startsWith('application/json'));
    final payload = jsonDecode(request.body) as Map<String, dynamic>;
    expect(payload.keys, unorderedEquals(['device_id', 'readings']));
    expect(payload['device_id'], 'soil-01');
    final readings = (payload['readings'] as List).cast<Map<String, dynamic>>();
    expect(readings, hasLength(8));
    expect(
      {for (final reading in readings) reading['entity_id']: reading['state']},
      {
        'sensor.soil_ch340_temperature': 22.24,
        'sensor.soil_ch340_moisture': 30.5,
        'sensor.soil_ch340_ec': 100,
        'sensor.soil_ch340_salinity': 200,
        'sensor.soil_ch340_nitrogen': 12,
        'sensor.soil_ch340_phosphorus': 13,
        'sensor.soil_ch340_potassium': 14,
        'sensor.soil_ch340_ph': 7.1,
      },
    );
    for (final reading in readings) {
      expect(reading['measurement_name'], 'Plot A');
      expect(reading['timestamp'], '2026-11-17T07:30:00.000Z');
      expect(reading['attributes'], {
        'local_log_id': 'measurement-1',
        'latitude': 18.74,
        'longitude': 98.98,
      });
    }
  });
}
