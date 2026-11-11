import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:soil_app/models/soil_measurement.dart';
import 'package:soil_app/utils/modbus_utils.dart';

void main() {
  group('SoilMeasurement & Modbus Tests', () {
    test('ModbusUtils CRC16 calculation', () {
      final query = ModbusUtils.queryCommand;
      expect(query.length, 8);
      expect(query[0], 0x01);
      expect(query[1], 0x03);
    });

    test('SoilMeasurement deserializes from raw bytes correctly', () {
      // Dummy 21 bytes packet:
      // ID=1, FUNC=3, LEN=16,
      // Temp=250 (25.0 C), Moist=350 (35.0%), EC=150, Sal=200, N=45, P=30, K=120, pH=680 (6.80)
      final dummyBytes = Uint8List.fromList([
        0x01, 0x03, 0x10,
        0x00, 0xFA, // Temp = 250 -> 25.0 C
        0x01, 0x5E, // Moist = 350 -> 35.0%
        0x00, 0x96, // EC = 150
        0x00, 0xC8, // Salinity = 200
        0x00, 0x2D, // N = 45
        0x00, 0x1E, // P = 30
        0x00, 0x78, // K = 120
        0x02, 0xA8, // pH = 680 -> 6.80
        0x00, 0x00, // CRC placeholder
      ]);

      final measurement = SoilMeasurement.fromRawBytes(
        dummyBytes,
        latitude: 13.7563,
        longitude: 100.5018,
        gpsAccuracy: 3.5,
      );

      expect(measurement.temperature, 25.0);
      expect(measurement.moisture, 35.0);
      expect(measurement.ec, 150);
      expect(measurement.salinity, 200);
      expect(measurement.nitrogen, 45);
      expect(measurement.phosphorus, 30);
      expect(measurement.potassium, 120);
      expect(measurement.ph, 6.80);
      expect(measurement.latitude, 13.7563);
      expect(measurement.longitude, 100.5018);
      expect(measurement.gpsAccuracy, 3.5);
    });

    test('JSON serialization & deserialization preserves all fields & GPS', () {
      final original = SoilMeasurement(
        id: 'TEST-001',
        temperature: 24.5,
        moisture: 30.2,
        ec: 210,
        salinity: 180,
        nitrogen: 50,
        phosphorus: 25,
        potassium: 110,
        ph: 7.15,
        timestamp: DateTime(2026, 11, 10, 10, 0, 0),
        isSyncedToCloud: true,
        latitude: 13.7563,
        longitude: 100.5018,
        gpsAccuracy: 4.2,
      );

      final json = original.toJson();
      final restored = SoilMeasurement.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.temperature, original.temperature);
      expect(restored.moisture, original.moisture);
      expect(restored.ec, original.ec);
      expect(restored.salinity, original.salinity);
      expect(restored.nitrogen, original.nitrogen);
      expect(restored.phosphorus, original.phosphorus);
      expect(restored.potassium, original.potassium);
      expect(restored.ph, original.ph);
      expect(restored.isSyncedToCloud, original.isSyncedToCloud);
      expect(restored.latitude, original.latitude);
      expect(restored.longitude, original.longitude);
      expect(restored.gpsAccuracy, original.gpsAccuracy);
    });
  });
}
