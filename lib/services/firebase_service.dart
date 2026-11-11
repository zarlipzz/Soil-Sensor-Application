import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';


import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/soil_measurement.dart';
import '../utils/app_constants.dart';

/// Service handling synchronization and data uploads to Google Cloud Firestore.
class FirebaseService {
  final FirebaseFirestore _firestore;
  final String collectionName;

  FirebaseService({
    FirebaseFirestore? firestore,
    this.collectionName = AppConstants.firestoreCollection,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Uploads a single measurement to Cloud Firestore.
  /// Returns `true` if successful, `false` otherwise.
  Future<bool> uploadMeasurement(SoilMeasurement measurement) async {
    // If Firebase hasn't been initialized (e.g., during widget tests), skip the upload.
    try {
      // firebase_core provides Firebase.apps to check initialization.
      // Import is already available in pubspec; guard against missing app.
      if (Firebase.apps.isEmpty) {
        debugPrint('[FirebaseService] Firebase not initialized; upload skipped.');
        return false;
      }
    } catch (_) {
      // If FirebaseCore is not available or throws, also skip.
      debugPrint('[FirebaseService] Unable to verify Firebase initialization; upload skipped.');
      return false;
    }
    try {
      await _firestore
          .collection(collectionName)
          .add(measurement.toFirestoreMap());
      return true;
    } catch (e) {
      debugPrint('[FirebaseService] Firestore upload error (Offline/Failure): $e');
      return false;
    }
  }

  /// Batch syncs multiple unsynced measurements to Cloud Firestore.
  Future<List<String>> uploadBatch(List<SoilMeasurement> measurements) async {
    final syncedIds = <String>[];
    for (var m in measurements) {
      final success = await uploadMeasurement(m);
      if (success) {
        syncedIds.add(m.id);
      }
    }
    return syncedIds;
  }
}
