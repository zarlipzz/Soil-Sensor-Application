import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../models/soil_measurement.dart';
import '../services/measurement_export_service.dart';
import '../utils/app_constants.dart';

/// Modal sheet/dialog to export raw logs with selection checkboxes (All, by Name, by Date).
class ExportDialog extends StatefulWidget {
  const ExportDialog({super.key, required this.records});

  final List<SoilMeasurement> records;

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  String _format = 'csv'; // 'csv' or 'json'
  bool _selectAll = true;
  final Set<String> _selectedNames = {};
  final Set<String> _selectedDates = {};
  bool _isExporting = false;

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  List<String> get _distinctNames {
    final names = <String>{};
    for (final r in widget.records) {
      final name = r.measurementName.trim().isEmpty
          ? 'Unnamed'
          : r.measurementName.trim();
      names.add(name);
    }
    return names.toList()..sort();
  }

  List<String> get _distinctDates {
    final dates = <String>{};
    for (final r in widget.records) {
      dates.add(_formatDate(r.timestamp));
    }
    return dates.toList()..sort((a, b) => b.compareTo(a));
  }

  List<SoilMeasurement> get _selectedRecords {
    if (_selectAll) return widget.records;
    return widget.records.where((r) {
      final name = r.measurementName.trim().isEmpty
          ? 'Unnamed'
          : r.measurementName.trim();
      final date = _formatDate(r.timestamp);
      final nameMatches =
          _selectedNames.isEmpty || _selectedNames.contains(name);
      final dateMatches =
          _selectedDates.isEmpty || _selectedDates.contains(date);
      return nameMatches && dateMatches;
    }).toList();
  }

  Future<void> _doExport() async {
    final targets = _selectedRecords;
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('กรุณาเลือกอย่างน้อย 1 รายการเพื่อส่งออก'),
        ),
      );
      return;
    }

    setState(() => _isExporting = true);
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = await MeasurementExportService.writeExport(
        records: targets,
        format: _format,
        directory: directory,
        timestamp: DateTime.now(),
      );
      await MeasurementExportService.shareExportFile(
        file: file,
        format: _format,
        recordCount: targets.length,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'ส่งออกไฟล์ ${_format.toUpperCase()} เรียบร้อย (${targets.length} รายการ)',
            ),
            backgroundColor: AppColors.softBlue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('การส่งออกล้มเหลว: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _selectedRecords.length;
    final distinctNames = _distinctNames;
    final distinctDates = _distinctDates;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.file_download_outlined,
                  color: AppColors.softBlue,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'ส่งออก Log (Raw File)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Format selection
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [
                        const Text(
                          'รูปแบบไฟล์: ',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        ChoiceChip(
                          label: const Text('CSV (Raw samples)'),
                          selected: _format == 'csv',
                          onSelected: (val) => setState(() => _format = 'csv'),
                        ),
                        ChoiceChip(
                          label: const Text('JSON (Full data)'),
                          selected: _format == 'json',
                          onSelected: (val) => setState(() => _format = 'json'),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    // Selection options
                    const Text(
                      'เลือกข้อมูลที่จะส่งออก:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    CheckboxListTile(
                      dense: true,
                      title: Text('ทั้งหมด (${widget.records.length} รายการ)'),
                      value: _selectAll,
                      activeColor: AppColors.softBlue,
                      onChanged: (val) {
                        setState(() {
                          _selectAll = val ?? false;
                          if (_selectAll) {
                            _selectedNames.clear();
                            _selectedDates.clear();
                          }
                        });
                      },
                    ),
                    if (!_selectAll) ...[
                      if (distinctNames.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: Text(
                            'เลือกตามชื่อการวัด:',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                        Wrap(
                          spacing: 6,
                          children: distinctNames.map((name) {
                            final isChecked = _selectedNames.contains(name);
                            return FilterChip(
                              label: Text(name),
                              selected: isChecked,
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    _selectedNames.add(name);
                                  } else {
                                    _selectedNames.remove(name);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ],
                      if (distinctDates.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: Text(
                            'เลือกตามวันที่:',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                        Wrap(
                          spacing: 6,
                          children: distinctDates.map((date) {
                            final isChecked = _selectedDates.contains(date);
                            return FilterChip(
                              label: Text(date),
                              selected: isChecked,
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    _selectedDates.add(date);
                                  } else {
                                    _selectedDates.remove(date);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed:
                  widget.records.isEmpty || _isExporting || selectedCount == 0
                  ? null
                  : _doExport,
              icon: _isExporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.share_rounded),
              label: Text(
                _isExporting
                    ? 'กำลังส่งออก...'
                    : 'ส่งออก $selectedCount รายการ ($_format)',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.softBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
