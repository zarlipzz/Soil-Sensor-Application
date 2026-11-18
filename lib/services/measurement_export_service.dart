import 'dart:convert';
import 'dart:io';

import 'package:share_plus/share_plus.dart';

import '../models/soil_measurement.dart';

class MeasurementExportService {
  static const fields = <String>[
    'measurement_id','measurement_name','timestamp','latitude','longitude','altitude',
    'temperature','moisture','ec','salinity','nitrogen','phosphorus','potassium','ph',
    'raw_samples','device_id','manufacturer','model','platform','os_version','app_version','sync_status',
  ];

  static String toJson(List<SoilMeasurement> records) => const JsonEncoder.withIndent('  ')
      .convert(records.map((record) => record.toJson()).toList());

  static String toCsv(List<SoilMeasurement> records) {
    final rows = <List<String>>[fields];
    for (final item in records) {
      final metadata = item.deviceMetadata;
      rows.add([
        item.id, item.measurementName, item.timestamp.toIso8601String(),
        '${item.latitude ?? ''}', '${item.longitude ?? ''}', '${metadata['altitude'] ?? ''}',
        '${item.temperature}', '${item.moisture}', '${item.ec}', '${item.salinity}',
        '${item.nitrogen}', '${item.phosphorus}', '${item.potassium}', '${item.ph}',
        jsonEncode(item.rawSamples.map((sample) => sample.toJson()).toList()),
        item.deviceId, '${metadata['manufacturer'] ?? ''}', '${metadata['model'] ?? ''}',
        '${metadata['platform'] ?? ''}', '${metadata['os_version'] ?? ''}',
        '${metadata['app_version'] ?? ''}', item.isSyncedToCloud ? 'synced' : 'not_synced',
      ]);
    }
    String cell(String value) => '"${value.replaceAll('"', '""')}"';
    return '\uFEFF${rows.map((row) => row.map(cell).join(',')).join('\r\n')}';
  }

  static String fileName(DateTime date, String format) {
    final stamp = '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}_'
        '${date.hour.toString().padLeft(2, '0')}${date.minute.toString().padLeft(2, '0')}${date.second.toString().padLeft(2, '0')}';
    return 'soil_measurements_$stamp.$format';
  }

  static String mimeType(String format) =>
      format == 'csv' ? 'text/csv' : 'application/json';

  static Future<File> writeExport({
    required List<SoilMeasurement> records,
    required String format,
    required Directory directory,
    required DateTime timestamp,
  }) async {
    if (format != 'csv' && format != 'json') {
      throw ArgumentError.value(format, 'format', 'Expected csv or json');
    }
    final file = File('${directory.path}${Platform.pathSeparator}${fileName(timestamp, format)}');
    await file.writeAsString(format == 'csv' ? toCsv(records) : toJson(records), encoding: utf8);
    if (!await file.exists()) {
      throw FileSystemException('Export file was not created', file.path);
    }
    return file;
  }

  static Future<ShareResult> shareExportFile({
    required File file,
    required String format,
    required int recordCount,
    SharePlus? sharePlus,
  }) async {
    if (!await file.exists()) {
      throw FileSystemException('Export file is missing', file.path);
    }
    return (sharePlus ?? SharePlus.instance).share(ShareParams(
      files: [XFile(file.path, mimeType: mimeType(format), name: file.uri.pathSegments.last)],
      subject: 'Soil measurements ($recordCount)',
      title: 'Share soil measurements',
    ));
  }
}
