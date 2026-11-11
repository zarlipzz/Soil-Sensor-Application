import 'dart:typed_data';

/// Modbus RTU protocol utilities for the 8-in-1 soil sensor.
class ModbusUtils {
  ModbusUtils._();

  /// Standard Query Command to read 8 registers starting at address 0x0000 from slave ID 0x01
  static final Uint8List queryCommand = Uint8List.fromList([
    0x01, 0x03, 0x00, 0x00, 0x00, 0x08, 0x44, 0x0C,
  ]);

  /// Expected length of valid response frame:
  /// 1 byte (Slave ID) + 1 byte (Func 0x03) + 1 byte (Byte count 0x10 = 16) + 16 bytes (8 registers) + 2 bytes (CRC16)
  static const int expectedResponseLength = 21;

  /// Calculates Modbus RTU CRC-16 checksum
  static int calculateCrc16(List<int> data) {
    int crc = 0xFFFF;
    for (int byte in data) {
      crc ^= (byte & 0xFF);
      for (int i = 0; i < 8; i++) {
        if ((crc & 0x0001) != 0) {
          crc = (crc >> 1) ^ 0xA001;
        } else {
          crc >>= 1;
        }
      }
    }
    return crc & 0xFFFF;
  }

  /// Verifies if a 21-byte packet is a valid Modbus RTU response from the soil sensor
  static bool isValidPacket(Uint8List packet) {
    if (packet.length < expectedResponseLength) return false;
    // Check Slave ID (0x01), Function code (0x03), and Byte count (0x10 = 16 bytes)
    if (packet[0] != 0x01 || packet[1] != 0x03 || packet[2] != 0x10) {
      return false;
    }

    // Optional CRC verification if available in packet
    if (packet.length >= expectedResponseLength) {
      final payload = packet.sublist(0, expectedResponseLength - 2);
      final expectedCrc = calculateCrc16(payload);
      final receivedCrc = packet[expectedResponseLength - 2] |
          (packet[expectedResponseLength - 1] << 8);
      return expectedCrc == receivedCrc;
    }

    return true;
  }
}
