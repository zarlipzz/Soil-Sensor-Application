// Model for grouping measurements within a radius.
import 'package:latlong2/latlong.dart';
import '../models/soil_measurement.dart';

class LocationGroup {
  final LatLng center;
  final List<SoilMeasurement> measurements;

  LocationGroup({required this.center, required this.measurements});

  // JSON serialization helpers
  Map<String, dynamic> toJson() => {
        'center': {'lat': center.latitude, 'lng': center.longitude},
        'measurements': measurements.map((m) => m.toJson()).toList(),
      };

  factory LocationGroup.fromJson(Map<String, dynamic> json) {
    final centerJson = json['center'] as Map<String, dynamic>;
    final center = LatLng(centerJson['lat'] as double, centerJson['lng'] as double);
    final measurementList = (json['measurements'] as List)
        .map((e) => SoilMeasurement.fromJson(e as Map<String, dynamic>))
        .toList();
    return LocationGroup(center: center, measurements: measurementList);
  }
}
