import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../utils/app_language.dart';

import '../models/soil_measurement.dart';
import '../utils/app_constants.dart';
import '../utils/history_filters.dart';

class LocalHistorySheet extends StatefulWidget {
  const LocalHistorySheet({
    super.key,
    required this.records,
    required this.scrollController,
    required this.autoUploadMode,
    required this.hasInternet,
    required this.onAutoUploadChanged,
    required this.onClear,
    required this.onRetryPending,
  });

  final List<SoilMeasurement> records;
  final ScrollController scrollController;
  final ValueListenable<bool?> autoUploadMode;
  final ValueListenable<bool> hasInternet;
  final Future<bool> Function(bool) onAutoUploadChanged;
  final Future<void> Function() onClear;
  final Future<String> Function() onRetryPending;

  @override
  State<LocalHistorySheet> createState() => _LocalHistorySheetState();
}

class _LocalHistorySheetState extends State<LocalHistorySheet> {
  final _searchController = TextEditingController();
  String _query = '';
  bool _selectAll = false;
  final Set<String> _selectedNames = {};
  final Set<String> _selectedDates = {};
  bool _confirmedAll = false;
  Set<String> _confirmedNames = {};
  Set<String> _confirmedDates = {};
  bool _showFilterPanel = false;
  bool _savingAutoUpload = false;
  bool _isRetrying = false;
  String? _retryMessage;
  Set<String> _retryIds = {};

  Future<void> _changeAutoUpload(bool enabled) async {
    if (_savingAutoUpload) return;
    setState(() => _savingAutoUpload = true);
    final saved = await widget.onAutoUploadChanged(enabled);
    if (!mounted) return;
    setState(() => _savingAutoUpload = false);
    if (!saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'บันทึกโหมดส่งข้อมูลอัตโนมัติไม่สำเร็จ',
              'Could not save the automatic upload setting',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _retryUploads() async {
    if (_isRetrying || !widget.hasInternet.value) return;
    setState(() {
      _isRetrying = true;
      _retryMessage = null;
      _retryIds = {
        for (final record in widget.records)
          if (!record.isSyncedToCloud) record.id,
      };
    });
    final String message;
    try {
      message = await widget.onRetryPending();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isRetrying = false;
        _retryMessage = context.tr(
          'ส่งรายการค้างไม่สำเร็จ กรุณาลองอีกครั้ง',
          'Could not send pending items. Please try again.',
        );
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _isRetrying = false;
      _retryMessage = message;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleFilterPanel({bool confirm = false}) {
    FocusScope.of(context).unfocus();
    if (widget.scrollController.hasClients) {
      widget.scrollController.jumpTo(0);
    }
    setState(() {
      if (!_showFilterPanel) {
        _selectAll = _confirmedAll;
        _selectedNames
          ..clear()
          ..addAll(_confirmedNames.where(_distinctNames.contains));
        _selectedDates
          ..clear()
          ..addAll(_confirmedDates.where(_availableDates.contains));
      } else if (confirm) {
        _confirmedAll = _selectAll;
        _confirmedNames = Set.of(_selectedNames);
        _confirmedDates = Set.of(_selectedDates);
      }
      _showFilterPanel = !_showFilterPanel;
    });
  }

  List<String> get _distinctNames =>
      widget.records.map(measurementFilterName).toSet().toList()..sort();

  Set<String> get _availableDates =>
      availableMeasurementDates(widget.records, _selectedNames);

  List<SoilMeasurement> get _filteredRecords {
    return widget.records.where((r) {
      final name = measurementFilterName(r);
      final date = measurementFilterDate(r.timestamp);

      // Check text search
      if (_query.isNotEmpty &&
          !name.toLowerCase().contains(_query.toLowerCase()) &&
          !date.contains(_query)) {
        return false;
      }

      // Check checkbox selections
      final dateMatches =
          _confirmedDates.isEmpty || _confirmedDates.contains(date);
      return matchesMeasurementNames(name, _confirmedNames) && dateMatches;
    }).toList();
  }

  Widget _buildHeader(int filteredCount) {
    final title = Row(
      children: [
        const Icon(Icons.history_rounded, color: AppColors.softBlue),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            context.tr(
              'ประวัติในเครื่อง ($filteredCount/${widget.records.length})',
              'Local history ($filteredCount/${widget.records.length})',
            ),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: ValueListenableBuilder<bool?>(
            valueListenable: widget.autoUploadMode,
            builder: (context, enabled, _) => MergeSemantics(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      context.tr('ส่งข้อมูลอัตโนมัติ', 'Automatic uploads'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Switch(
                    value: enabled ?? false,
                    onChanged: enabled == null || _savingAutoUpload
                        ? null
                        : _changeAutoUpload,
                  ),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: _showFilterPanel
              ? context.tr('ปิดตัวกรอง', 'Close filters')
              : context.tr('ตัวกรอง', 'Filters'),
          icon: Icon(
            _showFilterPanel ? Icons.close : Icons.filter_alt_outlined,
            color: _confirmedNames.isNotEmpty || _confirmedDates.isNotEmpty
                ? Colors.orange
                : AppColors.softBlue,
          ),
          onPressed: _toggleFilterPanel,
        ),
        IconButton(
          tooltip: context.tr('ล้างประวัติทั้งหมด', 'Clear all history'),
          onPressed: widget.records.isEmpty || _isRetrying
              ? null
              : widget.onClear,
          icon: const Icon(Icons.delete_outline, color: Colors.red),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 420) {
            return Column(
              children: [
                title,
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: title),
              Expanded(
                flex: 2,
                child: Align(alignment: Alignment.centerRight, child: actions),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredRecords;
    final distinctNames = _distinctNames;
    final distinctDates = _availableDates;
    final hasSelection =
        widget.records.isNotEmpty &&
        (_selectAll || _selectedNames.isNotEmpty || _selectedDates.isNotEmpty);
    final pendingCount = widget.records
        .where((record) => !record.isSyncedToCloud)
        .length;
    final sentDuringRetry = widget.records
        .where(
          (record) => record.isSyncedToCloud && _retryIds.contains(record.id),
        )
        .length;

    final controls = Column(
      children: [
        const SizedBox(height: 12),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        _buildHeader(filtered.length),
        if (!_showFilterPanel && (pendingCount > 0 || _isRetrying))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              width: double.infinity,
              child: ValueListenableBuilder<bool>(
                valueListenable: widget.hasInternet,
                builder: (context, hasInternet, _) => FilledButton.icon(
                  onPressed: !hasInternet || _isRetrying ? null : _retryUploads,
                  style: FilledButton.styleFrom(
                    disabledBackgroundColor: Colors.grey.shade300,
                    disabledForegroundColor: Colors.grey.shade700,
                  ),
                  icon: _isRetrying
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_upload_outlined),
                  label: Text(
                    _isRetrying
                        ? context.tr(
                            'กำลังส่ง… สำเร็จ $sentDuringRetry/${_retryIds.length}',
                            'Sending… $sentDuringRetry/${_retryIds.length} sent',
                          )
                        : context.tr(
                            'ส่งรายการค้าง ($pendingCount)',
                            'Send pending items ($pendingCount)',
                          ),
                  ),
                ),
              ),
            ),
          ),
        if (_retryMessage case final String message when !_showFilterPanel)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Semantics(liveRegion: true, child: Text(message)),
          ),
        // Search text box
        if (!_showFilterPanel)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: context.tr(
                  'ค้นหาชื่อการวัด หรือ วันที่...',
                  'Search by name or date...',
                ),
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
      ],
    );
    final filters = Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                context.tr('เลือกดูข้อมูล:', 'Filter measurements:'),
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const Spacer(),
              Checkbox(
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
              Text(
                context.tr('ทั้งหมด', 'All'),
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ],
          ),
          if (!_selectAll) ...[
            if (distinctNames.isNotEmpty) ...[
              const Divider(height: 12),
              Text(
                context.tr('ติ๊กเลือกชื่อการวัด:', 'By measurement name:'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: distinctNames.map((name) {
                  final checked = _selectedNames.contains(name);
                  return FilterChip(
                    label: Text(name, style: const TextStyle(fontSize: 12)),
                    selected: checked,
                    selectedColor: AppColors.lightBlueTint,
                    checkmarkColor: AppColors.softBlue,
                    onSelected: (val) {
                      setState(() {
                        if (val) {
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
              const Divider(height: 12),
              Text(
                context.tr('ติ๊กเลือกวันที่:', 'By date:'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: distinctDates.map((date) {
                  final checked = _selectedDates.contains(date);
                  return FilterChip(
                    label: Text(date, style: const TextStyle(fontSize: 12)),
                    selected: checked,
                    selectedColor: AppColors.lightBlueTint,
                    checkmarkColor: AppColors.softBlue,
                    onSelected: (val) {
                      setState(() {
                        if (val) {
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
    );
    final confirmButton = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: hasSelection
              ? () => _toggleFilterPanel(confirm: true)
              : null,
          icon: const Icon(Icons.check_rounded),
          label: Text(context.tr('ยืนยัน', 'Confirm')),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.softBlue,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey.shade300,
            disabledForegroundColor: Colors.grey.shade700,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final pinConfirm = _showFilterPanel && constraints.maxHeight >= 180;
        return Column(
          children: [
            Expanded(
              child: CustomScrollView(
                key: ValueKey(
                  _showFilterPanel ? 'history-filters' : 'history-results',
                ),
                controller: widget.scrollController,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverToBoxAdapter(child: controls),
                  if (_showFilterPanel) ...[
                    SliverToBoxAdapter(child: filters),
                    if (!pinConfirm) SliverToBoxAdapter(child: confirmButton),
                  ] else ...[
                    const SliverToBoxAdapter(child: Divider(height: 1)),
                    if (filtered.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Text(
                            widget.records.isEmpty
                                ? context.tr(
                                    'ยังไม่มีข้อมูลการวัดในเครื่อง',
                                    'No local measurements yet',
                                  )
                                : context.tr(
                                    'ไม่พบรายการที่ตรงกับตัวกรองที่เลือก',
                                    'No measurements match the selected filters',
                                  ),
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    else
                      SliverList.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final record = filtered[index];
                          final title = record.measurementName.trim().isEmpty
                              ? context.tr(
                                  'การวัดไม่มีชื่อ',
                                  'Unnamed measurement',
                                )
                              : record.measurementName.trim();
                          return ListTile(
                            dense: true,
                            leading: const Icon(
                              Icons.eco_rounded,
                              color: AppColors.softBlue,
                              size: 20,
                            ),
                            title: Text(
                              '$title — ${measurementFilterDate(record.timestamp)} ${record.timestamp.hour.toString().padLeft(2, '0')}:${record.timestamp.minute.toString().padLeft(2, '0')}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              context.tr(
                                'ความชื้น ${record.moisture.toStringAsFixed(1)}% · อุณหภูมิ ${record.temperature.toStringAsFixed(2)} °C · pH ${record.ph.toStringAsFixed(2)}',
                                'Moisture ${record.moisture.toStringAsFixed(1)}% · Temperature ${record.temperature.toStringAsFixed(2)} °C · pH ${record.ph.toStringAsFixed(2)}',
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  record.isSyncedToCloud
                                      ? Icons.cloud_done
                                      : Icons.cloud_off,
                                  color: record.isSyncedToCloud
                                      ? AppColors.softBlue
                                      : Colors.grey,
                                  size: 18,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  record.isSyncedToCloud
                                      ? context.tr('ส่งแล้ว', 'Sent')
                                      : context.tr('ค้างส่ง', 'Pending'),
                                ),
                              ],
                            ),
                            onTap: () {
                              FocusScope.of(context).unfocus();
                              showDialog<void>(
                                context: context,
                                builder: (_) => HistoryRecordDetails(record: record),
                              );
                            },
                          );
                        },
                      ),
                  ],
                ],
              ),
            ),
            if (pinConfirm) confirmButton,
          ],
        );
      },
    );
  }
}

class HistoryRecordDetails extends StatelessWidget {
  const HistoryRecordDetails({super.key, required this.record});
  final SoilMeasurement record;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      record.measurementName.trim().isEmpty
          ? context.tr('การวัดไม่มีชื่อ', 'Unnamed measurement')
          : record.measurementName,
    ),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ID: ${record.id}'),
            Text(
              context.tr(
                'บันทึกเมื่อ: ${record.timestamp}',
                'Recorded: ${record.timestamp}',
              ),
            ),
            const Divider(),
            _value(
              context.tr('ความชื้น (Moisture)', 'Moisture'),
              '${record.moisture.toStringAsFixed(1)} %',
            ),
            _value(
              context.tr('อุณหภูมิ (Temperature)', 'Temperature'),
              '${record.temperature.toStringAsFixed(2)} °C',
            ),
            _value('pH', record.ph.toStringAsFixed(2)),
            _value('EC', '${record.ec} µS/cm'),
            _value(
              context.tr('ไนโตรเจน (N)', 'Nitrogen (N)'),
              '${record.nitrogen} mg/kg',
            ),
            _value(
              context.tr('ฟอสฟอรัส (P)', 'Phosphorus (P)'),
              '${record.phosphorus} mg/kg',
            ),
            _value(
              context.tr('โพแทสเซียม (K)', 'Potassium (K)'),
              '${record.potassium} mg/kg',
            ),
            _value(
              context.tr('ความเค็ม (Salinity)', 'Salinity'),
              '${record.salinity} mg/L',
            ),
            if (record.latitude != null && record.longitude != null)
              _value(
                'GPS',
                '${record.latitude}, ${record.longitude} (±${record.gpsAccuracy?.toStringAsFixed(0) ?? "?"}m)',
              ),
            _value(context.tr('รหัสอุปกรณ์', 'Device ID'), record.deviceId),
            if (record.deviceMetadata.isNotEmpty) ...[
              const Divider(),
              Text(
                context.tr('ข้อมูลอุปกรณ์', 'Device metadata'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              ...record.deviceMetadata.entries.map(
                (entry) => _value(entry.key, '${entry.value}'),
              ),
            ],
            _value(
              context.tr('สถานะการส่งข้อมูล', 'Sync status'),
              record.isSyncedToCloud
                  ? context.tr('ส่งแล้ว', 'Synced')
                  : context.tr('ยังไม่ส่ง', 'Not synced'),
            ),
            if (record.rawSamples.isNotEmpty) ...[
              const Divider(),
              Text(
                context.tr(
                  'ค่าดิบ (${record.rawSamples.length})',
                  'Raw samples (${record.rawSamples.length})',
                ),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              ...record.rawSamples.asMap().entries.map(
                (entry) => Text(
                  '${entry.key + 1}. T:${entry.value.temperature}°C, M:${entry.value.moisture}%, pH:${entry.value.ph}, EC:${entry.value.ec}',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.tr('ปิด', 'Close')),
      ),
    ],
  );

  Widget _value(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Text('$label: $value'),
  );
}
