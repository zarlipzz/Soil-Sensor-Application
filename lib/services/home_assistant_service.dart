import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/soil_measurement.dart';

/// Stores each latest measurement in Home Assistant sensor entities.
class HomeAssistantService {
  static const _baseUrl = String.fromEnvironment(
    'HOME_ASSISTANT_URL',
    defaultValue: 'http://labubu.local',
  );
  static const _token = String.fromEnvironment(
    'HOME_ASSISTANT_TOKEN',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJhMjAzMzU2NWNjMmY0MTM2OTA2ZjM0NDE3NzU3NzI4NSIsImlhdCI6MTc5NDQ3NzQzNywiZXhwIjoyMTA5ODM3NDM3fQ.gkeo8c8Jf5NkmG2Hsg7fHIfGsEaN6nUka_tnaaiwuwQ',
  );

  final http.Client _client;

  HomeAssistantService({http.Client? client})
      : _client = client ?? http.Client();

  Future<bool> uploadMeasurement(SoilMeasurement measurement) async {
    final base = _baseUrl.endsWith('/')
        ? _baseUrl.substring(0, _baseUrl.length - 1)
        : _baseUrl;
    final commonAttributes = <String, dynamic>{
      'device_id': 'CH340-SOIL-01',
      'recorded_at': measurement.timestamp.toIso8601String(),
      'local_log_id': measurement.id,
      if (measurement.latitude != null) 'latitude': measurement.latitude,
      if (measurement.longitude != null) 'longitude': measurement.longitude,
      if (measurement.gpsAccuracy != null)
        'gps_accuracy_m': measurement.gpsAccuracy,
      if (measurement.locationTimestamp != null)
        'gps_recorded_at': measurement.locationTimestamp!.toIso8601String(),
    };

    final states = <_SensorState>[
      _SensorState('temperature', measurement.temperature.toStringAsFixed(2),
          'Soil temperature', '°C', 'temperature'),
      _SensorState('moisture', measurement.moisture.toStringAsFixed(1),
          'Soil moisture', '%', 'humidity'),
      _SensorState('ec', '${measurement.ec}', 'Soil EC', 'µS/cm', null),
      _SensorState('salinity', '${measurement.salinity}', 'Soil salinity',
          'mg/L', null),
      _SensorState('nitrogen', '${measurement.nitrogen}', 'Soil nitrogen',
          'mg/kg', null),
      _SensorState('phosphorus', '${measurement.phosphorus}',
          'Soil phosphorus', 'mg/kg', null),
      _SensorState('potassium', '${measurement.potassium}', 'Soil potassium',
          'mg/kg', null),
      _SensorState('ph', measurement.ph.toStringAsFixed(2), 'Soil pH', null,
          null),
      if (measurement.latitude != null && measurement.longitude != null)
        _SensorState(
          'gps',
          '${measurement.latitude!.toStringAsFixed(6)}, ${measurement.longitude!.toStringAsFixed(6)}',
          'Soil sensor GPS',
          null,
          null,
        ),
    ];

    try {
      final results = await Future.wait(
        states.map((sensor) => _postState(base, sensor, commonAttributes)),
      );
      final uploaded = results.every((success) => success);
      if (uploaded) {
        debugPrint(
          '[HomeAssistantService] Updated ${states.length} sensor states.',
        );
      }
      return uploaded;
    } catch (e) {
      debugPrint('[HomeAssistantService] Upload failed: $e');
      return false;
    }
  }

  Future<bool> _postState(
    String base,
    _SensorState sensor,
    Map<String, dynamic> commonAttributes,
  ) async {
    final endpoint = Uri.parse('$base/api/states/sensor.soil_ch340_${sensor.id}');
    final attributes = <String, dynamic>{
      ...commonAttributes,
      'friendly_name': sensor.name,
      'state_class': 'measurement',
      if (sensor.unit != null) 'unit_of_measurement': sensor.unit,
      if (sensor.deviceClass != null) 'device_class': sensor.deviceClass,
    };
    final response = await _client
        .post(
          endpoint,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_token',
          },
          body: jsonEncode({'state': sensor.value, 'attributes': attributes}),
        )
        .timeout(const Duration(seconds: 15));
    final success = response.statusCode >= 200 && response.statusCode < 300;
    if (!success) {
      debugPrint(
        '[HomeAssistantService] ${sensor.id}: HTTP ${response.statusCode}.',
      );
    }
    return success;
  }
}

class _SensorState {
  const _SensorState(this.id, this.value, this.name, this.unit, this.deviceClass);

  final String id;
  final String value;
  final String name;
  final String? unit;
  final String? deviceClass;
}
