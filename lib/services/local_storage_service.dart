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
            .map(
              (str) => SoilMeasurement.fromJson(
                jsonDecode(str) as Map<String, dynamic>,
              ),
            )
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
    // Keep unsent records available for a later upload, even during long outages.
    while (updatedList.length > maxLogs) {
      final oldestSynced = updatedList.lastIndexWhere(
        (record) => record.isSyncedToCloud,
      );
      if (oldestSynced < 0) break;
      updatedList.removeAt(oldestSynced);
    }

    if (!await saveAll(updatedList)) {
      throw StateError('Unable to save the measurement.');
    }
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

    if (!await saveAll(updatedList)) {
      throw StateError('Unable to save the measurement sync status.');
    }
    return updatedList;
  }

  /// Persists the full list of measurements as JSON strings.
  Future<bool> saveAll(List<SoilMeasurement> measurements) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stringList = measurements
          .map((item) => jsonEncode(item.toJson()))
          .toList();
      return await prefs.setStringList(prefKey, stringList);
    } catch (e) {
      debugPrint('[LocalStorageService] Error saving local logs: $e');
      return false;
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

  /// Deletes only this app's local measurement list from SharedPreferences.
  Future<bool> clearHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.remove(prefKey);
    } catch (e) {
      debugPrint('[LocalStorageService] Error clearing history: $e');
      return false;
    }
  }
}
