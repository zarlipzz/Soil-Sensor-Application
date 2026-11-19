const dataHubSettingsCommand = 'config555';

/// Returns a display-safe measurement name, or null when the input is blank.
String? normalizedMeasurementName(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
