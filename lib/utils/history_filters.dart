import '../models/soil_measurement.dart';

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
