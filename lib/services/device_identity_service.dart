import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceIdentity {
  const DeviceIdentity({required this.id, required this.metadata});

  final String id;
  final Map<String, dynamic> metadata;
}

/// Provides an app-scoped installation ID; never reads IMEI or hardware IDs.
class DeviceIdentityService {
  static const _installationKey = 'soil_installation_uuid_v1';
  DeviceIdentityService({DeviceInfoPlugin? deviceInfo})
    : _deviceInfo = deviceInfo ?? DeviceInfoPlugin();

  final DeviceInfoPlugin _deviceInfo;

  Future<DeviceIdentity> getIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    final id = await getOrCreateInstallationId(prefs);
    final package = await PackageInfo.fromPlatform();
    final metadata = <String, dynamic>{
      'platform': defaultTargetPlatform.name,
      'app_version': '${package.version}+${package.buildNumber}',
    };
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = await _deviceInfo.androidInfo;
      metadata.addAll({
        'manufacturer': android.manufacturer,
        'model': android.model,
        'os_version': android.version.release,
      });
    }
    return DeviceIdentity(id: id, metadata: metadata);
  }

  static Future<String> getOrCreateInstallationId(
    SharedPreferences prefs, {
    String Function()? createId,
  }) async {
    final existing = prefs.getString(_installationKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = (createId ?? _newUuidV4)();
    await prefs.setString(_installationKey, id);
    return id;
  }

  static String _newUuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int value) => value.toRadixString(16).padLeft(2, '0');
    final text = bytes.map(hex).join();
    return '${text.substring(0, 8)}-${text.substring(8, 12)}-'
        '${text.substring(12, 16)}-${text.substring(16, 20)}-'
        '${text.substring(20)}';
  }
}
