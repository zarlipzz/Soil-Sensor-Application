import 'package:flutter/material.dart';
import '../models/soil_measurement.dart';
import '../utils/app_constants.dart';

/// Reusable card displaying detailed historical log entry with sensor parameters and GPS coordinates.
class MeasurementDetailCard extends StatelessWidget {
  final SoilMeasurement item;
  final int index;
  final int totalCount;

  const MeasurementDetailCard({
    super.key,
    required this.item,
    required this.index,
    required this.totalCount,
  });

  String _formatDateTime(DateTime dt) {
    final timeStr =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} $timeStr';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.softBlue.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '#${totalCount - index}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.softBlue,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatDateTime(item.timestamp),
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: item.isSyncedToCloud
                        ? AppColors.lightBlueTint
                        : const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        item.isSyncedToCloud
                            ? Icons.cloud_done_rounded
                            : Icons.cloud_queue_rounded,
                        size: 14,
                        color: item.isSyncedToCloud
                            ? AppColors.softBlue
                            : Colors.orange.shade800,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        item.isSyncedToCloud ? 'Synced' : 'Local Only',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: item.isSyncedToCloud
                              ? AppColors.softBlue
                              : Colors.orange.shade900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Sensor parameter chips
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _buildSmallChip('Temp', '${item.temperature.toStringAsFixed(1)}°C', AppColors.tempColor),
                _buildSmallChip('Moist', '${item.moisture.toStringAsFixed(1)}%', AppColors.moistureColor),
                _buildSmallChip('pH', item.ph.toStringAsFixed(2), AppColors.phColor),
                _buildSmallChip('EC', '${item.ec} µS/cm', AppColors.ecColor),
                _buildSmallChip('N', '${item.nitrogen}', AppColors.nitrogenColor),
                _buildSmallChip('P', '${item.phosphorus}', AppColors.phosphorusColor),
                _buildSmallChip('K', '${item.potassium}', AppColors.potassiumColor),
                _buildSmallChip('Salinity', '${item.salinity} mg/L', AppColors.salinityColor),
                if (item.latitude != null && item.longitude != null)
                  _buildSmallChip(
                    'GPS',
                    '${item.latitude!.toStringAsFixed(4)}, ${item.longitude!.toStringAsFixed(4)}',
                    const Color(0xFF00796B),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmallChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 0.8),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
