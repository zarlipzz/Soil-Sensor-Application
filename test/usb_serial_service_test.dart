import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soil_app/services/usb_serial_service.dart';
import 'package:soil_app/utils/modbus_utils.dart';

void main() {
  testWidgets('an answered query cannot time out the next USB query', (
    tester,
  ) async {
    const usbChannel = MethodChannel('usb_serial');
    const portChannel = MethodChannel('test_usb_port');
    const streamChannel = MethodChannel('test_usb_port/stream');
    final messenger = tester.binding.defaultBinaryMessenger;
    var writes = 0;
    messenger.setMockMethodCallHandler(usbChannel, (call) async {
      if (call.method == 'create') return portChannel.name;
      if (call.method == 'listDevices') {
        return [
          {'deviceName': 'test', 'vid': 0x1a86, 'pid': 0x7523, 'deviceId': 1},
        ];
      }
      return null;
    });
    messenger.setMockMethodCallHandler(portChannel, (call) async {
      if (call.method == 'write') writes++;
      return true;
    });
    messenger.setMockMethodCallHandler(streamChannel, (_) async => null);
    addTearDown(() {
      for (final channel in [usbChannel, portChannel, streamChannel]) {
        messenger.setMockMethodCallHandler(channel, null);
      }
    });

    final usb = UsbSerialService();
    var failures = 0;
    usb.onModbusQueryFailed = () => failures++;
    expect(await usb.checkConnection(), isTrue);
    await tester.pump();
    expect(writes, 1);

    await tester.pump(const Duration(milliseconds: 100));
    final payload = [0x01, 0x03, 0x10, ...List.filled(16, 0)];
    final crc = ModbusUtils.calculateCrc16(payload);
    final frame = messenger.handlePlatformMessage(
      streamChannel.name,
      const StandardMethodCodec().encodeSuccessEnvelope(
        Uint8List.fromList([...payload, crc & 0xff, crc >> 8]),
      ),
      (_) {},
    );

    await tester.pump();
    await frame;
    await tester.pump(const Duration(milliseconds: 600));
    expect(writes, 2);
    expect(failures, 0);
    expect(await usb.sendQuery(allowDuringInitialization: true), isFalse);
    await tester.pump(const Duration(milliseconds: 500));
    expect(failures, 1);

    usb.dispose();
    await tester.pump();
  });
}
