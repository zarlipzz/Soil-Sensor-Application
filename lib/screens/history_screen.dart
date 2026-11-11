import 'package:flutter/material.dart';
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
        title: Text('บันทึกในเครื่อง (${logs.length} รายการ)'),
        actions: [
          if (logs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'ล้างบันทึกทั้งหมด',
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
                  const Text(
                    'ยังไม่มีข้อมูลบันทึกในเครื่อง',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'กดปุ่ม "อ่านค่าจากเซนเซอร์เดี๋ยวนี้" เพื่อบันทึกข้อมูลแรก',
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
        title: const Text('ยืนยันล้างบันทึกในเครื่อง'),
        content: const Text('คุณต้องการลบข้อมูล Local Log ทั้งหมดหรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ลบทั้งหมด', style: TextStyle(color: Colors.white)),
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
