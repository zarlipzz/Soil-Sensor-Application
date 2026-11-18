import 'package:flutter/material.dart';

import '../models/soil_measurement.dart';
import '../utils/app_constants.dart';

class LocalHistorySheet extends StatefulWidget {
  const LocalHistorySheet({
    super.key,
    required this.records,
    required this.scrollController,
    required this.onClear,
    required this.onRetryPending,
  });

  final List<SoilMeasurement> records;
  final ScrollController scrollController;
  final Future<void> Function() onClear;
  final Future<String> Function() onRetryPending;

  @override
  State<LocalHistorySheet> createState() => _LocalHistorySheetState();
}

class _LocalHistorySheetState extends State<LocalHistorySheet> {
  final _searchController = TextEditingController();
  String _query = '';
  bool _selectAll = true;
  final Set<String> _selectedNames = {};
  final Set<String> _selectedDates = {};
  bool _showFilterPanel = false;
  bool _isRetrying = false;
  String? _retryMessage;
  Set<String> _retryIds = {};

  Future<void> _retryUploads() async {
    if (_isRetrying) return;
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
        _retryMessage = 'ส่งรายการค้างไม่สำเร็จ กรุณาลองอีกครั้ง';
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

  void _toggleFilterPanel() {
    FocusScope.of(context).unfocus();
    if (widget.scrollController.hasClients) {
      widget.scrollController.jumpTo(0);
    }
    setState(() => _showFilterPanel = !_showFilterPanel);
  }

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

  List<SoilMeasurement> get _filteredRecords {
    return widget.records.where((r) {
      final name = r.measurementName.trim().isEmpty
          ? 'Unnamed'
          : r.measurementName.trim();
      final date = _formatDate(r.timestamp);

      // Check text search
      if (_query.isNotEmpty &&
          !name.toLowerCase().contains(_query.toLowerCase()) &&
          !date.contains(_query)) {
        return false;
      }

      // Check checkbox selections
      if (_selectAll) return true;

      final nameMatches =
          _selectedNames.isEmpty || _selectedNames.contains(name);
      final dateMatches =
          _selectedDates.isEmpty || _selectedDates.contains(date);
      return nameMatches && dateMatches;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredRecords;
    final distinctNames = _distinctNames;
    final distinctDates = _distinctDates;
    final pendingCount = widget.records
        .where((record) => !record.isSyncedToCloud)
        .length;
    final sentDuringRetry = widget.records
        .where(
          (record) => record.isSyncedToCloud && _retryIds.contains(record.id),
        )
        .length;

    return Column(
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
          child: Row(
            children: [
              const Icon(Icons.history_rounded, color: AppColors.softBlue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Local History (${filtered.length}/${widget.records.length})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (_showFilterPanel)
                TextButton.icon(
                  onPressed: _toggleFilterPanel,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('ยืนยัน'),
                )
              else
                IconButton(
                  tooltip: 'ตัวกรอง',
                  icon: Icon(
                    Icons.filter_alt_outlined,
                    color: !_selectAll ? Colors.orange : AppColors.softBlue,
                  ),
                  onPressed: _toggleFilterPanel,
                ),
              IconButton(
                tooltip: 'Clear all history',
                onPressed: widget.records.isEmpty || _isRetrying
                    ? null
                    : widget.onClear,
                icon: const Icon(Icons.delete_outline, color: Colors.red),
              ),
            ],
          ),
        ),
        if (!_showFilterPanel && (pendingCount > 0 || _isRetrying))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isRetrying ? null : _retryUploads,
                icon: _isRetrying
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_upload_outlined),
                label: Text(
                  _isRetrying
                      ? 'กำลังส่ง… สำเร็จ $sentDuringRetry/${_retryIds.length}'
                      : 'ส่งรายการค้าง ($pendingCount)',
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
                hintText: 'ค้นหาชื่อการวัด หรือ วันที่...',
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
        // Checkbox Filter panel (Requirement 8)
        if (_showFilterPanel)
          Expanded(
            child: ListView(
              key: const ValueKey('history-filters'),
              controller: widget.scrollController,
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
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
                          const Text(
                            'เลือกดูข้อมูล:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
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
                          const Text(
                            'ทั้งหมด',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      if (!_selectAll) ...[
                        if (distinctNames.isNotEmpty) ...[
                          const Divider(height: 12),
                          const Text(
                            'ติ๊กเลือกชื่อการวัด:',
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
                                label: Text(
                                  name,
                                  style: const TextStyle(fontSize: 12),
                                ),
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
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        ],
                        if (distinctDates.isNotEmpty) ...[
                          const Divider(height: 12),
                          const Text(
                            'ติ๊กเลือกวันที่:',
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
                                label: Text(
                                  date,
                                  style: const TextStyle(fontSize: 12),
                                ),
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
                ),
              ],
            ),
          )
        else ...[
          const Divider(height: 1),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      widget.records.isEmpty
                          ? 'ยังไม่มีข้อมูลการวัดในเครื่อง'
                          : 'ไม่พบรายการที่ตรงกับตัวกรองที่เลือก',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    key: const ValueKey('history-results'),
                    controller: widget.scrollController,
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final record = filtered[index];
                      final title = record.measurementName.trim().isEmpty
                          ? 'Unnamed measurement'
                          : record.measurementName.trim();
                      return ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.eco_rounded,
                          color: AppColors.softBlue,
                          size: 20,
                        ),
                        title: Text(
                          '$title — ${_formatDate(record.timestamp)} ${record.timestamp.hour.toString().padLeft(2, '0')}:${record.timestamp.minute.toString().padLeft(2, '0')}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          'ความชื้น ${record.moisture.toStringAsFixed(1)}% · อุณหภูมิ ${record.temperature.toStringAsFixed(2)} °C · pH ${record.ph.toStringAsFixed(2)}',
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
                              record.isSyncedToCloud ? 'ส่งแล้ว' : 'ค้างส่ง',
                            ),
                          ],
                        ),
                        onTap: () => showDialog<void>(
                          context: context,
                          builder: (_) => HistoryRecordDetails(record: record),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ],
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
          ? 'Unnamed measurement'
          : record.measurementName,
    ),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ID: ${record.id}'),
            Text('Recorded: ${record.timestamp}'),
            const Divider(),
            _value(
              'ความชื้น (Moisture)',
              '${record.moisture.toStringAsFixed(1)} %',
            ),
            _value(
              'อุณหภูมิ (Temperature)',
              '${record.temperature.toStringAsFixed(2)} °C',
            ),
            _value('pH', record.ph.toStringAsFixed(2)),
            _value('EC', '${record.ec} µS/cm'),
            _value('ไนโตรเจน (N)', '${record.nitrogen} mg/kg'),
            _value('ฟอสฟอรัส (P)', '${record.phosphorus} mg/kg'),
            _value('โพแทสเซียม (K)', '${record.potassium} mg/kg'),
            _value('ความเค็ม (Salinity)', '${record.salinity} mg/L'),
            if (record.latitude != null && record.longitude != null)
              _value(
                'GPS',
                '${record.latitude}, ${record.longitude} (±${record.gpsAccuracy?.toStringAsFixed(0) ?? "?"}m)',
              ),
            _value('Device ID', record.deviceId),
            if (record.deviceMetadata.isNotEmpty) ...[
              const Divider(),
              const Text(
                'Device metadata',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              ...record.deviceMetadata.entries.map(
                (entry) => _value(entry.key, '${entry.value}'),
              ),
            ],
            _value(
              'Home Assistant Sync',
              record.isSyncedToCloud ? 'Synced' : 'Not synced',
            ),
            if (record.rawSamples.isNotEmpty) ...[
              const Divider(),
              Text(
                'Raw samples (${record.rawSamples.length})',
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
        child: const Text('Close'),
      ),
    ],
  );

  Widget _value(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Text('$label: $value'),
  );
}
