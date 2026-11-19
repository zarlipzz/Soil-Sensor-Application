import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/soil_measurement.dart';

class DataHubSettings {
  const DataHubSettings({
    required this.url,
    required this.apiKey,
    this.autoUpload = false,
  });

  static const defaults = DataHubSettings(
    url: String.fromEnvironment(
      'DATA_HUB_URL',
      defaultValue: 'http://192.168.6.223:8099/api/ingest',
    ),
    apiKey: String.fromEnvironment('DATA_HUB_API_KEY'),
  );

  final String url;
  final String apiKey;
  final bool autoUpload;

  static Uri? parseEndpoint(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      return null;
    }
    return uri;
  }
}

enum DataHubUploadResult {
  uploaded,
  notConfigured,
  rejected,
  failed,
  statusNotSaved,
}

class HomeAssistantService {
  HomeAssistantService({http.Client? client})
    : _client = client ?? http.Client();

  static const _settingsKey = 'soil_data_hub_settings';
  final http.Client _client;

  Future<DataHubSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return _readSettings(prefs);
  }

  DataHubSettings _readSettings(SharedPreferences prefs) {
    final stored = prefs.getStringList(_settingsKey);
    if (stored == null || stored.length < 2) return DataHubSettings.defaults;
    return DataHubSettings(
      url: stored[0],
      apiKey: stored[1],
      autoUpload: stored.length == 3 && stored[2] == 'true',
    );
  }

  Future<bool> saveCredentials(DataHubSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.setStringList(_settingsKey, [
      settings.url,
      settings.apiKey,
      _readSettings(prefs).autoUpload.toString(),
    ]);
  }

  Future<bool> saveAutoUpload(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    final settings = _readSettings(prefs);
    return prefs.setStringList(_settingsKey, [
      settings.url,
      settings.apiKey,
      enabled.toString(),
    ]);
  }

  Future<DataHubUploadResult> uploadMeasurement(
    SoilMeasurement measurement,
  ) async {
    try {
      final settings = await loadSettings();
      final endpoint = DataHubSettings.parseEndpoint(settings.url);
      final apiKey = settings.apiKey.trim();
      if (endpoint == null || apiKey.isEmpty) {
        return DataHubUploadResult.notConfigured;
      }

      final status = await _post(endpoint, apiKey, _ingestPayload(measurement));
      if (status >= 200 && status < 300) {
        return DataHubUploadResult.uploaded;
      }

      debugPrint('[Data Hub] Ingest returned HTTP $status.');
      if (status >= 400 && status < 500 && status != 408 && status != 429) {
        return DataHubUploadResult.rejected;
      }
    } catch (_) {
      debugPrint('[Data Hub] Ingest request failed.');
    }
    return DataHubUploadResult.failed;
  }

  Future<int> testConnection(DataHubSettings settings) async {
    final endpoint = DataHubSettings.parseEndpoint(settings.url);
    final apiKey = settings.apiKey.trim();
    if (endpoint == null || apiKey.isEmpty) {
      throw ArgumentError('A valid Data Hub URL and API key are required.');
    }
    return _post(endpoint, apiKey, {
      'device_id': 'meta-farm-api-test',
      'readings': [
        {
          'entity_id': 'sensor.meta_farm_api_test',
          'state': 1,
          'measurement_name': 'API connection test',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        },
      ],
    });
  }

  Future<int> _post(
    Uri endpoint,
    String apiKey,
    Map<String, Object> payload,
  ) async {
    final request = http.Request('POST', endpoint)
      ..followRedirects = false
      ..headers.addAll({
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json; charset=utf-8',
      })
      ..body = jsonEncode(payload);
    final response = await _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 15));
    return response.statusCode;
  }

  Map<String, Object> _ingestPayload(SoilMeasurement measurement) {
    final timestamp = measurement.timestamp.toUtc().toIso8601String();
    final attributes = <String, Object>{
      'local_log_id': measurement.id,
      if (measurement.latitude != null && measurement.longitude != null) ...{
        'latitude': measurement.latitude!,
        'longitude': measurement.longitude!,
        if (measurement.gpsAccuracy != null)
          'gps_accuracy_m': measurement.gpsAccuracy!,
        if (measurement.locationTimestamp != null)
          'gps_recorded_at': measurement.locationTimestamp!
              .toUtc()
              .toIso8601String(),
      },
    };

    Map<String, Object> reading(String metric, double state, [String? unit]) =>
        {
          'entity_id': 'sensor.soil_ch340_$metric',
          'state': double.parse(state.toStringAsFixed(2)),
          'unit': ?unit,
          'measurement_name': measurement.measurementName,
          'timestamp': timestamp,
          'attributes': attributes,
        };

    return {
      'device_id': measurement.deviceId,
      'readings': [
        reading('temperature', measurement.temperature, '°C'),
        reading('moisture', measurement.moisture, '%'),
        reading('ec', measurement.ec, 'µS/cm'),
        reading('salinity', measurement.salinity, 'mg/L'),
        reading('nitrogen', measurement.nitrogen, 'mg/kg'),
        reading('phosphorus', measurement.phosphorus, 'mg/kg'),
        reading('potassium', measurement.potassium, 'mg/kg'),
        reading('ph', measurement.ph),
      ],
    };
  }

  void dispose() => _client.close();
}
