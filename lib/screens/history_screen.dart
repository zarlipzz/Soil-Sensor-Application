import 'package:flutter/material.dart';

import '../utils/app_language.dart';
import '../models/soil_measurement.dart';
import '../widgets/measurement_detail.dart';

/// Screen displaying historical soil measurements stored locally on the device.
class HistoryScreen extends StatelessWidget {
  final List<SoilMeasurement> logs;
  final VoidCallback onClearLogs;

  const HistoryScreen({
    super.key,
    required this.logs,
    required this.onClearLogs,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.tr(
            'บันทึกในเครื่อง (${logs.length} รายการ)',
            'Local logs (${logs.length} items)',
          ),
        ),
        actions: [
          if (logs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: context.tr('ล้างบันทึกทั้งหมด', 'Clear all logs'),
              onPressed: () => _confirmClear(context),
            ),
        ],
      ),
      body: logs.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 48,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    context.tr(
                      'ยังไม่มีข้อมูลบันทึกในเครื่อง',
                      'No local measurements yet',
                    ),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.tr(
                      'กดปุ่ม "อ่านค่าจากเซนเซอร์เดี๋ยวนี้" เพื่อบันทึกข้อมูลแรก',
                      'Tap Press to measure to save your first reading.',
                    ),
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final item = logs[index];
                return MeasurementDetailCard(
                  item: item,
                  index: index,
                  totalCount: logs.length,
                );
              },
            ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          context.tr('ยืนยันล้างบันทึกในเครื่อง', 'Clear local logs?'),
        ),
        content: Text(
          context.tr(
            'คุณต้องการลบข้อมูล Local Log ทั้งหมดหรือไม่?',
            'Delete all locally stored measurements?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('ยกเลิก', 'Cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              context.tr('ลบทั้งหมด', 'Delete all'),
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      onClearLogs();
      if (context.mounted) {
        Navigator.pop(context);
      }
    }
  }
}
