import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:usb_serial/usb_serial.dart';
import '../utils/app_constants.dart';
import '../utils/modbus_utils.dart';

/// Callback signatures
typedef OnPacketReceived = void Function(Uint8List packet);
typedef OnUsbConnectionChanged = void Function(bool isConnected);

/// Service responsible for managing hardware USB Serial connection with CH340 / RS485 module.
class UsbSerialService {
  UsbPort? _port;
  StreamSubscription<Uint8List>? _subscription;
  StreamSubscription<UsbEvent>? _usbEventSubscription;

  final List<int> _incomingBuffer = [];
  bool _isConnected = false;

  OnPacketReceived? onPacketReceived;
  OnUsbConnectionChanged? onConnectionChanged;

  bool get isConnected => _isConnected;

  /// Initializes listening to USB attach/detach events on supported platforms.
  void initialize() {
    if (kIsWeb) return;

    _usbEventSubscription = UsbSerial.usbEventStream?.listen((UsbEvent event) {
      checkConnection();
    });
    checkConnection();
  }

  /// Scans for CH340 / USB-Serial devices and attempts connection.
  Future<bool> checkConnection() async {
    if (kIsWeb) return false;

    try {
      final List<UsbDevice> devices = await UsbSerial.listDevices();
      UsbDevice? targetDevice;

      for (var device in devices) {
        if (device.vid == AppConstants.ch340VendorId ||
            (device.productName?.contains('CH340') ?? false)) {
          targetDevice = device;
          break;
        }
      }

      if (targetDevice != null) {
        if (_port == null || !_isConnected) {
          return await _connectToDevice(targetDevice);
        }
        return true;
      } else {
        _setConnected(false);
        await disconnect();
        return false;
      }
    } catch (e) {
      debugPrint('[UsbSerialService] USB detection error: $e');
      _setConnected(false);
      return false;
    }
  }

  Future<bool> _connectToDevice(UsbDevice device) async {
    try {
      _port = await device.create();
      bool opened = await _port?.open() ?? false;
      if (opened) {
        await _port?.setDTR(true);
        await _port?.setRTS(true);
        await _port?.setPortParameters(
          AppConstants.baudRate,
          UsbPort.DATABITS_8,
          UsbPort.STOPBITS_1,
          UsbPort.PARITY_NONE,
        );

        _subscription?.cancel();
        _subscription = _port?.inputStream?.listen((Uint8List data) {
          _handleIncomingChunk(data);
        });

        _setConnected(true);
        debugPrint('[UsbSerialService] Connected to ${device.productName}');
        return true;
      }
    } catch (e) {
      debugPrint('[UsbSerialService] Error establishing port connection: $e');
    }
    _setConnected(false);
    return false;
  }

  /// Handles incoming byte stream and extracts valid 21-byte Modbus packets.
  void _handleIncomingChunk(Uint8List chunk) {
    _incomingBuffer.addAll(chunk);

    while (_incomingBuffer.length >= ModbusUtils.expectedResponseLength) {
      // Find beginning of packet: 0x01, 0x03, 0x10
      if (_incomingBuffer[0] == 0x01 &&
          _incomingBuffer[1] == 0x03 &&
          _incomingBuffer[2] == 0x10) {
        final packet = Uint8List.fromList(
          _incomingBuffer.sublist(0, ModbusUtils.expectedResponseLength),
        );
        _incomingBuffer.removeRange(0, ModbusUtils.expectedResponseLength);

        onPacketReceived?.call(packet);
      } else {
        // Discard invalid leading byte to resynchronize stream
        _incomingBuffer.removeAt(0);
      }
    }
  }

  /// Sends the standard 8-byte Modbus read query to the sensor.
  Future<bool> sendQuery() async {
    if (_port != null && _isConnected) {
      _incomingBuffer.clear();
      await _port?.write(ModbusUtils.queryCommand);
      return true;
    }
    return false;
  }

  void _setConnected(bool connected) {
    if (_isConnected != connected) {
      _isConnected = connected;
      onConnectionChanged?.call(_isConnected);
    }
  }

  /// Closes the port and releases subscriptions.
  Future<void> disconnect() async {
    _subscription?.cancel();
    _subscription = null;
    await _port?.close();
    _port = null;
    _setConnected(false);
  }

  /// Disposes all resources.
  void dispose() {
    _usbEventSubscription?.cancel();
    disconnect();
  }
}
