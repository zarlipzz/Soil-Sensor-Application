// Dashboard screen โ€” responsive for Samsung Galaxy Tab A9
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../models/soil_measurement.dart';
import '../services/device_identity_service.dart';
import '../services/gps_service.dart';
import '../services/home_assistant_service.dart';
import '../services/local_storage_service.dart';
import '../services/measurement_engine.dart';
import '../services/usb_serial_service.dart';
import '../utils/app_constants.dart';
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
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const _portraitStartDiameter = 88.0;
  static const _sensorGridSpacing = 6.0;

  // ----- Service instances -----
  final LocalStorageService _storageService = LocalStorageService();
  final UsbSerialService _usbService = UsbSerialService();
  final GpsService _gpsService = GpsService();
  final HomeAssistantService _homeAssistantService = HomeAssistantService();
  final DeviceIdentityService _deviceIdentityService = DeviceIdentityService();
  final MeasurementEngine _measurementEngine = MeasurementEngine();
  final TextEditingController _measurementNameController =
      TextEditingController();

  // ----- State variables -----
  final _logs = ValueNotifier<List<SoilMeasurement>>([]);
  List<SoilMeasurement> get _localLogs => _logs.value;
  Future<void> _logWrites = Future.value();
  final _activeUploads = <String, Future<DataHubUploadResult>>{};
  final _acceptedUploads = <String>{};
  Future<String>? _pendingRetry;
  int _seenLogCount = 0;
  SoilMeasurement _currentData = SoilMeasurement.initial();
  UsbConnectionStatus _usbStatus = UsbConnectionStatus.disconnected;

  // Additional state variables
  bool _isMeasuring = false;
  int _countdownSeconds = 10;
  Timer? _countdownTimer;
  String? _activeMeasurementName;
  String? _measurementNameError;
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
    // Load cached logs
    final logs = await _storageService.loadMeasurements();
    if (mounted) {
      setState(() {
        _logs.value = logs;
        if (_localLogs.isNotEmpty) {
          _currentData = _localLogs.first;
        }
      });
    }

    // USB status callbacks
    _usbService.onStatusChanged = (status) {
      if (!mounted) return;
      setState(() => _usbStatus = status);
      if (status == UsbConnectionStatus.disconnected ||
          status == UsbConnectionStatus.permissionDenied ||
          status == UsbConnectionStatus.connectionFailed) {
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
    _startGpsTracking();
  }

  Future<void> _startGpsTracking() async {
    final enabled = await _gpsService.isLocationServiceEnabled();
    if (!enabled || !await _gpsService.requestPermission()) return;
    final loc = await _gpsService.getCurrentLocation();
    if (mounted && loc != null) setState(() => _currentGpsLocation = loc);
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
        });
  }

  @override
  void dispose() {
    _measurementNameController.dispose();
    _nextSampleTimer?.cancel();
    _countdownTimer?.cancel();
    _measurementEngine.dispose();
    _gpsPositionSubscription?.cancel();
    _usbService.dispose();
    _homeAssistantService.dispose();
    _logs.dispose();
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
    final identity =
        _deviceIdentity ?? await _deviceIdentityService.getIdentity();
    final gps = await _gpsService.getCurrentLocation();
    final timestamp = _measurementEngine.completedAt;
    final measurement = SoilMeasurement.fromAveragedSamples(
      id: 'MEAS-${timestamp.millisecondsSinceEpoch}',
      rawSamples: samples,
      timestamp: timestamp,
      deviceId: identity.id,
      deviceMetadata: identity.metadata,
      measurementName: _activeMeasurementName ?? '',
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
        _currentGpsLocation = gps;
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
          const SnackBar(content: Text('บันทึกข้อมูลลงเครื่องไม่สำเร็จ')),
        );
      }
      return;
    }
    if (!mounted) return;
    final result = await _uploadSavedMeasurement(measurement);
    if (!mounted) return;
    final message = switch (result) {
      DataHubUploadResult.uploaded =>
        'บันทึกลงเครื่องและส่งไปยัง Data Hub แล้ว',
      DataHubUploadResult.notConfigured =>
        'บันทึกลงเครื่องแล้ว ตั้งค่า Data Hub แล้วส่งซ้ำจากหน้า Log ได้',
      DataHubUploadResult.failed =>
        'ส่งไปยัง Data Hub ไม่สำเร็จ บันทึกไว้แล้วและส่งซ้ำจากหน้า Log ได้',
      DataHubUploadResult.statusNotSaved =>
        'Data Hub รับข้อมูลแล้ว แต่บันทึกสถานะการส่งลงเครื่องไม่สำเร็จ',
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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

  Future<String> _retryPendingUploads() => _pendingRetry ??= _sendPendingLogs()
      .whenComplete(() => _pendingRetry = null);

  Future<String> _sendPendingLogs() async {
    final pending = _localLogs.reversed
        .where((record) => !record.isSyncedToCloud)
        .toList();
    if (pending.isEmpty) return 'ไม่มีรายการค้างส่ง';
    var sent = 0;
    for (final record in pending) {
      if (!mounted) break;
      final result = await _uploadSavedMeasurement(record);
      switch (result) {
        case DataHubUploadResult.uploaded:
          sent++;
        case DataHubUploadResult.notConfigured:
          return 'ส่งสำเร็จ $sent รายการ กรุณาตั้งค่า Data Hub แล้วลองอีกครั้ง';
        case DataHubUploadResult.failed:
          return 'ส่งสำเร็จ $sent รายการ รายการที่เหลือยังค้างส่ง ลองอีกครั้งเมื่อเชื่อมต่อ Data Hub';
        case DataHubUploadResult.statusNotSaved:
          return 'Data Hub รับรายการล่าสุดแล้ว แต่บันทึกสถานะลงเครื่องไม่สำเร็จ';
      }
    }
    return 'ส่งข้อมูลไปยัง Data Hub แล้ว $sent รายการ';
  }

  Future<void> _openDataHubSettings() async {
    final DataHubSettings settings;
    try {
      settings = await _homeAssistantService.loadSettings();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('โหลดการตั้งค่า Data Hub ไม่สำเร็จ')),
        );
      }
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => DataHubSettingsDialog(
        service: _homeAssistantService,
        settings: settings,
      ),
    );
  }

  // ---------- Read flow ----------
  Future<void> _triggerRead() async {
    if (_isMeasuring) return;
    final name = normalizedMeasurementName(_measurementNameController.text);
    if (name == null) {
      setState(() => _measurementNameError = 'กรุณาระบุชื่อการวัด');
      return;
    }
    if (_usbStatus != UsbConnectionStatus.ready) {
      if (_usbStatus == UsbConnectionStatus.connectionFailed ||
          _usbStatus == UsbConnectionStatus.permissionDenied ||
          _usbStatus == UsbConnectionStatus.disconnected) {
        await _usbService.retry();
      }
      return;
    }

    setState(() {
      _measurementNameController.text = name;
      _measurementNameError = null;
      _activeMeasurementName = name;
      _isMeasuring = true;
      _countdownSeconds = 10;
    });

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
      onTimeout: () =>
          _stopMeasurement('หมดเวลาการตรวจวัดก่อนได้รับค่าครบ 10 ค่า'),
    );
    await _requestNextSample();
  }

  // ---------- Local Logs Modal ----------
  void _openLocalLogsView() {
    setState(() => _seenLogCount = _localLogs.length);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: MediaQuery.orientationOf(ctx) == Orientation.landscape
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
              onRetryPending: _retryPendingUploads,
              onClear: () async {
                if (_pendingRetry != null) return;
                final confirmed = await showDialog<bool>(
                  context: ctx,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Clear all history?'),
                    content: const Text(
                      'This deletes saved records on this device only.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('Delete'),
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
    );
  }

  // ---------- Export Raw Log Modal ----------
  void _openExportView() {
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
              style: const TextStyle(
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
  Widget _buildMap() {
    final center = (_currentGpsLocation != null)
        ? LatLng(_currentGpsLocation!.latitude, _currentGpsLocation!.longitude)
        : const LatLng(13.75, 100.52); // Bangkok default
    final groups = measurementMarkerGroups(_localLogs);
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
  Widget _buildMeasurementNameInput({bool compact = false}) {
    return TextField(
      controller: _measurementNameController,
      enabled: !_isMeasuring,
      textInputAction: TextInputAction.done,
      maxLength: 80,
      onChanged: (_) {
        if (_measurementNameError != null) {
          setState(() => _measurementNameError = null);
        }
      },
      decoration: InputDecoration(
        labelText: 'ชื่อการวัด',
        hintText: 'เช่น แปลง A / Field A',
        errorText: _measurementNameError,
        counterText: '',
        isDense: compact,
        prefixIcon: const Icon(Icons.label_outline_rounded),
        border: const OutlineInputBorder(),
      ),
    );
  }

  // ---------- Floating START buttons ----------

  /// Circular START button for portrait mode
  Widget _buildCircleStartButton() {
    final isReady = _usbStatus == UsbConnectionStatus.ready;
    final bgColor = _isMeasuring
        ? AppColors.appbarBlue
        : isReady
        ? AppColors.softBlue
        : AppColors.disabledStart;

    return GestureDetector(
      onTap: _isMeasuring || !isReady ? null : _triggerRead,
      child: Container(
        width: _portraitStartDiameter,
        height: _portraitStartDiameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: bgColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
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
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                )
              : const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                    Text(
                      'START',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  /// Half-circle START button for landscape mode (bottom center, overlapping map & cards)
  Widget _buildHalfCircleStartButton() {
    final isReady = _usbStatus == UsbConnectionStatus.ready;
    final bgColor = _isMeasuring
        ? AppColors.appbarBlue
        : isReady
        ? AppColors.softBlue
        : AppColors.disabledStart;

    return GestureDetector(
      onTap: _isMeasuring || !isReady ? null : _triggerRead,
      child: Container(
        width: 132,
        height: 64,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(66)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 10,
              spreadRadius: 1,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Align(
          alignment: Alignment.center,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
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
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  )
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'START',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
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
  }) {
    const portraitStartCutoutRadius = 52.0;
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
          title: 'ความชื้น',
          value: _currentData.moisture.toStringAsFixed(1),
          unit: '%',
          icon: Icons.water_drop_rounded,
          color: AppColors.moistureColor,
          valueFontSize: isPortrait ? 38 : 34,
        ),
        SensorCard(
          title: 'อุณหภูมิ',
          value: _currentData.temperature.toStringAsFixed(2),
          unit: '°C',
          icon: Icons.thermostat_rounded,
          color: AppColors.tempColor,
          valueFontSize: isPortrait ? 38 : 34,
        ),
        SensorCard(
          title: 'pH',
          value: _currentData.ph.toStringAsFixed(2),
          unit: '',
          icon: Icons.science_rounded,
          color: AppColors.phColor,
          valueFontSize: isPortrait ? 38 : 34,
        ),
        SensorCard(
          title: 'EC',
          value: '${_currentData.ec}',
          unit: 'µS/cm',
          icon: Icons.bolt_rounded,
          color: AppColors.ecColor,
          valueFontSize: isPortrait ? 38 : 34,
        ),
        SensorCard(
          title: 'ไนโตรเจน',
          value: '${_currentData.nitrogen}',
          unit: 'mg/kg',
          icon: Icons.grass_rounded,
          color: AppColors.nitrogenColor,
          cornerCutout: isPortrait
              ? CornerCutout.bottomRight
              : CornerCutout.none,
          cutoutRadius: portraitStartCutoutRadius,
          valueFontSize: isPortrait ? 38 : 34,
        ),
        SensorCard(
          title: 'ฟอสฟอรัส',
          value: '${_currentData.phosphorus}',
          unit: 'mg/kg',
          icon: Icons.grain_rounded,
          color: AppColors.phosphorusColor,
          cornerCutout: isPortrait
              ? CornerCutout.bottomLeft
              : CornerCutout.none,
          cutoutRadius: isPortrait ? portraitStartCutoutRadius : 46.0,
          valueFontSize: isPortrait ? 38 : 34,
        ),
        SensorCard(
          title: 'โพแทสเซียม',
          value: '${_currentData.potassium}',
          unit: 'mg/kg',
          icon: Icons.spa_rounded,
          color: AppColors.potassiumColor,
          cornerCutout: isPortrait ? CornerCutout.topRight : CornerCutout.none,
          cutoutRadius: isPortrait ? portraitStartCutoutRadius : 46.0,
          valueFontSize: isPortrait ? 38 : 34,
        ),
        SensorCard(
          title: 'ความเค็ม',
          value: '${_currentData.salinity}',
          unit: 'mg/L',
          icon: Icons.waves_rounded,
          color: AppColors.salinityColor,
          cornerCutout: isPortrait ? CornerCutout.topLeft : CornerCutout.none,
          cutoutRadius: isPortrait ? portraitStartCutoutRadius : 46.0,
          valueFontSize: isPortrait ? 38 : 34,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isPortrait = size.height > size.width;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        titleSpacing: 8,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Image.asset(
                'assets/meta_soil_logo.png',
                width: 24,
                height: 24,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text(
                    AppConstants.appTitle,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  Text(
                    AppConstants.appSubtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'ตั้งค่า Data Hub',
            onPressed: _openDataHubSettings,
          ),
          // Export Raw Log icon on AppBar (Requirement 9)
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'ส่งออกข้อมูลดิบ (Export Raw Log)',
            onPressed: _openExportView,
          ),
          // Local Log icon on AppBar
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.history_rounded),
                tooltip: 'Local Logs',
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
                        style: const TextStyle(
                          fontSize: 8,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
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
        child: isPortrait ? _buildPortrait(size) : _buildLandscape(size),
      ),
    );
  }

  // ============================================================
  // PORTRAIT — Map top, GPS/Name, 8 cards with circle START button between the 4 cards
  // Fits completely on one screen without scrolling
  // ============================================================
  Widget _buildPortrait(Size size) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // MAP — top
          Expanded(flex: 7, child: _buildMap()),

          const SizedBox(height: 6),

          // GPS bar + Name input under map
          _buildGpsBar(),
          const SizedBox(height: 4),
          _buildMeasurementNameInput(compact: true),
          const SizedBox(height: 6),

          // SENSOR GRID — 2 columns x 4 rows with circle START button in center between Row 3 & 4
          Expanded(
            flex: 10,
            child: LayoutBuilder(
              builder: (ctx, bc) {
                final cardH = (bc.maxHeight - 3 * _sensorGridSpacing) / 4;
                final cardW = (bc.maxWidth - _sensorGridSpacing) / 2;
                final ratio = cardW / cardH;
                final centerX = bc.maxWidth / 2;
                final centerY = 3 * cardH + 2.5 * _sensorGridSpacing;
                const buttonRadius = _portraitStartDiameter / 2;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _buildSensorGrid(
                      columns: 2,
                      aspectRatio: ratio,
                      isPortrait: true,
                    ),
                    // Floating circular START button — exactly at the center between the 4 cards
                    Positioned(
                      left: centerX - buttonRadius,
                      top: centerY - buttonRadius,
                      child: _buildCircleStartButton(),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // LANDSCAPE — Map left, right: GPS + Name + 4x2 grid; floating half-circle START at bottom center
  // ============================================================
  Widget _buildLandscape(Size size) {
    const contentPadding = 8.0;
    final cardMargin =
        CardTheme.of(context).margin?.resolve(Directionality.of(context)) ??
        const EdgeInsets.all(4);
    return Stack(
      children: [
        // Main content
        Padding(
          padding: const EdgeInsets.all(contentPadding),
          child: ClipPath(
            clipper: const _LandscapeStartCutout(bottomInset: contentPadding),
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
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Center(child: _buildHalfCircleStartButton()),
        ),
      ],
    );
  }
}

/// Cuts the same circle from both sides of the landscape layout.
class _LandscapeStartCutout extends CustomClipper<Path> {
  const _LandscapeStartCutout({required this.bottomInset});

  final double bottomInset;

  @override
  Path getClip(Size size) {
    final rectPath = Path()..addRect(Offset.zero & size);
    // The button baseline is at the bottom of the stack, below the content.
    final circleCenter = Offset(size.width / 2, size.height + bottomInset);
    final circlePath = Path()
      ..addOval(Rect.fromCircle(center: circleCenter, radius: 68));

    return Path.combine(PathOperation.difference, rectPath, circlePath);
  }

  @override
  bool shouldReclip(covariant _LandscapeStartCutout oldClipper) =>
      oldClipper.bottomInset != bottomInset;
}
