import 'dart:typed_data';

import '../utils/app_constants.dart';

/// Data Model representing 8-in-1 Soil Measurement parameters and GPS coordinates.
class SoilMeasurement {
  final String id;
  final double temperature;
  final double moisture;
  final int ec;
  final int salinity;
  final int nitrogen;
  final int phosphorus;
  final int potassium;
  final double ph;
  final DateTime timestamp;
  bool isSyncedToCloud;

  // GPS Coordinates and accuracy fields
  final double? latitude;
  final double? longitude;
  final double? gpsAccuracy;
  final DateTime? locationTimestamp;

  SoilMeasurement({
    required this.id,
    required this.temperature,
    required this.moisture,
    required this.ec,
    required this.salinity,
    required this.nitrogen,
    required this.phosphorus,
    required this.potassium,
    required this.ph,
    required this.timestamp,
    this.isSyncedToCloud = false,
    this.latitude,
    this.longitude,
    this.gpsAccuracy,
    this.locationTimestamp,
  });

  /// Decodes raw Modbus 21-byte response payload into [SoilMeasurement]
  factory SoilMeasurement.fromRawBytes(
    Uint8List bytes, {
    double? latitude,
    double? longitude,
    double? gpsAccuracy,
    DateTime? locationTimestamp,
  }) {
    final byteData = ByteData.sublistView(bytes);
    final rawTemp = byteData.getInt16(3, Endian.big);
    final rawMoist = byteData.getUint16(5, Endian.big);
    final rawEc = byteData.getUint16(7, Endian.big);
    final rawSalinity = byteData.getUint16(9, Endian.big);
    final rawN = byteData.getUint16(11, Endian.big);
    final rawP = byteData.getUint16(13, Endian.big);
    final rawK = byteData.getUint16(15, Endian.big);
    final rawPh = byteData.getUint16(17, Endian.big);

    final now = DateTime.now();
    return SoilMeasurement(
      id: 'LOG-${now.millisecondsSinceEpoch}',
      temperature: rawTemp / 10.0,
      moisture: rawMoist / 10.0,
      ec: rawEc,
      salinity: rawSalinity,
      nitrogen: rawN,
      phosphorus: rawP,
      potassium: rawK,
      ph: rawPh / 100.0,
      timestamp: now,
      latitude: latitude,
      longitude: longitude,
      gpsAccuracy: gpsAccuracy,
      locationTimestamp: locationTimestamp,
    );
  }

  /// Initial placeholder data
  factory SoilMeasurement.initial() {
    return SoilMeasurement(
      id: 'INIT',
      temperature: 23.6,
      moisture: 0.0,
      ec: 0,
      salinity: 0,
      nitrogen: 0,
      phosphorus: 0,
      potassium: 0,
      ph: 7.00,
      timestamp: DateTime.now(),
    );
  }

  /// Serializes to JSON Map for SharedPreferences storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'temperature': temperature,
      'moisture': moisture,
      'ec': ec,
      'salinity': salinity,
      'nitrogen': nitrogen,
      'phosphorus': phosphorus,
      'potassium': potassium,
      'ph': ph,
      'timestamp': timestamp.toIso8601String(),
      'isSyncedToCloud': isSyncedToCloud,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (gpsAccuracy != null) 'gpsAccuracy': gpsAccuracy,
      if (locationTimestamp != null)
        'locationTimestamp': locationTimestamp!.toIso8601String(),
    };
  }

  /// Deserializes from JSON Map with backward compatibility
  factory SoilMeasurement.fromJson(Map<String, dynamic> json) {
    return SoilMeasurement(
      id:
          json['id'] as String? ??
          'LOG-${DateTime.now().millisecondsSinceEpoch}',
      temperature: (json['temperature'] as num).toDouble(),
      moisture: (json['moisture'] as num).toDouble(),
      ec: (json['ec'] as num).toInt(),
      salinity: (json['salinity'] as num).toInt(),
      nitrogen: (json['nitrogen'] as num).toInt(),
      phosphorus: (json['phosphorus'] as num).toInt(),
      potassium: (json['potassium'] as num).toInt(),
      ph: (json['ph'] as num).toDouble(),
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      isSyncedToCloud: json['isSyncedToCloud'] as bool? ?? false,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      gpsAccuracy: (json['gpsAccuracy'] as num?)?.toDouble(),
      locationTimestamp: json['locationTimestamp'] != null
          ? DateTime.tryParse(json['locationTimestamp'] as String)
          : null,
    );
  }

  /// Creates a copy with modified values
  SoilMeasurement copyWith({
    String? id,
    double? temperature,
    double? moisture,
    int? ec,
    int? salinity,
    int? nitrogen,
    int? phosphorus,
    int? potassium,
    double? ph,
    DateTime? timestamp,
    bool? isSyncedToCloud,
    double? latitude,
    double? longitude,
    double? gpsAccuracy,
    DateTime? locationTimestamp,
  }) {
    return SoilMeasurement(
      id: id ?? this.id,
      temperature: temperature ?? this.temperature,
      moisture: moisture ?? this.moisture,
      ec: ec ?? this.ec,
      salinity: salinity ?? this.salinity,
      nitrogen: nitrogen ?? this.nitrogen,
      phosphorus: phosphorus ?? this.phosphorus,
      potassium: potassium ?? this.potassium,
      ph: ph ?? this.ph,
      timestamp: timestamp ?? this.timestamp,
      isSyncedToCloud: isSyncedToCloud ?? this.isSyncedToCloud,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      gpsAccuracy: gpsAccuracy ?? this.gpsAccuracy,
      locationTimestamp: locationTimestamp ?? this.locationTimestamp,
    );
  }
}
