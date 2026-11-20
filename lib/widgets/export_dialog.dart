import 'package:flutter/material.dart';

import '../utils/app_language.dart';

import 'package:path_provider/path_provider.dart';

import '../models/soil_measurement.dart';
import '../services/measurement_export_service.dart';
import '../utils/app_constants.dart';
import '../utils/history_filters.dart';

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

  List<String> get _distinctNames =>
      widget.records.map(measurementFilterName).toSet().toList()..sort();

  Set<String> get _availableDates =>
      availableMeasurementDates(widget.records, _selectedNames);

  List<SoilMeasurement> get _selectedRecords {
    if (_selectAll) return widget.records;
    if (_selectedNames.isEmpty && _selectedDates.isEmpty) return const [];
    return widget.records.where((r) {
      final name = measurementFilterName(r);
      final date = measurementFilterDate(r.timestamp);
      final dateMatches =
          _selectedDates.isEmpty || _selectedDates.contains(date);
      return matchesMeasurementNames(name, _selectedNames) && dateMatches;
    }).toList();
  }

  Future<void> _doExport() async {
    final targets = _selectedRecords;
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'กรุณาเลือกอย่างน้อย 1 รายการเพื่อส่งออก',
              'Select at least one item to export',
            ),
          ),
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
              context.tr(
                'ส่งออกไฟล์ ${_format.toUpperCase()} เรียบร้อย (${targets.length} รายการ)',
                'Exported ${targets.length} items as ${_format.toUpperCase()}',
              ),
            ),
            backgroundColor: AppColors.softBlue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr('การส่งออกล้มเหลว: $e', 'Export failed: $e'),
            ),
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
    final distinctDates = _availableDates.toList()
      ..sort((a, b) => b.compareTo(a));

    final header = Row(
      children: [
        const Icon(Icons.file_download_outlined, color: AppColors.softBlue),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            context.tr('ส่งออกข้อมูลดิบ', 'Export raw logs'),
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
    final exportButton = ElevatedButton.icon(
      onPressed: _isExporting || selectedCount == 0 ? null : _doExport,
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
            ? context.tr('กำลังส่งออก...', 'Exporting...')
            : selectedCount == 0
            ? context.tr('ส่งออก 0 รายการ', 'Export 0 items')
            : context.tr(
                'ส่งออก $selectedCount รายการ ($_format)',
                'Export $selectedCount items ($_format)',
              ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.softBlue,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.grey.shade300,
        disabledForegroundColor: Colors.grey.shade700,
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scrollAll = constraints.maxHeight < 180;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!scrollAll) ...[header, const SizedBox(height: 8)],
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (scrollAll) ...[header, const SizedBox(height: 8)],
                        // Format selection
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          children: [
                            Text(
                              context.tr('รูปแบบไฟล์: ', 'File format: '),
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            ChoiceChip(
                              label: const Text('CSV (Raw samples)'),
                              selected: _format == 'csv',
                              onSelected: (val) =>
                                  setState(() => _format = 'csv'),
                            ),
                            ChoiceChip(
                              label: const Text('JSON (Full data)'),
                              selected: _format == 'json',
                              onSelected: (val) =>
                                  setState(() => _format = 'json'),
                            ),
                          ],
                        ),
                        const Divider(height: 20),
                        // Selection options
                        Text(
                          context.tr(
                            'เลือกข้อมูลที่จะส่งออก:',
                            'Select items to export:',
                          ),
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        CheckboxListTile(
                          dense: true,
                          title: Text(
                            context.tr(
                              'ทั้งหมด (${widget.records.length} รายการ)',
                              'All (${widget.records.length} items)',
                            ),
                          ),
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
                            Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4,
                              ),
                              child: Text(
                                context.tr(
                                  'เลือกตามชื่อการวัด:',
                                  'By measurement name:',
                                ),
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
                                      _selectedDates.retainAll(_availableDates);
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                          ],
                          if (distinctDates.isNotEmpty) ...[
                            Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4,
                              ),
                              child: Text(
                                context.tr('เลือกตามวันที่:', 'By date:'),
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
                        if (scrollAll) ...[
                          const SizedBox(height: 12),
                          exportButton,
                        ],
                      ],
                    ),
                  ),
                ),
                if (!scrollAll) ...[const SizedBox(height: 12), exportButton],
              ],
            );
          },
        ),
      ),
    );
  }
}
