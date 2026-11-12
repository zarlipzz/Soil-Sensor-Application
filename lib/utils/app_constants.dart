import 'package:flutter/material.dart';

/// Application Colors — Light Green theme for Soil Sensor App
class AppColors {
  AppColors._();

  // Primary green palette
  static const Color softBlue = Color(
    0xFF4CAF7D,
  ); // primary green (replaces softBlue)
  static const Color appbarBlue = Color(0xFF388E5A); // darker green appbar
  static const Color softGreyBackground = Color(
    0xFFF1F8F4,
  ); // very light greenish bg
  static const Color lightBlueTint = Color(
    0xFFE0F2EA,
  ); // light green tint for chips

  // Status & accent colors
  static const Color statusConnected = Color(0xFF2E7D52);
  static const Color statusWarning = Color(0xFFE65100);
  static const Color statusDarkText = Color(0xFF1B3A2D);
  static const Color statusSubText = Color(0xFF4A7060);

  // Sensor metric colors (kept distinct for readability)
  static const Color moistureColor = Color(0xFF0288D1);
  static const Color tempColor = Color(0xFFE65100);
  static const Color phColor = Color(0xFF7B1FA2);
  static const Color ecColor = Color(0xFFF57F17);
  static const Color nitrogenColor = Color(0xFF388E3C);
  static const Color phosphorusColor = Color(0xFF4CAF7D);
  static const Color potassiumColor = Color(0xFF5D4037);
  static const Color salinityColor = Color(0xFF1565C0);
}

/// Application-wide constants
class AppConstants {
  AppConstants._();

  static const String appTitle = 'Soil Multi-Parameter Monitor';
  static const String appSubtitle =
      'CH340 USB Modbus RTU + Local Log & Home Assistant';

  // Local storage keys
  static const String prefKeyLocationGroups = 'soil_location_groups_v1';
  static const double locationGroupRadiusMeters = 20.0;
  static const String prefKeyLocalLogs = 'soil_local_logs_v1';
  static const int maxLocalLogs = 200;

  static const String defaultDeviceId = 'CH340-SOIL-01';

  // Hardware constants
  static const int ch340VendorId = 0x1A86;
  static const int baudRate = 9600;
  static const Duration autoReadInterval = Duration(minutes: 1);
}
