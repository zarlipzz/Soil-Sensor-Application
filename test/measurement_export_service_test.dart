import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
import 'package:soil_app/models/soil_measurement.dart';
import 'package:soil_app/services/measurement_export_service.dart';

SoilMeasurement record(String id, String name, {double? latitude}) => SoilMeasurement(
      id: id, measurementName: name, timestamp: DateTime.utc(2026, 11, 16, 10, 57),
      temperature: 20, moisture: 30, ec: 40, salinity: 50, nitrogen: 1,
      phosphorus: 2, potassium: 3, ph: 6.5, latitude: latitude,
      deviceId: 'installation', deviceMetadata: const {'platform': 'android'},
    );

class FakeSharePlatform extends SharePlatform {
  ShareParams? received;

  @override
  Future<ShareResult> share(ShareParams params) async {
    received = params;
    return const ShareResult('fake', ShareResultStatus.success);
  }
}

void main() {
  test('CSV has headers, multiple records, Thai and English names, BOM', () {
    final csv = MeasurementExportService.toCsv([record('a', 'แปลงเหนือ', latitude: 13), record('b', 'North field')]);
    expect(csv.startsWith('\uFEFF'), isTrue);
    for (final header in MeasurementExportService.fields) { expect(csv, contains(header)); }
    expect(csv, contains('แปลงเหนือ'));
    expect(csv, contains('North field'));
    expect(csv, contains('"a"'));
    expect(csv, contains('"b"'));
  });

  test('JSON decodes and preserves complete model fields and optional values', () {
    final input = record('x', 'ดิน A', latitude: 1);
    final json = jsonDecode(MeasurementExportService.toJson([input])) as List;
    final decoded = json.single as Map<String, dynamic>;
    expect(decoded['measurement_name'], 'ดิน A');
    expect(decoded['measurement_id'], 'x');
    expect(decoded['latitude'], 1);
    expect(decoded['raw_samples'], isEmpty);
    expect(decoded['device_metadata']['platform'], 'android');
  });

  test('empty CSV and JSON remain valid and filename has format extension', () {
    expect(MeasurementExportService.toCsv([]), contains('measurement_id'));
    expect(jsonDecode(MeasurementExportService.toJson([])), isEmpty);
    expect(MeasurementExportService.fileName(DateTime(2026, 1, 2), 'csv'), endsWith('.csv'));
    expect(MeasurementExportService.fileName(DateTime(2026, 1, 2), 'json'), endsWith('.json'));
  });

  test('CSV and JSON exports share the generated file with its MIME type', () async {
    final directory = await Directory.systemTemp.createTemp('soil_export_test_');
    addTearDown(() => directory.delete(recursive: true));
    final timestamp = DateTime(2026, 11, 17, 8, 30, 12);

    for (final format in ['csv', 'json']) {
      final file = await MeasurementExportService.writeExport(
        records: [record('share-$format', 'Thai / English')],
        format: format,
        directory: directory,
        timestamp: timestamp,
      );
      final platform = FakeSharePlatform();
      final result = await MeasurementExportService.shareExportFile(
        file: file,
        format: format,
        recordCount: 1,
        sharePlus: SharePlus.custom(platform),
      );

      expect(await file.exists(), isTrue);
      expect(result.status, ShareResultStatus.success);
      final sharedFile = platform.received!.files!.single;
      expect(sharedFile.path, file.path);
      expect(sharedFile.name, MeasurementExportService.fileName(timestamp, format));
      expect(sharedFile.mimeType, MeasurementExportService.mimeType(format));
      expect(file.path, endsWith('.$format'));
    }
  });
}
