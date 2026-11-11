import 'package:flutter/material.dart';

/// Application Colors based on modern Soft Light Blue & Soft Grey palette
class AppColors {
  AppColors._();

  static const Color softBlue = Color(0xFF4A7BB0);
  static const Color appbarBlue = Color(0xFF385E88);
  static const Color softGreyBackground = Color(0xFFF0F2F5);
  static const Color lightBlueTint = Color(0xFFE8EEF5);

  // Status & accent colors
  static const Color statusConnected = Color(0xFF3D6B99);
  static const Color statusWarning = Color(0xFFE65100);
  static const Color statusDarkText = Color(0xFF1E293B);
  static const Color statusSubText = Color(0xFF64748B);

  // Sensor metric colors
  static const Color moistureColor = Color(0xFF0288D1);
  static const Color tempColor = Color(0xFFE65100);
  static const Color phColor = Color(0xFF7B1FA2);
  static const Color ecColor = Color(0xFFF57F17);
  static const Color nitrogenColor = Color(0xFF3D6B99);
  static const Color phosphorusColor = softBlue;
  static const Color potassiumColor = Color(0xFF5D4037);
  static const Color salinityColor = Color(0xFF303F9F);
}

/// Application-wide constants
class AppConstants {
  AppConstants._();

  static const String appTitle = 'Soil Multi-Parameter Monitor';
  static const String appSubtitle = 'CH340 USB Modbus RTU + Local Log & Cloud';

  // Local storage keys
  static const String prefKeyLocalLogs = 'soil_local_logs_v1';
  static const int maxLocalLogs = 200;

  // Cloud Firestore collection
  static const String firestoreCollection = 'soil_measurements';
  static const String defaultDeviceId = 'CH340-SOIL-01';

  // Hardware constants
  static const int ch340VendorId = 0x1A86;
  static const int baudRate = 9600;
  static const Duration autoReadInterval = Duration(minutes: 1);
}
