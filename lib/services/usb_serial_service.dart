import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:usb_serial/usb_serial.dart';
import '../utils/app_constants.dart';
import '../utils/modbus_utils.dart';

/// Callback signatures
typedef OnPacketReceived = void Function(Uint8List packet);
typedef OnUsbConnectionChanged = void Function(bool isConnected);
typedef OnUsbStatusChanged = void Function(UsbConnectionStatus status);

enum UsbConnectionStatus {
  disconnected,
  requestingPermission,
  permissionDenied,
  connecting,
  connected,
  connectionFailed,
}

class UsbSerialService {
  UsbPort? _port;
  StreamSubscription<Uint8List>? _subscription;
  StreamSubscription<UsbEvent>? _usbEventSubscription;

  final List<int> _incomingBuffer = [];
  bool _isConnected = false;
  UsbConnectionStatus _status = UsbConnectionStatus.disconnected;

  OnPacketReceived? onPacketReceived;
  OnUsbStatusChanged? onStatusChanged;

  bool get isConnected => _isConnected;
  UsbConnectionStatus get status => _status;

  /// Initializes listening to USB attach/detach events on supported platforms.
  void initialize() {
    if (kIsWeb) return;
    _usbEventSubscription = UsbSerial.usbEventStream?.listen((UsbEvent event) {
      // Re‑check connection on any USB event (attach/detach)
      checkConnection();
    });
    checkConnection();
  }

  /// Checks for CH340 / USB‑Serial devices and attempts connection.
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
        // Already connected – just update status
        _updateStatus(UsbConnectionStatus.connected);
        _setConnected(true);
        return true;
      } else {
        _setConnected(false);
        await disconnect();
        _updateStatus(UsbConnectionStatus.disconnected);
        return false;
      }
    } catch (e) {
      debugPrint('[UsbSerialService] USB detection error: $e');
      _setConnected(false);
      _updateStatus(UsbConnectionStatus.connectionFailed);
      return false;
    }
  }

  Future<bool> _connectToDevice(UsbDevice device) async {
    try {
      _updateStatus(UsbConnectionStatus.connecting);
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
        _updateStatus(UsbConnectionStatus.connected);
        debugPrint('[UsbSerialService] Connected to ${device.productName}');
        return true;
      }
    } catch (e) {
      debugPrint('[UsbSerialService] Error establishing port connection: $e');
    }
    _setConnected(false);
    _updateStatus(UsbConnectionStatus.connectionFailed);
    return false;
  }

  /// Handles incoming byte stream and extracts valid 21‑byte Modbus packets.
  void _handleIncomingChunk(Uint8List chunk) {
    _incomingBuffer.addAll(chunk);
    // Process as many complete packets as possible
    while (_incomingBuffer.length >= ModbusUtils.expectedResponseLength) {
      // Look for the start pattern 0x01 0x03 0x10
      if (_incomingBuffer[0] == 0x01 &&
          _incomingBuffer[1] == 0x03 &&
          _incomingBuffer[2] == 0x10) {
        // Extract a candidate packet
        final candidate = Uint8List.fromList(
          _incomingBuffer.sublist(0, ModbusUtils.expectedResponseLength),
        );
        // Validate with ModbusUtils
        if (ModbusUtils.isValidPacket(candidate)) {
          onPacketReceived?.call(candidate);
        } else {
          debugPrint('[UsbSerialService] Invalid Modbus packet received');
        }
        // Remove processed bytes regardless of validity to avoid stalling
        _incomingBuffer.removeRange(0, ModbusUtils.expectedResponseLength);
      } else {
        // Discard leading byte to re‑synchronise the stream
        _incomingBuffer.removeAt(0);
      }
    }
  }

  /// Sends the standard 8‑byte Modbus read query to the sensor.
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
      // Update higher‑level status as well
      if (connected) {
        _updateStatus(UsbConnectionStatus.connected);
      } else {
        _updateStatus(UsbConnectionStatus.disconnected);
      }
      // Legacy callback retained only for backward compatibility – can be removed later
      // onConnectionChanged?.call(_isConnected);
    }
  }

  void _updateStatus(UsbConnectionStatus newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      onStatusChanged?.call(_status);
    }
  }

  /// Closes the port and releases subscriptions.
  Future<void> disconnect() async {
    await _subscription?.cancel();
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
