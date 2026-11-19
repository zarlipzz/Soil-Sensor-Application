import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../models/soil_measurement.dart';
import 'measurement_name.dart';

/// GPS-enabled records only. Each returned item represents one measurement ID.
List<SoilMeasurement> gpsEnabledMeasurements(
  Iterable<SoilMeasurement> measurements,
) {
  return measurements
      .where(
        (measurement) =>
            measurement.latitude != null &&
            measurement.longitude != null &&
            measurement.latitude!.isFinite &&
            measurement.longitude!.isFinite,
      )
      .toList(growable: false);
}

/// A presentation-only marker group. Its records remain separate locally.
class MeasurementMapGroup {
  const MeasurementMapGroup({
    required this.key,
    required this.name,
    required this.measurements,
  });

  final String key;
  final String name;
  final List<SoilMeasurement> measurements;

  /// Newest record in the name group, regardless of GPS availability.
  SoilMeasurement get newest => measurements.first;

  /// Earliest record with GPS; this keeps the marker anchored to its first
  /// known location even when later measurements move or have no GPS.
  SoilMeasurement get earliestGps => measurements.lastWhere(
        (measurement) =>
            measurement.latitude != null &&
            measurement.longitude != null &&
            measurement.latitude!.isFinite &&
            measurement.longitude!.isFinite,
      );
}

/// Groups records by trimmed measurement name, newest first.
/// Groups with no GPS records have no marker. A no-GPS record remains available
/// in an existing group's popup, but never determines its marker location.
/// No stored measurement is changed or merged.
List<MeasurementMapGroup> measurementMarkerGroups(
  Iterable<SoilMeasurement> measurements, {
  Set<String> hiddenMeasurementIds = const {},
}) {
  final recordsByName = <String, List<SoilMeasurement>>{};
  for (final measurement in measurements) {
    if (hiddenMeasurementIds.contains(measurement.id)) continue;
    final name = normalizedMeasurementName(measurement.measurementName) ??
        'Unnamed measurement';
    recordsByName.putIfAbsent(name, () => []).add(measurement);
  }
  final groups = recordsByName.entries.map((entry) {
    final records = List<SoilMeasurement>.from(entry.value)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return MeasurementMapGroup(
      key: entry.key,
      name: entry.key,
      measurements: List.unmodifiable(records),
    );
  }).where((group) => group.measurements.any((measurement) =>
      measurement.latitude != null &&
      measurement.longitude != null &&
      measurement.latitude!.isFinite &&
      measurement.longitude!.isFinite)).toList()
    ..sort((a, b) => b.newest.timestamp.compareTo(a.newest.timestamp));
  return List.unmodifiable(groups);
}

/// Gives each name group a marker point using its earliest valid GPS value.
/// Different names at identical coordinates are fanned out so both stay tappable.
Map<String, LatLng> measurementGroupMarkerPoints(
  Iterable<MeasurementMapGroup> groups,
) {
  final overlapping = <String, List<MeasurementMapGroup>>{};
  for (final group in groups) {
    final record = group.earliestGps;
    final coordinateKey = '${record.latitude!.toStringAsFixed(8)},'
        '${record.longitude!.toStringAsFixed(8)}';
    overlapping.putIfAbsent(coordinateKey, () => []).add(group);
  }
  final points = <String, LatLng>{};
  for (final samePositionGroups in overlapping.values) {
    samePositionGroups.sort((a, b) => a.key.compareTo(b.key));
    for (var index = 0; index < samePositionGroups.length; index++) {
      final group = samePositionGroups[index];
      final record = group.earliestGps;
      if (samePositionGroups.length == 1) {
        points[group.key] = LatLng(record.latitude!, record.longitude!);
        continue;
      }
      final angle = (2 * math.pi * index) / samePositionGroups.length;
      const offsetDegrees = 0.00003;
      points[group.key] = LatLng(
        record.latitude! + math.sin(angle) * offsetDegrees,
        record.longitude! + math.cos(angle) * offsetDegrees,
      );
    }
  }
  return points;
}

/// Gives every GPS-enabled measurement its own marker location.
///
/// Nearby points are never clustered or merged. Only exact coordinate matches
/// are fanned out by a few metres, allowing each overlapping marker to be
/// selected. Ordering by measurement ID keeps the display offsets stable.
Map<String, LatLng> measurementMarkerPoints(
  Iterable<SoilMeasurement> measurements,
) {
  final groups = <String, List<SoilMeasurement>>{};
  for (final measurement in gpsEnabledMeasurements(measurements)) {
    final key = '${measurement.latitude!.toStringAsFixed(8)},'
        '${measurement.longitude!.toStringAsFixed(8)}';
    groups.putIfAbsent(key, () => []).add(measurement);
  }

  final points = <String, LatLng>{};
  for (final group in groups.values) {
    group.sort((a, b) => a.id.compareTo(b.id));
    if (group.length == 1) {
      points[group.single.id] = LatLng(group.single.latitude!, group.single.longitude!);
      continue;
    }
    for (var index = 0; index < group.length; index++) {
      final measurement = group[index];
      final angle = (2 * math.pi * index) / group.length;
      // About 3.3 metres at the equator; adequate to make hit targets separate.
      const offsetDegrees = 0.00003;
      points[measurement.id] = LatLng(
        measurement.latitude! + math.sin(angle) * offsetDegrees,
        measurement.longitude! + math.cos(angle) * offsetDegrees,
      );
    }
  }
  return points;
}
