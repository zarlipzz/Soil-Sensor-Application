import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/soil_measurement.dart';
import '../utils/app_constants.dart';

/// Service responsible for managing local persistence of soil measurements via SharedPreferences.
class LocalStorageService {
  final String prefKey;
  final int maxLogs;

  LocalStorageService({
    this.prefKey = AppConstants.prefKeyLocalLogs,
    this.maxLogs = AppConstants.maxLocalLogs,
  });

  /// Loads all locally cached measurements from device storage.
  Future<List<SoilMeasurement>> loadMeasurements() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList(prefKey);
      if (rawList != null && rawList.isNotEmpty) {
        return rawList
            .map((str) => SoilMeasurement.fromJson(jsonDecode(str) as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('[LocalStorageService] Error loading local logs: $e');
    }
    return [];
  }

  /// Saves a single measurement at the front of the list, respecting the maximum capacity.
  Future<List<SoilMeasurement>> saveMeasurement(
    SoilMeasurement measurement,
    List<SoilMeasurement> currentList,
  ) async {
    // Retries after a sync failure must not create a second local record.
    if (currentList.any((item) => item.id == measurement.id)) {
      return List<SoilMeasurement>.from(currentList);
    }
    final updatedList = List<SoilMeasurement>.from(currentList);
    updatedList.insert(0, measurement);
    if (updatedList.length > maxLogs) {
      updatedList.removeLast();
    }

    await saveAll(updatedList);
    return updatedList;
  }

  /// Updates the cloud sync flag for a specific measurement by ID.
  Future<List<SoilMeasurement>> updateSyncStatus(
    String id,
    bool isSynced,
    List<SoilMeasurement> currentList,
  ) async {
    final updatedList = currentList.map((item) {
      if (item.id == id) {
        return item.copyWith(isSyncedToCloud: isSynced);
      }
      return item;
    }).toList();

    await saveAll(updatedList);
    return updatedList;
  }

  /// Persists the full list of measurements as JSON strings.
  Future<void> saveAll(List<SoilMeasurement> measurements) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stringList = measurements.map((item) => jsonEncode(item.toJson())).toList();
      await prefs.setStringList(prefKey, stringList);
    } catch (e) {
      debugPrint('[LocalStorageService] Error saving local logs: $e');
    }
  }

  /// Clears all local measurements.
  Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(prefKey);
    } catch (e) {
      debugPrint('[LocalStorageService] Error clearing local logs: $e');
    }
  }
}
