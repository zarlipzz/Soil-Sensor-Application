import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/soil_measurement.dart';

/// Sends measurements to Home Assistant through its REST events API.
///
/// Values can be overridden with `--dart-define` when building.
class HomeAssistantService {
  static const _baseUrl = String.fromEnvironment(
    'HOME_ASSISTANT_URL',
    defaultValue: 'http://labubu.local',
  );
  static const _token = String.fromEnvironment(
    'HOME_ASSISTANT_TOKEN',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJhMjAzMzU2NWNjMmY0MTM2OTA2ZjM0NDE3NzU3NzI4NSIsImlhdCI6MTc5NDQ3NzQzNywiZXhwIjoyMTA5ODM3NDM3fQ.gkeo8c8Jf5NkmG2Hsg7fHIfGsEaN6nUka_tnaaiwuwQ',
  );
  static const _eventType = String.fromEnvironment(
    'HOME_ASSISTANT_EVENT_TYPE',
    defaultValue: 'soil_measurement',
  );

  final http.Client _client;

  HomeAssistantService({http.Client? client})
    : _client = client ?? http.Client();

  bool get isConfigured => _baseUrl.isNotEmpty && _token.isNotEmpty;

  Future<bool> uploadMeasurement(SoilMeasurement measurement) async {
    if (!isConfigured) {
      debugPrint(
        '[HomeAssistantService] URL or token missing; upload skipped.',
      );
      return false;
    }

    final base = _baseUrl.endsWith('/')
        ? _baseUrl.substring(0, _baseUrl.length - 1)
        : _baseUrl;
    final endpoint = Uri.parse('$base/api/events/$_eventType');

    try {
      final response = await _client
          .post(
            endpoint,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_token',
            },
            body: jsonEncode(measurement.toHomeAssistantEventData()),
          )
          .timeout(const Duration(seconds: 15));
      final uploaded = response.statusCode >= 200 && response.statusCode < 300;
      if (!uploaded) {
        debugPrint('[HomeAssistantService] HTTP ${response.statusCode}.');
      }
      return uploaded;
    } catch (e) {
      debugPrint('[HomeAssistantService] Upload failed: $e');
      return false;
    }
  }
}
