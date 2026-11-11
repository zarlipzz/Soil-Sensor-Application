import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/gps_service.dart';
import '../utils/app_constants.dart';

/// Component displaying connection states for USB Hardware, Cloud Sync, and GPS tracking.
class DeviceStatusIndicator extends StatelessWidget {
  final bool isDeviceConnected;
  final bool isCloudSyncing;
  final DateTime lastUpdated;
  final GpsStatus gpsStatus;
  final GpsLocationData? gpsLocation;

  const DeviceStatusIndicator({
    super.key,
    required this.isDeviceConnected,
    required this.isCloudSyncing,
    required this.lastUpdated,
    this.gpsStatus = GpsStatus.ready,
    this.gpsLocation,
  });

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final statusText = kIsWeb
        ? 'โหมดทดสอบจำลอง (Web Preview Mode)'
        : (isDeviceConnected
            ? 'เซนเซอร์ USB เชื่อมต่อแล้ว (CH340 Ready)'
            : 'รอเสียบสายเซนเซอร์ USB OTG');

    final statusColor = kIsWeb
        ? AppColors.softBlue
        : (isDeviceConnected
            ? AppColors.statusConnected
            : AppColors.statusWarning);

    return Column(
      children: [
        Row(
          children: [
            Icon(
              kIsWeb
                  ? Icons.preview_rounded
                  : (isDeviceConnected
                      ? Icons.usb_rounded
                      : Icons.usb_off_rounded),
              color: statusColor,
              size: 26,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    statusText,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    'อัปเดตล่าสุด: ${_formatTime(lastUpdated)}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
            if (isCloudSyncing)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.softBlue),
                ),
              )
            else
              const Tooltip(
                message: 'เชื่อมต่อ Firebase Firestore แล้ว',
                child: Icon(
                  Icons.cloud_done_rounded,
                  color: AppColors.softBlue,
                  size: 22,
                ),
              ),
          ],
        ),

        // GPS status chip bar
        if (gpsLocation != null || gpsStatus != GpsStatus.unknown) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.lightBlueTint,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  size: 16,
                  color: AppColors.softBlue,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    gpsLocation != null
                        ? 'GPS: ${gpsLocation!.latitude.toStringAsFixed(5)}, ${gpsLocation!.longitude.toStringAsFixed(5)} (±${gpsLocation!.accuracy.toStringAsFixed(0)}m)'
                        : 'GPS: กำลังค้นหาสัญญาณตำแหน่ง...',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.statusDarkText,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: gpsLocation != null ? Colors.green : Colors.amber,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
