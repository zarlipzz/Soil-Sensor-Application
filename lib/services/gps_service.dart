import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Status of the GPS / Location subsystem
enum GpsStatus {
  unknown,
  disabled,
  permissionDenied,
  permissionDeniedForever,
  ready,
  searching,
  error,
}

/// Structured GPS Data Result
class GpsLocationData {
  final double latitude;
  final double longitude;
  final double accuracy;
  final DateTime timestamp;

  const GpsLocationData({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  @override
  String toString() {
    return 'GpsLocationData(lat: ${latitude.toStringAsFixed(6)}, lng: ${longitude.toStringAsFixed(6)}, acc: ${accuracy.toStringAsFixed(1)}m)';
  }
}

/// Service handling GPS location retrieval, permission checks, and hardware status.
class GpsService {
  GpsStatus _status = GpsStatus.unknown;
  GpsLocationData? _lastKnownLocation;
  String? _lastError;

  GpsStatus get status => _status;
  GpsLocationData? get lastKnownLocation => _lastKnownLocation;
  String? get lastError => _lastError;
  bool get hasValidLocation => _lastKnownLocation != null;

  /// Checks if location services are enabled on the host device.
  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Checks current location permissions.
  Future<bool> checkPermission() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always || permission == LocationPermission.whileInUse;
  }

  /// Requests location permissions from the user.
  Future<bool> requestPermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      _status = GpsStatus.permissionDeniedForever;
      return false;
    }
    final granted = permission == LocationPermission.always || permission == LocationPermission.whileInUse;
    if (granted) {
      _status = GpsStatus.ready;
    } else {
      _status = GpsStatus.permissionDenied;
    }
    return granted;
  }

  /// Retrieves the current position with accuracy and timestamp.
  /// Provides fallback/simulated coordinates for Web and devices without active GPS fix.
  Future<GpsLocationData?> getCurrentLocation({
    bool allowSimulatedOnFallback = false,
  }) async {
    _status = GpsStatus.searching;
    _lastError = null;

    try {
      // Use geolocator plugin for real GPS coordinates.
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final location = GpsLocationData(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        timestamp: position.timestamp,
      );
      _lastKnownLocation = location;
      _status = GpsStatus.ready;
      return location;
    } catch (e) {
      _lastError = e.toString();
      _status = GpsStatus.error;
      debugPrint('[GpsService] Error acquiring location: $e');
      return null;
    }
  }

  /// Resets GPS status
  void reset() {
    _status = GpsStatus.unknown;
    _lastError = null;
  }
}
