import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:usb_serial/usb_serial.dart';

import '../utils/app_constants.dart';
import '../utils/modbus_utils.dart';

typedef OnPacketReceived = void Function(Uint8List packet);
typedef OnModbusQueryFailed = void Function();
typedef OnUsbStatusChanged = void Function(UsbConnectionStatus status);

enum UsbConnectionStatus {
  disconnected,
  requestingPermission,
  permissionDenied,
  connecting,
  initializing,
  ready,
  connectionFailed,
}

/// Owns one CH340 USB session, including Android permission and warm-up state.
class UsbSerialService {
  static const _initializationDuration = Duration(seconds: 3);
  static const _initializationPollInterval = Duration(milliseconds: 500);

  UsbPort? _port;
  StreamSubscription<Uint8List>? _subscription;
  StreamSubscription<UsbEvent>? _usbEventSubscription;
  Timer? _initializationTimer;
  Timer? _initializationPollTimer;
  Future<bool>? _connectionCheck;

  final List<int> _incomingBuffer = [];
  bool _isConnected = false;
  bool _isInitializing = false;
  bool _isReady = false;
  bool _isQueryInFlight = false;
  bool _receivedValidInitializationFrame = false;
  bool _hasInitialized = false;
  bool _disposed = false;
  int? _activeDeviceId;
  int? _permissionDeniedDeviceId;
  int _session = 0;
  UsbConnectionStatus _status = UsbConnectionStatus.disconnected;

  OnPacketReceived? onPacketReceived;
  OnModbusQueryFailed? onModbusQueryFailed;
  OnUsbStatusChanged? onStatusChanged;

  bool get isConnected => _isConnected;
  bool get isReady => _isReady;
  UsbConnectionStatus get status => _status;

  /// Starts one attach/detach listener and checks an already-attached device.
  void initialize() {
    if (kIsWeb || _disposed || _hasInitialized) return;
    _hasInitialized = true;
    _usbEventSubscription = UsbSerial.usbEventStream?.listen(
      _handleUsbEvent,
      onError: (Object error) {
        debugPrint('[UsbSerialService] USB event stream error: $error');
      },
    );
    checkConnection();
  }

  Future<void> _handleUsbEvent(UsbEvent event) async {
    if (_disposed) return;
    final eventDeviceId = event.device?.deviceId;
    if (event.event == UsbEvent.ACTION_USB_DETACHED &&
        eventDeviceId != null &&
        eventDeviceId == _activeDeviceId) {
      await disconnect();
      return;
    }
    // Android device IDs are valid only until unplugged. A new attach is a new
    // permission session, so a previously denied ID must not block it.
    if (event.event == UsbEvent.ACTION_USB_ATTACHED) {
      _permissionDeniedDeviceId = null;
    }
    await checkConnection();
  }

  /// Finds the CH340 and opens it once. The plugin requests Android USB
  /// permission while [UsbDevice.create] is pending if permission is required.
  Future<bool> checkConnection({bool userInitiatedRetry = false}) {
    if (kIsWeb || _disposed) return Future.value(false);
    if (userInitiatedRetry) _permissionDeniedDeviceId = null;
    return _connectionCheck ??= _checkConnectionInternal().whenComplete(
      () => _connectionCheck = null,
    );
  }

  Future<bool> _checkConnectionInternal() async {
    try {
      final devices = await UsbSerial.listDevices();
      final target = _findCh340(devices);
      if (target == null) {
        await disconnect();
        return false;
      }

      final targetId = target.deviceId;
      if (_activeDeviceId != null && _activeDeviceId != targetId) {
        await disconnect();
      }
      if (_port != null && _isConnected) {
        if (_status == UsbConnectionStatus.connectionFailed) {
          _beginInitialization();
        }
        return true;
      }

      // Remember a denial for this physical connection. This prevents repeated
      // dialogs; disconnect/reconnect or [retry] clears the guard.
      if (_permissionDeniedDeviceId == targetId) {
        _updateStatus(UsbConnectionStatus.permissionDenied);
        return false;
      }
      return await _connectToDevice(target);
    } catch (e) {
      debugPrint('[UsbSerialService] USB detection error: $e');
      _updateStatus(UsbConnectionStatus.connectionFailed);
      return false;
    }
  }

  UsbDevice? _findCh340(List<UsbDevice> devices) {
    for (final device in devices) {
      if (device.vid == AppConstants.ch340VendorId ||
          (device.productName?.toUpperCase().contains('CH340') ?? false)) {
        return device;
      }
    }
    return null;
  }

  Future<bool> _connectToDevice(UsbDevice device) async {
    _updateStatus(UsbConnectionStatus.requestingPermission);
    try {
      // usb_serial maps UsbManager.requestPermission into create(). Keep this
      // call single-flight through [_connectionCheck].
      final port = await device.create(UsbSerial.CH34x);
      if (port == null) {
        _permissionDeniedDeviceId = device.deviceId;
        _updateStatus(UsbConnectionStatus.permissionDenied);
        return false;
      }

      _updateStatus(UsbConnectionStatus.connecting);
      final opened = await port.open();
      if (!opened) {
        await port.close();
        _updateStatus(UsbConnectionStatus.connectionFailed);
        return false;
      }

      _port = port;
      _activeDeviceId = device.deviceId;
      await _port!.setDTR(true);
      await _port!.setRTS(true);
      await _port!.setPortParameters(
        AppConstants.baudRate,
        UsbPort.DATABITS_8,
        UsbPort.STOPBITS_1,
        UsbPort.PARITY_NONE,
      );
      await _subscription?.cancel();
      _subscription = _port!.inputStream?.listen(
        _handleIncomingChunk,
        onError: (Object error) {
          debugPrint('[UsbSerialService] USB input stream error: $error');
          _failSession();
        },
      );
      _isConnected = true;
      _beginInitialization();
      debugPrint('[UsbSerialService] Connected to ${device.productName}.');
      return true;
    } catch (e) {
      debugPrint('[UsbSerialService] Connection/permission error: $e');
      if (e.toString().toLowerCase().contains('permission')) {
        _permissionDeniedDeviceId = device.deviceId;
        _updateStatus(UsbConnectionStatus.permissionDenied);
      } else {
        _updateStatus(UsbConnectionStatus.connectionFailed);
      }
      await disconnect(preserveStatus: true);
      return false;
    }
  }

  /// Warm-up runs for three seconds. Responses are validated then discarded;
  /// READY requires at least one valid Modbus frame from this connection session.
  void _beginInitialization() {
    if (_port == null || !_isConnected || _isInitializing || _disposed) return;
    final session = ++_session;
    _isReady = false;
    _isInitializing = true;
    _receivedValidInitializationFrame = false;
    _incomingBuffer.clear();
    _updateStatus(UsbConnectionStatus.initializing);

    void poll() {
      if (_session == session && _isInitializing) {
        sendQuery(allowDuringInitialization: true);
      }
    }

    poll();
    _initializationPollTimer?.cancel();
    _initializationPollTimer = Timer.periodic(_initializationPollInterval, (_) {
      poll();
    });
    _initializationTimer?.cancel();
    _initializationTimer = Timer(_initializationDuration, () {
      if (_disposed || _session != session || !_isInitializing) return;
      _initializationPollTimer?.cancel();
      _initializationPollTimer = null;
      _isInitializing = false;
      if (_receivedValidInitializationFrame) {
        _isReady = true;
        _updateStatus(UsbConnectionStatus.ready);
      } else {
        _updateStatus(UsbConnectionStatus.connectionFailed);
      }
    });
  }

  void _handleIncomingChunk(Uint8List chunk) {
    _incomingBuffer.addAll(chunk);
    while (_incomingBuffer.length >= ModbusUtils.expectedResponseLength) {
      if (_incomingBuffer[0] == 0x01 &&
          _incomingBuffer[1] == 0x03 &&
          _incomingBuffer[2] == 0x10) {
        final candidate = Uint8List.fromList(
          _incomingBuffer.sublist(0, ModbusUtils.expectedResponseLength),
        );
        _incomingBuffer.removeRange(0, ModbusUtils.expectedResponseLength);
        if (!ModbusUtils.isValidPacket(candidate)) {
          debugPrint('[UsbSerialService] Invalid Modbus packet received.');
          _isQueryInFlight = false;
          onModbusQueryFailed?.call();
          continue;
        }
        _isQueryInFlight = false;
        if (_isInitializing) {
          _receivedValidInitializationFrame = true;
          continue;
        }
        if (_isReady) onPacketReceived?.call(candidate);
      } else {
        _incomingBuffer.removeAt(0);
      }
    }
  }

  /// Sends the unchanged Modbus request only when the session can accept it.
  Future<bool> sendQuery({bool allowDuringInitialization = false}) async {
    if (_port == null || !_isConnected || _isQueryInFlight) return false;
    if (!_isReady && !(allowDuringInitialization && _isInitializing)) {
      return false;
    }
    try {
      _isQueryInFlight = true;
      _incomingBuffer.clear();
      await _port!.write(ModbusUtils.queryCommand);
      // There is no transaction callback in usb_serial. Release a silent query
      // so the next warm-up poll or explicit read can proceed.
      Timer(const Duration(milliseconds: 700), () {
        if (!_isQueryInFlight) return;
        _isQueryInFlight = false;
        onModbusQueryFailed?.call();
      });
      return true;
    } catch (e) {
      _isQueryInFlight = false;
      debugPrint('[UsbSerialService] Modbus write failed: $e');
      _failSession();
      return false;
    }
  }

  /// Explicit retry after denial or initialization failure.
  Future<bool> retry() async {
    _permissionDeniedDeviceId = null;
    if (_port != null && _isConnected) {
      _beginInitialization();
      return true;
    }
    return checkConnection(userInitiatedRetry: true);
  }

  void _failSession() {
    _isReady = false;
    _isInitializing = false;
    _initializationTimer?.cancel();
    _initializationPollTimer?.cancel();
    _updateStatus(UsbConnectionStatus.connectionFailed);
  }

  Future<void> disconnect({bool preserveStatus = false}) async {
    ++_session;
    _initializationTimer?.cancel();
    _initializationTimer = null;
    _initializationPollTimer?.cancel();
    _initializationPollTimer = null;
    _isInitializing = false;
    _isReady = false;
    _isQueryInFlight = false;
    _receivedValidInitializationFrame = false;
    _incomingBuffer.clear();
    await _subscription?.cancel();
    _subscription = null;
    await _port?.close();
    _port = null;
    _activeDeviceId = null;
    _isConnected = false;
    if (!preserveStatus) _updateStatus(UsbConnectionStatus.disconnected);
  }

  void _updateStatus(UsbConnectionStatus newStatus) {
    if (_status == newStatus) return;
    _status = newStatus;
    onStatusChanged?.call(newStatus);
  }

  void dispose() {
    _disposed = true;
    _usbEventSubscription?.cancel();
    _usbEventSubscription = null;
    disconnect();
  }
}
