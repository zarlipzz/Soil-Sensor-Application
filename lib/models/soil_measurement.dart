import 'dart:typed_data';

import '../utils/app_constants.dart';

/// One complete, CRC-validated response from the 8-in-1 sensor.
class SoilSample {
  const SoilSample({
    required this.temperature,
    required this.moisture,
    required this.ec,
    required this.salinity,
    required this.nitrogen,
    required this.phosphorus,
    required this.potassium,
    required this.ph,
  });

  final double temperature;
  final double moisture;
  final double ec;
  final double salinity;
  final double nitrogen;
  final double phosphorus;
  final double potassium;
  final double ph;

  factory SoilSample.fromRawBytes(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    return SoilSample(
      temperature: data.getInt16(3, Endian.big) / 10.0,
      moisture: data.getUint16(5, Endian.big) / 10.0,
      ec: data.getUint16(7, Endian.big).toDouble(),
      salinity: data.getUint16(9, Endian.big).toDouble(),
      nitrogen: data.getUint16(11, Endian.big).toDouble(),
      phosphorus: data.getUint16(13, Endian.big).toDouble(),
      potassium: data.getUint16(15, Endian.big).toDouble(),
      ph: data.getUint16(17, Endian.big) / 100.0,
    );
  }

  bool get isComplete => [
        temperature, moisture, ec, salinity, nitrogen, phosphorus, potassium, ph,
      ].every((value) => value.isFinite);

  Map<String, dynamic> toJson() => {
        'temperature': temperature,
        'moisture': moisture,
        'ec': ec,
        'salinity': salinity,
        'nitrogen': nitrogen,
        'phosphorus': phosphorus,
        'potassium': potassium,
        'ph': ph,
      };

  factory SoilSample.fromJson(Map<String, dynamic> json) => SoilSample(
        temperature: (json['temperature'] as num).toDouble(),
        moisture: (json['moisture'] as num).toDouble(),
        ec: (json['ec'] as num).toDouble(),
        salinity: (json['salinity'] as num).toDouble(),
        nitrogen: (json['nitrogen'] as num).toDouble(),
        phosphorus: (json['phosphorus'] as num).toDouble(),
        potassium: (json['potassium'] as num).toDouble(),
        ph: (json['ph'] as num).toDouble(),
      );
}

/// Averaged result plus raw samples. Completed records contain exactly 10 samples.
class SoilMeasurement {
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
    this.measurementName = '',
    this.rawSamples = const [],
    this.deviceId = AppConstants.defaultDeviceId,
    this.deviceMetadata = const {},
    this.isSyncedToCloud = false,
    this.latitude,
    this.longitude,
    this.gpsAccuracy,
    this.locationTimestamp,
  });

  final String id;
  String get measurementId => id;
  final String measurementName;
  final double temperature;
  final double moisture;
  final double ec;
  final double salinity;
  final double nitrogen;
  final double phosphorus;
  final double potassium;
  final double ph;
  final DateTime timestamp;
  final List<SoilSample> rawSamples;
  final String deviceId;
  final Map<String, dynamic> deviceMetadata;
  bool isSyncedToCloud;
  final double? latitude;
  final double? longitude;
  final double? gpsAccuracy;
  final DateTime? locationTimestamp;

  factory SoilMeasurement.fromAveragedSamples({
    required String id,
    required List<SoilSample> rawSamples,
    required DateTime timestamp,
    required String deviceId,
    required Map<String, dynamic> deviceMetadata,
    String measurementName = '',
    double? latitude,
    double? longitude,
    double? gpsAccuracy,
    DateTime? locationTimestamp,
  }) {
    if (rawSamples.length != 10 || rawSamples.any((sample) => !sample.isComplete)) {
      throw ArgumentError('A completed measurement requires exactly 10 valid samples.');
    }
    double average(double Function(SoilSample sample) value) =>
        rawSamples.map(value).reduce((a, b) => a + b) / rawSamples.length;
    return SoilMeasurement(
      id: id,
      measurementName: measurementName,
      temperature: average((sample) => sample.temperature),
      moisture: average((sample) => sample.moisture),
      ec: average((sample) => sample.ec),
      salinity: average((sample) => sample.salinity),
      nitrogen: average((sample) => sample.nitrogen),
      phosphorus: average((sample) => sample.phosphorus),
      potassium: average((sample) => sample.potassium),
      ph: average((sample) => sample.ph),
      timestamp: timestamp,
      rawSamples: List.unmodifiable(rawSamples),
      deviceId: deviceId,
      deviceMetadata: Map.unmodifiable(deviceMetadata),
      latitude: latitude,
      longitude: longitude,
      gpsAccuracy: gpsAccuracy,
      locationTimestamp: locationTimestamp,
    );
  }

  /// Legacy helper retained for callers that convert one Modbus frame.
  factory SoilMeasurement.fromRawBytes(
    Uint8List bytes, {
    double? latitude,
    double? longitude,
    double? gpsAccuracy,
    DateTime? locationTimestamp,
  }) {
    final sample = SoilSample.fromRawBytes(bytes);
    final now = DateTime.now();
    return SoilMeasurement(
      id: 'LOG-${now.millisecondsSinceEpoch}',
      temperature: sample.temperature,
      moisture: sample.moisture,
      ec: sample.ec,
      salinity: sample.salinity,
      nitrogen: sample.nitrogen,
      phosphorus: sample.phosphorus,
      potassium: sample.potassium,
      ph: sample.ph,
      timestamp: now,
      rawSamples: [sample],
      latitude: latitude,
      longitude: longitude,
      gpsAccuracy: gpsAccuracy,
      locationTimestamp: locationTimestamp,
    );
  }

  factory SoilMeasurement.initial() => SoilMeasurement(
        id: 'INIT',
        temperature: 23.6,
        moisture: 0,
        ec: 0,
        salinity: 0,
        nitrogen: 0,
        phosphorus: 0,
        potassium: 0,
        ph: 7,
        timestamp: DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        // Existing top-level fields remain for historic map/history consumers.
        'id': id,
        'measurement_id': id,
        'measurement_name': measurementName,
        'timestamp': timestamp.toIso8601String(),
        'device_id': deviceId,
        'device_metadata': deviceMetadata,
        'sync_status': isSyncedToCloud,
        'isSyncedToCloud': isSyncedToCloud,
        'temperature': temperature,
        'moisture': moisture,
        'ec': ec,
        'salinity': salinity,
        'nitrogen': nitrogen,
        'phosphorus': phosphorus,
        'potassium': potassium,
        'ph': ph,
        'average_result': _averageJson(),
        'raw_samples': rawSamples.map((sample) => sample.toJson()).toList(),
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (gpsAccuracy != null) 'gpsAccuracy': gpsAccuracy,
        if (locationTimestamp != null)
          'locationTimestamp': locationTimestamp!.toIso8601String(),
      };

  Map<String, dynamic> _averageJson() => {
        'temperature': temperature,
        'moisture': moisture,
        'ec': ec,
        'salinity': salinity,
        'nitrogen': nitrogen,
        'phosphorus': phosphorus,
        'potassium': potassium,
        'ph': ph,
      };

  factory SoilMeasurement.fromJson(Map<String, dynamic> json) {
    final average = (json['average_result'] as Map?)?.cast<String, dynamic>() ?? json;
    num value(String key) => (json[key] ?? average[key] ?? 0) as num;
    final raw = json['raw_samples'] ?? json['rawSamples'];
    final rawSamples = raw is List
        ? raw.whereType<Map>().map((item) {
            return SoilSample.fromJson(item.cast<String, dynamic>());
          }).toList(growable: false)
        : const <SoilSample>[];
    final metadata = json['device_metadata'] ?? json['deviceMetadata'];
    final syncValue = json['sync_status'] ?? json['isSyncedToCloud'];
    return SoilMeasurement(
      id: (json['measurement_id'] ?? json['id'] ??
              'LOG-${DateTime.now().millisecondsSinceEpoch}') as String,
      measurementName:
          (json['measurement_name'] ?? json['measurementName'] ?? '') as String,
      temperature: value('temperature').toDouble(),
      moisture: value('moisture').toDouble(),
      ec: value('ec').toDouble(),
      salinity: value('salinity').toDouble(),
      nitrogen: value('nitrogen').toDouble(),
      phosphorus: value('phosphorus').toDouble(),
      potassium: value('potassium').toDouble(),
      ph: value('ph').toDouble(),
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
      rawSamples: rawSamples,
      deviceId:
          (json['device_id'] ?? json['deviceId'] ?? AppConstants.defaultDeviceId)
              as String,
      deviceMetadata:
          metadata is Map ? Map<String, dynamic>.from(metadata) : const {},
      isSyncedToCloud: syncValue is bool ? syncValue : false,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      gpsAccuracy: (json['gpsAccuracy'] as num?)?.toDouble(),
      locationTimestamp: json['locationTimestamp'] != null
          ? DateTime.tryParse(json['locationTimestamp'] as String)
          : null,
    );
  }

  SoilMeasurement copyWith({bool? isSyncedToCloud}) => SoilMeasurement(
        id: id,
        measurementName: measurementName,
        temperature: temperature,
        moisture: moisture,
        ec: ec,
        salinity: salinity,
        nitrogen: nitrogen,
        phosphorus: phosphorus,
        potassium: potassium,
        ph: ph,
        timestamp: timestamp,
        rawSamples: rawSamples,
        deviceId: deviceId,
        deviceMetadata: deviceMetadata,
        isSyncedToCloud: isSyncedToCloud ?? this.isSyncedToCloud,
        latitude: latitude,
        longitude: longitude,
        gpsAccuracy: gpsAccuracy,
        locationTimestamp: locationTimestamp,
      );
}
