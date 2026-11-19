import '../models/soil_measurement.dart';

String measurementFilterName(SoilMeasurement record) {
  final name = record.measurementName.trim();
  return name.isEmpty ? 'Unnamed' : name;
}

String measurementFilterDate(DateTime timestamp) {
  final day = timestamp.day.toString().padLeft(2, '0');
  final month = timestamp.month.toString().padLeft(2, '0');
  return '$day/$month/${timestamp.year}';
}

bool matchesMeasurementNames(String name, Set<String> selectedNames) =>
    selectedNames.isEmpty || selectedNames.contains(name);

Set<String> availableMeasurementDates(
  Iterable<SoilMeasurement> records,
  Set<String> selectedNames,
) => {
  for (final record in records)
    if (matchesMeasurementNames(measurementFilterName(record), selectedNames))
      measurementFilterDate(record.timestamp),
};

List<SoilMeasurement> filterHistory(
  Iterable<SoilMeasurement> records, {
  String query = '',
  DateTime? startDate,
  DateTime? endDate,
}) {
  final needle = query.trim().toLowerCase();
  final endExclusive = endDate == null
      ? null
      : DateTime(endDate.year, endDate.month, endDate.day + 1);
  final result = records.where((record) {
    final name = record.measurementName.trim().toLowerCase();
    return (needle.isEmpty || name.contains(needle)) &&
        (startDate == null || !record.timestamp.isBefore(DateTime(startDate.year, startDate.month, startDate.day))) &&
        (endExclusive == null || record.timestamp.isBefore(endExclusive));
  }).toList()
    ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  return result;
}
