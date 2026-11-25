// Dashboard screen โ€” responsive for Samsung Galaxy Tab A9
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../models/soil_measurement.dart';
import '../services/device_identity_service.dart';
import '../services/gps_service.dart';
import '../services/home_assistant_service.dart';
import '../services/local_storage_service.dart';
import '../services/map_pin_visibility.dart';
import '../services/measurement_name_history_service.dart';
import '../services/measurement_engine.dart';
import '../services/usb_serial_service.dart';
import '../utils/app_constants.dart';
import '../utils/app_fonts.dart';
import '../utils/app_language.dart';
import '../utils/measurement_map_utils.dart';
import '../utils/measurement_name.dart';
import '../widgets/data_hub_settings_dialog.dart';
import '../widgets/export_dialog.dart';
import '../widgets/local_history_sheet.dart';
import '../widgets/measurement_group_popup.dart';
import '../widgets/non_network_tile_provider.dart';
import '../widgets/sensor_card.dart';

/// Main Dashboard Screen displaying realtime metrics, hardware state, and controls.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.dataHubService});

  final HomeAssistantService? dataHubService;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const _portraitStartDiameter = 88.0;
  static const _phonePortraitStartRadius = 60.0;
  static const _sensorGridSpacing = 6.0;
  static const _uploadDelay = Duration(seconds: 7);
  static const _uploadRetryDelay = Duration(seconds: 30);
  static const _networkEvents = EventChannel('com.soil.sensor.soil_app/network');

  // ----- Service instances -----
  final LocalStorageService _storageService = LocalStorageService();
  final UsbSerialService _usbService = UsbSerialService();
  AppLifecycleListener? _usbLifecycle;
  final GpsService _gpsService = GpsService();
  late final _homeAssistantService =
      widget.dataHubService ?? HomeAssistantService();
  final MeasurementNameHistoryService _nameHistoryService =
      MeasurementNameHistoryService();
  final DeviceIdentityService _deviceIdentityService = DeviceIdentityService();
  final MeasurementEngine _measurementEngine = MeasurementEngine();
  final TextEditingController _measurementNameController =
      TextEditingController();
  final FocusNode _measurementNameFocusNode = FocusNode();
  final MenuController _measurementNameMenu = MenuController();
  bool get _isSettingsName =>
      _measurementNameController.text.trim() == dataHubSettingsCommand;

  // ----- State variables -----
  final _logs = ValueNotifier<List<SoilMeasurement>>([]);
  List<SoilMeasurement> get _localLogs => _logs.value;
  Future<void> _logWrites = Future.value();
  final _activeUploads = <String, Future<DataHubUploadResult>>{};
  final _acceptedUploads = <String>{};
  Future<String>? _pendingRetry;
  bool _manualUploadRequested = false;
  final _autoUploadMode = ValueNotifier<bool?>(null);
  bool get _autoUploadEnabled => _autoUploadMode.value ?? false;
  final _hasInternet = ValueNotifier(
    kIsWeb || defaultTargetPlatform != TargetPlatform.android,
  );
  int? _networkHandle;
  int _autoUploadGeneration = 0;
  Timer? _autoUploadTimer;
  StreamSubscription<Object?>? _networkSubscription;
  int _seenLogCount = 0;
  SoilMeasurement _currentData = SoilMeasurement.initial();
  UsbConnectionStatus _usbStatus = UsbConnectionStatus.disconnected;

  // Additional state variables
  bool _isMeasuring = false;
  int _countdownSeconds = 10;
  Timer? _countdownTimer;
  String? _activeMeasurementName;
  String? _measurementNameError;
  List<String> _measurementNameHistory = [];
  DeviceIdentity? _deviceIdentity;
  Timer? _nextSampleTimer;
  GpsLocationData? _currentGpsLocation;
  StreamSubscription<Position>? _gpsPositionSubscription;

  @override
  void initState() {
    super.initState();
    _initServices();
  }

  Future<void> _initServices() async {
    _loadDeviceIdentity();
    await MapPinVisibility.instance.load();
    // Load cached logs
    final logs = await _storageService.loadMeasurements();
    List<String> names = [];
    try {
      names = await _nameHistoryService.load(
        logs.map((record) => record.measurementName),
      );
    } catch (error) {
      debugPrint('[DashboardScreen] Name history unavailable: $error');
    }
    if (!mounted) return;
    setState(() {
      _logs.value = logs;
      _measurementNameHistory = names;
      if (_localLogs.isNotEmpty) {
        _currentData = _localLogs.first;
      }
    });

    // USB status callbacks
    _usbService.onStatusChanged = (status) {
      if (!mounted) return;
      setState(() => _usbStatus = status);
      if (_measurementEngine.isCollecting &&
          (status == UsbConnectionStatus.disconnected ||
              status == UsbConnectionStatus.permissionDenied ||
              status == UsbConnectionStatus.connectionFailed)) {
        _stopMeasurement();
      }
    };

    // Packet callback โ€“ only called after Modbus validation in USB service
    _usbService.onPacketReceived = _handleSamplePacket;
    _usbService.onModbusQueryFailed = () {
      if (_measurementEngine.isCollecting) _scheduleNextSample();
    };

    // Initialise USB detection and GPS
    _usbService.initialize();
    _usbLifecycle = AppLifecycleListener(
      onResume: () => unawaited(_usbService.checkConnection()),
    );
    _startGpsTracking();
    unawaited(_initAutoUpload());
  }

  Future<void> _initAutoUpload() async {
    var enabled = false;
    try {
      final settings = await _homeAssistantService.loadSettings();
      enabled = settings.autoUpload;
    } catch (_) {
      debugPrint('[Data Hub] Could not load automatic upload settings.');
    }
    if (!mounted) return;
    _autoUploadMode.value = enabled;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    _networkSubscription = _networkEvents.receiveBroadcastStream().listen(
      (event) {
        final status = event as Map<Object?, Object?>;
        _updateUploadNetwork(
          status['network'] as int?,
          status['hasInternet'] == true,
        );
      },
      onError: (Object _) => _updateUploadNetwork(null, false),
    );
  }

  Future<bool> _setAutoUpload(bool enabled) async {
    try {
      if (!await _homeAssistantService.saveAutoUpload(enabled)) return false;
    } catch (_) {
      return false;
    }
    if (mounted) {
      _autoUploadMode.value = enabled;
      _resetAutoUpload();
    }
    return true;
  }

  void _updateUploadNetwork(int? networkHandle, bool hasInternet) {
    if (!mounted) return;
    _hasInternet.value = hasInternet;
    if (_networkHandle == networkHandle) return;
    _networkHandle = networkHandle;
    _resetAutoUpload();
  }

  void _resetAutoUpload() {
    _autoUploadGeneration++;
    _autoUploadTimer?.cancel();
    _autoUploadTimer = null;
    _scheduleAutoUpload();
  }

  bool get _canAutoUpload =>
      mounted && _autoUploadEnabled && _networkHandle != null;

  void _scheduleAutoUpload([Duration delay = _uploadDelay]) {
    if (!_canAutoUpload ||
        _autoUploadTimer != null ||
        !_localLogs.any((record) => !record.isSyncedToCloud)) {
      return;
    }
    final generation = _autoUploadGeneration;
    _autoUploadTimer = Timer(delay, () async {
      // Share the existing upload queue if a manual or prior run is finishing.
      await _pendingRetry;
      if (!_canAutoUpload || generation != _autoUploadGeneration) return;
      _autoUploadTimer = null;
      await _startPendingUploads(generation);
    });
  }

  Future<void> _rememberMeasurementName(String name) async {
    try {
      final names = await _queueLogWrite(
        () => _nameHistoryService.remember(name),
      );
      if (mounted) setState(() => _measurementNameHistory = names);
    } catch (error) {
      debugPrint('[DashboardScreen] Could not save name history: $error');
    }
  }

  Future<void> _removeMeasurementName(String name) async {
    try {
      final names = await _queueLogWrite(
        () => _nameHistoryService.remove(name),
      );
      if (mounted) {
        if (names.isEmpty) _measurementNameMenu.close();
        setState(() => _measurementNameHistory = names);
      }
    } catch (error) {
      debugPrint('[DashboardScreen] Could not remove name history: $error');
    }
  }

  Future<void> _startGpsTracking() async {
    final enabled = await _gpsService.isLocationServiceEnabled();
    if (!enabled || !await _gpsService.requestPermission()) return;
    final loc = await _gpsService.getCurrentLocation();
    if (!mounted) return;
    if (loc != null) setState(() => _currentGpsLocation = loc);
    _gpsPositionSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 1,
          ),
        ).listen((position) {
          if (!mounted) return;
          setState(
            () => _currentGpsLocation = GpsLocationData(
              latitude: position.latitude,
              longitude: position.longitude,
              accuracy: position.accuracy,
              timestamp: position.timestamp,
            ),
          );
        }, onError: (Object error) {
          debugPrint('[DashboardScreen] GPS tracking unavailable: $error');
        });
  }

  @override
  void dispose() {
    _measurementNameController.dispose();
    _measurementNameFocusNode.dispose();
    _nextSampleTimer?.cancel();
    _countdownTimer?.cancel();
    _autoUploadTimer?.cancel();
    _networkSubscription?.cancel();
    _measurementEngine.dispose();
    _gpsPositionSubscription?.cancel();
    _usbLifecycle?.dispose();
    _usbService.dispose();
    if (widget.dataHubService == null) _homeAssistantService.dispose();
    _logs.dispose();
    _autoUploadMode.dispose();
    _hasInternet.dispose();
    super.dispose();
  }

  Future<void> _loadDeviceIdentity() async {
    try {
      final identity = await _deviceIdentityService.getIdentity();
      if (mounted) setState(() => _deviceIdentity = identity);
    } catch (error) {
      debugPrint('[DashboardScreen] Device identity unavailable: $error');
    }
  }

  void _handleSamplePacket(Uint8List packet) {
    final samples = _measurementEngine.addSample(
      SoilSample.fromRawBytes(packet),
    );
    if (samples == null) {
      if (_measurementEngine.isCollecting) _scheduleNextSample();
      return;
    }
    _completeMeasurement(samples);
  }

  Future<void> _completeMeasurement(List<SoilSample> samples) async {
    _nextSampleTimer?.cancel();
    _countdownTimer?.cancel();
    try {
      await _finishMeasurement(samples);
    } catch (error) {
      debugPrint('[DashboardScreen] Could not complete measurement: $error');
      if (mounted) {
        _stopMeasurement(
          context.tr(
            'บันทึกการวัดไม่สำเร็จ',
            'Could not complete the measurement',
          ),
        );
      }
    }
  }

  Future<void> _finishMeasurement(List<SoilSample> samples) async {
    final timestamp = _measurementEngine.completedAt;
    final name = _activeMeasurementName ?? '';
    final identity =
        _deviceIdentity ?? await _deviceIdentityService.getIdentity();
    final gps = await _gpsService.getCurrentLocation();
    final measurement = SoilMeasurement.fromAveragedSamples(
      id: 'MEAS-${timestamp.millisecondsSinceEpoch}',
      rawSamples: samples,
      timestamp: timestamp,
      deviceId: identity.id,
      deviceMetadata: identity.metadata,
      measurementName: name,
      latitude: gps?.latitude,
      longitude: gps?.longitude,
      gpsAccuracy: gps?.accuracy,
      locationTimestamp: gps?.timestamp,
    );
    if (mounted) {
      setState(() {
        _isMeasuring = false;
        _countdownSeconds = 10;
        _activeMeasurementName = null;
        _currentData = measurement;
        final current = _currentGpsLocation;
        if (gps != null &&
            (current == null || !gps.timestamp.isBefore(current.timestamp))) {
          _currentGpsLocation = gps;
        }
      });
    }
    await _processNewMeasurement(measurement);
  }

  void _scheduleNextSample() {
    _nextSampleTimer?.cancel();
    // Pace queries over ~10 seconds so 10 samples complete smoothly with countdown
    _nextSampleTimer = Timer(
      const Duration(milliseconds: 900),
      _requestNextSample,
    );
  }

  Future<void> _requestNextSample() async {
    if (!_measurementEngine.isCollecting ||
        _usbStatus != UsbConnectionStatus.ready) {
      return;
    }
    final sent = await _usbService.sendQuery();
    if (!sent && _measurementEngine.isCollecting) _scheduleNextSample();
  }

  void _stopMeasurement([String? message]) {
    if (!_measurementEngine.isCollecting && !_isMeasuring) return;
    _nextSampleTimer?.cancel();
    _countdownTimer?.cancel();
    _measurementEngine.cancel();
    if (mounted) {
      setState(() {
        _isMeasuring = false;
        _countdownSeconds = 10;
        _activeMeasurementName = null;
      });
      if (message != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  // ---------- Data handling ----------
  Future<T> _queueLogWrite<T>(Future<T> Function() write) {
    final next = _logWrites.then((_) => write());
    _logWrites = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  void _replaceLocalLogs(List<SoilMeasurement> records) {
    if (mounted) setState(() => _logs.value = records);
  }

  Future<void> _processNewMeasurement(SoilMeasurement measurement) async {
    try {
      await _queueLogWrite(() async {
        if (!mounted) return;
        _replaceLocalLogs(
          await _storageService.saveMeasurement(measurement, _localLogs),
        );
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr(
                'บันทึกข้อมูลลงเครื่องไม่สำเร็จ',
                'Could not save the measurement on this device',
              ),
            ),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    _scheduleAutoUpload();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _autoUploadEnabled
              ? context.tr(
                  'บันทึกลงเครื่องแล้ว รอส่งไปยัง Data Hub',
                  'Saved on this device. Waiting to send to Data Hub.',
                )
              : context.tr(
                  'บันทึกลงเครื่องแล้ว กดส่งข้อมูลได้จากหน้า Log',
                  'Saved on this device. Send it from Local Logs.',
                ),
        ),
      ),
    );
  }

  Future<DataHubUploadResult> _uploadSavedMeasurement(
    SoilMeasurement measurement,
  ) {
    if (measurement.isSyncedToCloud) {
      return Future.value(DataHubUploadResult.uploaded);
    }
    return _activeUploads.putIfAbsent(
      measurement.id,
      () => _sendAndMarkSynced(measurement).whenComplete(() {
        // Remove the entry without returning the Future being completed.
        _activeUploads.remove(measurement.id);
      }),
    );
  }

  Future<DataHubUploadResult> _sendAndMarkSynced(
    SoilMeasurement measurement,
  ) async {
    final result = _acceptedUploads.contains(measurement.id)
        ? DataHubUploadResult.uploaded
        : await _homeAssistantService.uploadMeasurement(measurement);
    if (result != DataHubUploadResult.uploaded || !mounted) return result;
    _acceptedUploads.add(measurement.id);
    try {
      await _queueLogWrite(() async {
        if (!mounted) return;
        final current = _localLogs;
        if (!current.any((record) => record.id == measurement.id)) return;
        final updated = await _storageService.updateSyncStatus(
          measurement.id,
          true,
          current,
        );
        measurement.isSyncedToCloud = true;
        _replaceLocalLogs(updated);
      });
    } catch (_) {
      return DataHubUploadResult.statusNotSaved;
    }
    _acceptedUploads.remove(measurement.id);
    return result;
  }

  Future<String> _retryPendingUploads() {
    if (!_hasInternet.value) {
      return Future.value(
        context.tr('ยังไม่ได้เชื่อมต่ออินเทอร์เน็ต', 'No internet connection'),
      );
    }
    _manualUploadRequested = true;
    return _startPendingUploads();
  }

  Future<String> _startPendingUploads([int? generation]) =>
      _pendingRetry ??= _sendPendingLogs(generation).whenComplete(() {
        _pendingRetry = null;
        _manualUploadRequested = false;
      });

  Future<String> _sendPendingLogs(int? generation) async {
    final pending = _localLogs.reversed
        .where((record) => !record.isSyncedToCloud)
        .toList();
    if (pending.isEmpty) {
      return context.tr('ไม่มีรายการค้างส่ง', 'No pending measurements');
    }
    var sent = 0;
    for (final record in pending) {
      if (!mounted) return '';
      if (_manualUploadRequested && !_hasInternet.value) {
        return context.tr(
          'ส่งสำเร็จ $sent รายการ อินเทอร์เน็ตขาดการเชื่อมต่อ',
          'Sent $sent. The internet connection was lost.',
        );
      }
      if (!_manualUploadRequested &&
          (!_canAutoUpload || generation != _autoUploadGeneration)) {
        break;
      }
      final result = await _uploadSavedMeasurement(record);
      if (!mounted) return '';
      switch (result) {
        case DataHubUploadResult.uploaded:
          sent++;
        case DataHubUploadResult.notConfigured:
          return context.tr(
            'ส่งสำเร็จ $sent รายการ กรุณาตั้งค่า Data Hub แล้วลองอีกครั้ง',
            'Sent $sent. Set up Data Hub and try again.',
          );
        case DataHubUploadResult.rejected:
          return context.tr(
            'ส่งสำเร็จ $sent รายการ Data Hub ปฏิเสธรายการถัดไป กรุณาตรวจการตั้งค่า',
            'Sent $sent. Data Hub rejected the next item. Check settings.',
          );
        case DataHubUploadResult.failed:
          if (generation == _autoUploadGeneration) {
            _scheduleAutoUpload(_uploadRetryDelay);
          }
          return context.tr(
            'ส่งสำเร็จ $sent รายการ รายการที่เหลือยังค้างส่ง ลองอีกครั้งเมื่อเชื่อมต่อ Data Hub',
            'Sent $sent. Retry the remaining items when Data Hub is available.',
          );
        case DataHubUploadResult.statusNotSaved:
          return context.tr(
            'Data Hub รับรายการล่าสุดแล้ว แต่บันทึกสถานะลงเครื่องไม่สำเร็จ',
            'Data Hub received the last item, but the sync status could not be saved.',
          );
      }
    }
    return context.tr(
      'ส่งข้อมูลไปยัง Data Hub แล้ว $sent รายการ',
      'Sent $sent items to Data Hub',
    );
  }

  Future<void> _openDataHubSettings() async {
    final DataHubSettings settings;
    try {
      settings = await _homeAssistantService.loadSettings();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr(
                'โหลดการตั้งค่า Data Hub ไม่สำเร็จ',
                'Could not load Data Hub settings',
              ),
            ),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DataHubSettingsDialog(
        service: _homeAssistantService,
        settings: settings,
      ),
    );
    if (mounted && saved == true) _resetAutoUpload();
  }

  // ---------- Read flow ----------
  Future<void> _submitSettingsName() async {
    _measurementNameMenu.close();
    _measurementNameFocusNode.unfocus();
    _measurementNameController.clear();
    setState(() => _measurementNameError = null);
    await _openDataHubSettings();
  }

  Future<void> _triggerRead() async {
    if (_isMeasuring) return;
    final name = normalizedMeasurementName(_measurementNameController.text);
    if (name == dataHubSettingsCommand) {
      await _submitSettingsName();
      return;
    }
    if (_usbStatus != UsbConnectionStatus.ready) {
      _measurementNameMenu.close();
      _measurementNameFocusNode.unfocus();
      final retry = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(context.tr('การเชื่อมต่อเซนเซอร์', 'Sensor connection')),
          scrollable: true,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                switch (_usbStatus) {
                  UsbConnectionStatus.permissionDenied => context.tr(
                    'กรุณาอนุญาตให้แอปเข้าถึงเซนเซอร์ USB แล้วลองใหม่',
                    'Allow access to the USB sensor and try again.',
                  ),
                  UsbConnectionStatus.connectionFailed => context.tr(
                    'เซนเซอร์ไม่ตอบสนอง กรุณาตรวจสายแล้วลองใหม่',
                    'The sensor did not respond. Check the cable and try again.',
                  ),
                  UsbConnectionStatus.requestingPermission => context.tr(
                    'กำลังรอการอนุญาต USB',
                    'Waiting for USB permission.',
                  ),
                  UsbConnectionStatus.connecting ||
                  UsbConnectionStatus.initializing ||
                  UsbConnectionStatus.ready => context.tr(
                    'กำลังเตรียมเซนเซอร์ กรุณารอสักครู่',
                    'Preparing the sensor. Please wait.',
                  ),
                  UsbConnectionStatus.disconnected => context.tr(
                    'ยังไม่ได้เชื่อมต่อเซนเซอร์ ตรวจสายหรือเปิด OTG ในการตั้งค่ามือถือ',
                    'Sensor not detected. Check the OTG adapter or enable OTG in settings.',
                  ),
                },
              ),
              const SizedBox(height: 12),
              Text(
                AppConstants.sensorConnectionType,
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(context.tr('ตกลง', 'OK')),
            ),
            if (_usbStatus == UsbConnectionStatus.disconnected ||
                _usbStatus == UsbConnectionStatus.permissionDenied ||
                _usbStatus == UsbConnectionStatus.connectionFailed)
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(context.tr('ลองเชื่อมต่อใหม่', 'Retry connection')),
              ),
          ],
        ),
      );
      if (retry == true && mounted) await _usbService.retry();
      return;
    }
    if (name == null) {
      setState(
        () => _measurementNameError = context.tr(
          'กรุณาระบุชื่อการวัด',
          'Enter a measurement name',
        ),
      );
      return;
    }

    setState(() {
      _measurementNameController.text = name;
      _measurementNameError = null;
      _activeMeasurementName = name;
      _isMeasuring = true;
      _countdownSeconds = 10;
    });
    _measurementNameMenu.close();
    _measurementNameFocusNode.unfocus();
    unawaited(_rememberMeasurementName(name));

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_countdownSeconds > 1) {
          _countdownSeconds--;
        }
      });
    });

    _measurementEngine.start(
      onTimeout: () => _stopMeasurement(
        context.tr(
          'หมดเวลาการตรวจวัดก่อนได้รับค่าครบ 10 ค่า',
          'Measurement timed out before receiving 10 readings',
        ),
      ),
    );
    await _requestNextSample();
  }

  // ---------- Local Logs Modal ----------
  void _openLocalLogsView() {
    _measurementNameFocusNode.unfocus();
    setState(() => _seenLogCount = _localLogs.length);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: DraggableScrollableSheet(
          expand: false,
          minChildSize: MediaQuery.orientationOf(ctx) == Orientation.landscape
              ? 0.45
              : 0.25,
          initialChildSize:
              MediaQuery.orientationOf(ctx) == Orientation.landscape
              ? 0.84
              : 0.65,
          maxChildSize: 0.92,
          builder: (_, scrollController) => SafeArea(
            top: false,
            child: ValueListenableBuilder<List<SoilMeasurement>>(
              valueListenable: _logs,
              builder: (_, records, _) => LocalHistorySheet(
                records: records,
                scrollController: scrollController,
                autoUploadMode: _autoUploadMode,
                hasInternet: _hasInternet,
                onAutoUploadChanged: _setAutoUpload,
                onRetryPending: _retryPendingUploads,
                onClear: () async {
                  if (_pendingRetry != null) return;
                  final confirmed = await showDialog<bool>(
                    context: ctx,
                    builder: (dialogContext) => AlertDialog(
                      scrollable: true,
                      title: Text(
                        context.tr(
                          'ล้างประวัติทั้งหมดหรือไม่',
                          'Clear all history?',
                        ),
                      ),
                      content: Text(
                        context.tr(
                          'ระบบจะลบบันทึกที่เก็บไว้ในเครื่องนี้',
                          'This deletes saved records on this device only.',
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: Text(context.tr('ยกเลิก', 'Cancel')),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: Text(context.tr('ลบ', 'Delete')),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true ||
                      !ctx.mounted ||
                      _pendingRetry != null) {
                    return;
                  }
                  await _queueLogWrite(() async {
                    if (!mounted || _pendingRetry != null) return;
                    if (await _storageService.clearHistory() && mounted) {
                      _seenLogCount = 0;
                      _acceptedUploads.clear();
                      _replaceLocalLogs([]);
                    }
                  });
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------- Export Raw Log Modal ----------
  void _openExportView() {
    _measurementNameFocusNode.unfocus();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => ExportDialog(records: _localLogs),
    );
  }

  // ---------- GPS info bar (compact) ----------
  Widget _buildGpsBar() {
    if (_currentGpsLocation == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.lightBlueTint,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.location_on_outlined,
            size: 13,
            color: AppColors.softBlue,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              'GPS: ${_currentGpsLocation!.latitude.toStringAsFixed(5)}, ${_currentGpsLocation!.longitude.toStringAsFixed(5)} (+-${_currentGpsLocation!.accuracy.toStringAsFixed(0)}m)',
              style: AppFonts.manrope.copyWith(
                fontSize: 10,
                color: AppColors.statusDarkText,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.green,
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Map widget (one marker per measurement name) ----------
  Widget _buildMap() => ListenableBuilder(
    listenable: MapPinVisibility.instance,
    builder: (context, _) => _buildMapContent(),
  );

  Widget _buildMapContent() {
    final center = (_currentGpsLocation != null)
        ? LatLng(_currentGpsLocation!.latitude, _currentGpsLocation!.longitude)
        : const LatLng(13.75, 100.52); // Bangkok default
    final groups = measurementMarkerGroups(
      _localLogs,
      hiddenMeasurementIds: MapPinVisibility.instance.value,
    );
    final markerPoints = measurementGroupMarkerPoints(groups);
    final savedMarkers = groups.map((group) {
      return Marker(
        point: markerPoints[group.key]!,
        width: 112,
        height: 64,
        child: MeasurementGroupMarkerLabel(
          group: group,
          onMarkerTap: (anchorContext) => showMeasurementGroupPopup(
            context: context,
            anchorContext: anchorContext,
            group: group,
          ),
        ),
      );
    }).toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: FlutterMap(
        options: MapOptions(
          initialCenter: center,
          initialZoom: _currentGpsLocation != null ? 15 : 5,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.soil_app',
            tileProvider: NonNetworkTileProvider(),
          ),
          if (_currentGpsLocation != null)
            MarkerLayer(
              markers: [
                Marker(
                  point: center,
                  width: 32,
                  height: 32,
                  child: const Icon(
                    Icons.location_pin,
                    color: Colors.red,
                    size: 32,
                  ),
                ),
              ],
            ),
          MarkerLayer(markers: savedMarkers),
        ],
      ),
    );
  }

  // ---------- Action buttons ----------
  Widget _buildMeasurementNameInput({bool compact = false, bool phone = false}) {
    return LayoutBuilder(
      builder: (context, constraints) => MenuAnchor(
        controller: _measurementNameMenu,
        style: const MenuStyle(
          padding: WidgetStatePropertyAll(EdgeInsets.zero),
          maximumSize: WidgetStatePropertyAll(Size(double.infinity, 208)),
        ),
        menuChildren: [
          for (final name in _measurementNameHistory)
            TextFieldTapRegion(
              child: SizedBox(
                width: constraints.maxWidth,
                child: ListTile(
                  dense: true,
                  title: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: context.tr(
                      'ลบชื่อ $name จากประวัติ',
                      'Remove $name from name history',
                    ),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => _removeMeasurementName(name),
                  ),
                  onTap: () {
                    _measurementNameController.value = TextEditingValue(
                      text: name,
                      selection: TextSelection.collapsed(offset: name.length),
                    );
                    setState(() => _measurementNameError = null);
                    _measurementNameMenu.close();
                    _measurementNameFocusNode.unfocus();
                  },
                ),
              ),
            ),
        ],
        child: TextField(
          controller: _measurementNameController,
          focusNode: _measurementNameFocusNode,
          enabled: !_isMeasuring,
          style: phone ? const TextStyle(fontSize: 14) : null,
          textInputAction: TextInputAction.done,
          maxLength: 80,
          onTap: () {
            if (_measurementNameHistory.isNotEmpty &&
                !_measurementNameMenu.isOpen) {
              _measurementNameMenu.open();
            }
          },
          onChanged: (_) {
            _measurementNameMenu.close();
            setState(() => _measurementNameError = null);
          },
          onSubmitted: (_) {
            _measurementNameMenu.close();
            if (_isSettingsName) _submitSettingsName();
          },
          decoration: InputDecoration(
            labelText: context.tr('ชื่อการวัด', 'Measurement name'),
            hintText: context.tr('เช่น แปลง A / Field A', 'e.g. Field A'),
            errorText: _measurementNameError,
            counterText: '',
            isDense: compact,
            contentPadding: phone
                ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
                : null,
            prefixIconConstraints: phone
                ? const BoxConstraints(minWidth: 34, minHeight: 40)
                : null,
            prefixIcon: Icon(
              Icons.label_outline_rounded,
              size: phone ? 17 : null,
            ),
            suffixIcon: _measurementNameHistory.isEmpty
                ? null
                : IconButton(
                    tooltip: context.tr(
                      'ประวัติชื่อการวัด',
                      'Measurement name history',
                    ),
                    icon: Icon(Icons.arrow_drop_down, size: phone ? 18 : null),
                    constraints: phone
                        ? const BoxConstraints(minWidth: 44, minHeight: 40)
                        : null,
                    onPressed: _isMeasuring
                        ? null
                        : () {
                            if (_measurementNameMenu.isOpen) {
                              _measurementNameMenu.close();
                            } else {
                              _measurementNameFocusNode.unfocus();
                              _measurementNameMenu.open();
                            }
                          },
                  ),
            border: const OutlineInputBorder(),
          ),
        ),
      ),
    );
  }

  // ---------- Floating START buttons ----------

  Widget _buildMeasureButtonLabel(
    bool isReady, {
    required double iconSize,
    double fontSize = 11,
  }) {
    final label = isReady
        ? context.tr('กดเพื่อวัดค่า', 'Press\nto measure')
        : context.tr('ยังไม่พร้อม', 'Not Ready');
    final isThai = AppLanguage.of(context)?.isThai ?? true;
    final labelStyle = isThai
        ? const TextStyle(fontWeight: FontWeight.bold)
        : AppFonts.manropeBold;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.play_arrow_rounded, color: Colors.white, size: iconSize),
        Text(
          label,
          textAlign: TextAlign.center,
          style: labelStyle.copyWith(
            fontSize: fontSize,
            height: 1.1,
            color: Colors.white,
          ),
        ),
      ],
    );
    return fontSize < 11
        ? FittedBox(fit: BoxFit.scaleDown, child: content)
        : content;
  }

  /// Circular START button for portrait mode
  Widget _buildCircleStartButton(double diameter, {required bool phone}) {
    final isReady = _usbStatus == UsbConnectionStatus.ready;
    final bgColor = _isMeasuring
        ? AppColors.appbarBlue
        : isReady
        ? AppColors.softBlue
        : AppColors.disabledStart;

    return GestureDetector(
      onTap: _isMeasuring ? null : _triggerRead,
      child: Container(
        key: const ValueKey('portrait-measure-button'),
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(shape: BoxShape.circle, color: bgColor),
        child: Center(
          child: _isMeasuring
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$_countdownSeconds',
                      style: AppFonts.manropeBold.copyWith(
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                  ],
                )
              : _buildMeasureButtonLabel(
                  isReady,
                  iconSize: phone ? 21 : 30,
                  fontSize: phone ? 9 : 11,
                ),
        ),
      ),
    );
  }

  /// Half-circle START button for landscape mode (bottom center, overlapping map & cards)
  Widget _buildHalfCircleStartButton(double radius, {required bool phone}) {
    final isReady = _usbStatus == UsbConnectionStatus.ready;
    final bgColor = _isMeasuring
        ? AppColors.appbarBlue
        : isReady
        ? AppColors.softBlue
        : AppColors.disabledStart;

    return GestureDetector(
      onTap: _isMeasuring ? null : _triggerRead,
      child: Container(
        key: ValueKey(phone ? 'portrait-measure-button' : 'landscape-measure-button'),
        width: radius * 2,
        height: radius - 2,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
        ),
        child: Align(
          alignment: Alignment.center,
          child: Padding(
            padding: EdgeInsets.only(top: phone ? 4 : 8),
            child: _isMeasuring
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$_countdownSeconds',
                        style: AppFonts.manropeBold.copyWith(
                          fontSize: 20,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  )
                : _buildMeasureButtonLabel(
                    isReady,
                    iconSize: phone ? 19 : 22,
                    fontSize: phone ? 10 : 11,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildLandscapePhoneControl() {
    final isReady = _usbStatus == UsbConnectionStatus.ready;
    final color = _isMeasuring
        ? AppColors.appbarBlue
        : isReady
        ? AppColors.softBlue
        : AppColors.disabledStart;
    return Material(
      key: const ValueKey('landscape-measure-button'),
      color: color,
      borderRadius: BorderRadius.circular(9),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _isMeasuring ? null : _triggerRead,
        child: SizedBox(
          width: 86,
          height: 42,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Center(
              child: _isMeasuring
                  ? Text(
                      '$_countdownSeconds',
                      style: AppFonts.manropeBold.copyWith(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    )
                  : _buildMeasureButtonLabel(isReady, iconSize: 15, fontSize: 9),
            ),
          ),
        ),
      ),
    );
  }

  // ---------- Sensor grid ----------
  Widget _buildSensorGrid({
    required int columns,
    required double aspectRatio,
    bool isPortrait = false,
    bool phone = false,
  }) {
    const portraitStartCutoutRadius = 52.0;
    final hasCutout = isPortrait && !phone;
    final valueFontSize = phone
        ? (isPortrait ? 28.0 : 24.0)
        : (isPortrait ? 38.0 : 34.0);
    return GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      crossAxisSpacing: _sensorGridSpacing,
      mainAxisSpacing: _sensorGridSpacing,
      childAspectRatio: aspectRatio,
      children: [
        SensorCard(
          title: context.tr('ความชื้น', 'Moisture'),
          abbreviation: 'M',
          value: _currentData.moisture.toStringAsFixed(1),
          unit: '%',
          icon: Icons.water_drop_rounded,
          color: AppColors.moistureColor,
          valueFontSize: valueFontSize,
          compact: phone,
        ),
        SensorCard(
          title: context.tr('อุณหภูมิ', 'Temperature'),
          abbreviation: 'T',
          value: _currentData.temperature.toStringAsFixed(2),
          unit: '°C',
          icon: Icons.thermostat_rounded,
          color: AppColors.tempColor,
          valueFontSize: valueFontSize,
          compact: phone,
        ),
        SensorCard(
          title: context.tr('ค่าความเป็นกรด/ด่าง', 'Acidity/alkalinity'),
          abbreviation: 'pH',
          value: _currentData.ph.toStringAsFixed(2),
          unit: '',
          icon: Icons.science_rounded,
          color: AppColors.phColor,
          valueFontSize: valueFontSize,
          compact: phone,
        ),
        SensorCard(
          title: context.tr('ค่าการนำไฟฟ้า', 'Electrical conductivity'),
          abbreviation: 'EC',
          value: '${_currentData.ec}',
          unit: 'µS/cm',
          icon: Icons.bolt_rounded,
          color: AppColors.ecColor,
          valueFontSize: valueFontSize,
          compact: phone,
        ),
        SensorCard(
          title: context.tr('ไนโตรเจน', 'Nitrogen'),
          abbreviation: 'N',
          value: '${_currentData.nitrogen}',
          unit: 'mg/kg',
          icon: Icons.grass_rounded,
          color: AppColors.nitrogenColor,
          cornerCutout: hasCutout
              ? CornerCutout.bottomRight
              : CornerCutout.none,
          cutoutRadius: portraitStartCutoutRadius,
          valueFontSize: valueFontSize,
          compact: phone,
        ),
        SensorCard(
          title: context.tr('ฟอสฟอรัส', 'Phosphorus'),
          abbreviation: 'P',
          value: '${_currentData.phosphorus}',
          unit: 'mg/kg',
          icon: Icons.grain_rounded,
          color: AppColors.phosphorusColor,
          cornerCutout: hasCutout
              ? CornerCutout.bottomLeft
              : CornerCutout.none,
          cutoutRadius: isPortrait ? portraitStartCutoutRadius : 46.0,
          valueFontSize: valueFontSize,
          compact: phone,
        ),
        SensorCard(
          title: context.tr('โพแทสเซียม', 'Potassium'),
          abbreviation: 'K',
          value: '${_currentData.potassium}',
          unit: 'mg/kg',
          icon: Icons.spa_rounded,
          color: AppColors.potassiumColor,
          cornerCutout: hasCutout ? CornerCutout.topRight : CornerCutout.none,
          cutoutRadius: isPortrait ? portraitStartCutoutRadius : 46.0,
          valueFontSize: valueFontSize,
          compact: phone,
        ),
        SensorCard(
          title: context.tr('ความเค็ม', 'Salinity'),
          abbreviation: 'SAL',
          value: '${_currentData.salinity}',
          unit: 'mg/L',
          icon: Icons.waves_rounded,
          color: AppColors.salinityColor,
          cornerCutout: hasCutout ? CornerCutout.topLeft : CornerCutout.none,
          cutoutRadius: isPortrait ? portraitStartCutoutRadius : 46.0,
          valueFontSize: valueFontSize,
          compact: phone,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isPortrait = size.height > size.width;
    final phone = size.shortestSide < 480;
    final body = isPortrait ? _buildPortrait(phone) : _buildLandscape(phone);

    final language = AppLanguage.of(context);
    final dashboard = Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        titleSpacing: 8,
        toolbarHeight: phone ? 44 : 48,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: phone ? 26 : 30,
              height: phone ? 26 : 30,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.all(Radius.circular(6)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset(
                'assets/meta_soil_logo.png',
                fit: BoxFit.contain,
                excludeFromSemantics: true,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                AppConstants.appTitle,
                style: AppFonts.manropeBold.copyWith(
                  fontSize: phone ? 13 : 14,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          if (language != null)
            IconButton(
              tooltip: context.tr('เปลี่ยนเป็นภาษาอังกฤษ', 'Switch to Thai'),
              onPressed: () => language.onToggle(context),
              icon: Text(
                language.isThai ? 'TH' : 'EN',
                style: AppFonts.manropeBold.copyWith(
                  color: Colors.white,
                  fontSize: phone ? 13 : 15,
                ),
              ),
            ),
          // Export Raw Log icon on AppBar (Requirement 9)
          IconButton(
            iconSize: phone ? 20 : null,
            icon: const Icon(Icons.file_download_outlined),
            tooltip: context.tr('ส่งออกข้อมูลดิบ', 'Export raw log'),
            onPressed: _openExportView,
          ),
          // Local Log icon on AppBar
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                iconSize: phone ? 20 : null,
                icon: const Icon(Icons.history_rounded),
                tooltip: context.tr('บันทึกในเครื่อง', 'Local Logs'),
                onPressed: _openLocalLogsView,
              ),
              if (_localLogs.length > _seenLogCount)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(
                      color: Colors.orange,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        (_localLogs.length - _seenLogCount) > 99
                            ? '99+'
                            : '${_localLogs.length - _seenLogCount}',
                        style: AppFonts.manropeBold.copyWith(
                          fontSize: 8,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        maintainBottomViewPadding: true,
        child: phone ? _fitPhoneBody(body, isPortrait) : body,
      ),
    );
    return PopScope(
      canPop: !_isMeasuring,
      child: Stack(
        fit: StackFit.expand,
        children: [
          dashboard,
          if (_isMeasuring) ...[
            const ModalBarrier(dismissible: false, color: Colors.black38),
            Center(
              child: AlertDialog(
                content: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox.square(
                      dimension: 26,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                    const SizedBox(width: 16),
                    Flexible(
                      child: Text(
                        context.tr(
                          'เซนเซอร์กำลังทำงาน กรุณารอ',
                          'Sensor is measuring. Please wait.',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _fitPhoneBody(Widget body, bool isPortrait) => LayoutBuilder(
    builder: (context, constraints) {
      final textScale = math.max(
        1.0,
        MediaQuery.textScalerOf(context).scale(11) / 11,
      );
      final minimumHeight = isPortrait
          ? 74 + _phonePortraitStartRadius + 410 * textScale
          : 30 + 204 * textScale;
      if (constraints.maxHeight >= minimumHeight) return body;
      return SingleChildScrollView(
        child: SizedBox(height: minimumHeight, child: body),
      );
    },
  );

  // ============================================================
  // PORTRAIT — Map top, GPS/Name, 8 cards with circle START button between the 4 cards
  // Fits completely on one screen without scrolling
  // ============================================================
  Widget _buildPortrait(bool phone) {
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // MAP — top
          Expanded(flex: phone ? 6 : 7, child: _buildMap()),

          const SizedBox(height: 6),

          // GPS bar + Name input under map
          _buildGpsBar(),
          const SizedBox(height: 4),
          _buildMeasurementNameInput(compact: true, phone: phone),
          const SizedBox(height: 6),

          // SENSOR GRID — 2 columns x 4 rows with circle START button in center between Row 3 & 4
          Expanded(
            flex: 10,
            child: LayoutBuilder(
              builder: (ctx, bc) {
                final cardH = (bc.maxHeight - 3 * _sensorGridSpacing) / 4;
                final cardW = (bc.maxWidth - _sensorGridSpacing) / 2;
                final grid = _buildSensorGrid(
                  columns: 2,
                  aspectRatio: cardW / cardH,
                  isPortrait: true,
                  phone: phone,
                );
                if (phone) return grid;
                final centerX = bc.maxWidth / 2;
                final centerY = 3 * cardH + 2.5 * _sensorGridSpacing;
                const buttonRadius = _portraitStartDiameter / 2;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    grid,
                    // Floating circular START button — exactly at the center between the 4 cards
                    Positioned(
                      left: centerX - buttonRadius,
                      top: centerY - buttonRadius,
                      child: _buildCircleStartButton(_portraitStartDiameter, phone: false),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
    if (!phone) return content;
    return Column(
      children: [
        Expanded(child: content),
        _buildHalfCircleStartButton(_phonePortraitStartRadius, phone: true),
      ],
    );
  }

  // ============================================================
  // LANDSCAPE — Map left, right: GPS + Name + 4x2 grid; floating half-circle START at bottom center
  // ============================================================
  Widget _buildLandscape(bool phone) {
    const contentPadding = 8.0;
    const buttonRadius = 66.0;
    final cardMargin =
        CardTheme.of(context).margin?.resolve(Directionality.of(context)) ??
        const EdgeInsets.all(4);
    return Stack(
      children: [
        // Main content
        Padding(
          padding: const EdgeInsets.all(contentPadding),
          child: ClipPath(
            clipper: _LandscapeStartCutout(
              bottomInset: contentPadding,
              radius: phone ? 0 : buttonRadius + 2,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Match the inner and bottom edges of the sensor card surface.
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: cardMargin.left,
                      bottom: cardMargin.bottom,
                    ),
                    child: _buildMap(),
                  ),
                ),

                const SizedBox(width: 8),

                // GPS, measurement name, and sensor grid.
                Expanded(
                  flex: 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildGpsBar(),
                      const SizedBox(height: 4),
                      if (phone)
                        Row(
                          children: [
                            Expanded(
                              child: _buildMeasurementNameInput(
                                compact: true,
                                phone: true,
                              ),
                            ),
                            const SizedBox(width: 6),
                            _buildLandscapePhoneControl(),
                          ],
                        )
                      else
                        _buildMeasurementNameInput(compact: true),
                      const SizedBox(height: 6),
                      // Grid fills remaining space: 4 cols x 2 rows
                      Expanded(
                        child: LayoutBuilder(
                          builder: (ctx, bc) {
                            final cardH =
                                (bc.maxHeight - _sensorGridSpacing) / 2;
                            final cardW =
                                (bc.maxWidth - 3 * _sensorGridSpacing) / 4;
                            final ratio = cardW / cardH;
                            return _buildSensorGrid(
                              columns: 4,
                              aspectRatio: ratio,
                              isPortrait: false,
                              phone: phone,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Enlarged floating half-circle START button at bottom center (overlapping map & cards)
        if (!phone) Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Center(
            child: _buildHalfCircleStartButton(buttonRadius, phone: false),
          ),
        ),
      ],
    );
  }
}

/// Cuts the same circle from both sides of the landscape layout.
class _LandscapeStartCutout extends CustomClipper<Path> {
  const _LandscapeStartCutout({required this.bottomInset, required this.radius});

  final double bottomInset;
  final double radius;

  @override
  Path getClip(Size size) {
    final rectPath = Path()..addRect(Offset.zero & size);
    if (radius == 0) return rectPath;
    // The button baseline is at the bottom of the stack, below the content.
    final circleCenter = Offset(size.width / 2, size.height + bottomInset);
    final circlePath = Path()
      ..addOval(Rect.fromCircle(center: circleCenter, radius: radius));

    return Path.combine(PathOperation.difference, rectPath, circlePath);
  }

  @override
  bool shouldReclip(covariant _LandscapeStartCutout oldClipper) =>
      oldClipper.bottomInset != bottomInset || oldClipper.radius != radius;
}
