// Dashboard screen โ€” responsive for Samsung Galaxy Tab A9
import '../widgets/sensor_card.dart';

import 'dart:typed_data';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

import '../models/soil_measurement.dart';
import '../services/home_assistant_service.dart';
import '../services/gps_service.dart';
import '../services/device_identity_service.dart';
import '../services/local_storage_service.dart';
import '../services/measurement_engine.dart';
import '../services/usb_serial_service.dart';
import '../utils/app_constants.dart';
import '../widgets/non_network_tile_provider.dart';
import '../models/location_group.dart';

/// Main Dashboard Screen displaying realtime metrics, hardware state, and controls.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // ----- Service instances -----
  final LocalStorageService _storageService = LocalStorageService();
  final UsbSerialService _usbService = UsbSerialService();
  final GpsService _gpsService = GpsService();
  final HomeAssistantService _homeAssistantService = HomeAssistantService();
  final DeviceIdentityService _deviceIdentityService = DeviceIdentityService();
  final MeasurementEngine _measurementEngine = MeasurementEngine();

  // ----- State variables -----
  List<SoilMeasurement> _localLogs = [];
  int _seenLogCount = 0;
  SoilMeasurement _currentData = SoilMeasurement.initial();
  UsbConnectionStatus _usbStatus = UsbConnectionStatus.disconnected;

  // Additional state variables
  bool _isCloudSyncing = false;
  bool _isMeasuring = false;
  DeviceIdentity? _deviceIdentity;
  Timer? _nextSampleTimer;
  GpsLocationData? _currentGpsLocation;
  StreamSubscription<Position>? _gpsPositionSubscription;

  // ---------- Location Grouping ----------
  static const double _groupRadiusMeters = 15.0;
  List<LocationGroup> _locationGroups = [];

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
        _localLogs = logs;
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
        _stopMeasurement(
          'Measurement stopped because the USB sensor is unavailable.',
        );
      }
      _showUsbStatus(status);
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
    _nextSampleTimer?.cancel();
    _measurementEngine.dispose();
    _gpsPositionSubscription?.cancel();
    _usbService.dispose();
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
    DeviceIdentity identity;
    try {
      identity = _deviceIdentity ?? await _deviceIdentityService.getIdentity();
    } catch (error) {
      _stopMeasurement(
        'Measurement could not be saved: device identity is unavailable.',
      );
      debugPrint('[DashboardScreen] Cannot complete measurement: $error');
      return;
    }
    final gps = await _gpsService.getCurrentLocation();
    final timestamp = _measurementEngine.completedAt;
    final measurement = SoilMeasurement.fromAveragedSamples(
      id: 'MEAS-${timestamp.millisecondsSinceEpoch}',
      rawSamples: samples,
      timestamp: timestamp,
      deviceId: identity.id,
      deviceMetadata: identity.metadata,
      latitude: gps?.latitude,
      longitude: gps?.longitude,
      gpsAccuracy: gps?.accuracy,
      locationTimestamp: gps?.timestamp,
    );
    if (mounted) {
      setState(() {
        _isMeasuring = false;
        _currentData = measurement;
        _currentGpsLocation = gps;
      });
    }
    await _processNewMeasurement(measurement);
  }

  void _scheduleNextSample() {
    _nextSampleTimer?.cancel();
    _nextSampleTimer = Timer(
      const Duration(milliseconds: 200),
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

  void _stopMeasurement(String message) {
    if (!_measurementEngine.isCollecting && !_isMeasuring) return;
    _nextSampleTimer?.cancel();
    _measurementEngine.cancel();
    if (mounted) {
      setState(() => _isMeasuring = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  // ---------- Data handling ----------
  Future<void> _processNewMeasurement(SoilMeasurement measurement) async {
    // Save locally
    final updatedList = await _storageService.saveMeasurement(
      measurement,
      _localLogs,
    );
    if (mounted) setState(() => _localLogs = updatedList);

    // Upload to cloud if needed
    if (mounted) setState(() => _isCloudSyncing = true);
    final uploaded = await _homeAssistantService.uploadMeasurement(measurement);
    if (uploaded) {
      final syncedList = await _storageService.updateSyncStatus(
        measurement.id,
        true,
        _localLogs,
      );
      if (mounted) {
        setState(() {
          measurement.isSyncedToCloud = true;
          _localLogs = syncedList;
          _isCloudSyncing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'บันทึกลงเครื่องและส่งไปยัง Home Assistant เรียบร้อย!',
            ),
            duration: Duration(seconds: 2),
            backgroundColor: AppColors.softBlue,
          ),
        );
      }
    } else {
      if (mounted) setState(() => _isCloudSyncing = false);
    }
  }

  // ---------- Read flow ----------
  Future<void> _triggerRead() async {
    if (_isMeasuring) return;
    if (_usbStatus != UsbConnectionStatus.ready) {
      if (_usbStatus == UsbConnectionStatus.connectionFailed ||
          _usbStatus == UsbConnectionStatus.permissionDenied ||
          _usbStatus == UsbConnectionStatus.disconnected) {
        await _usbService.retry();
      }
      return;
    }

    setState(() => _isMeasuring = true);
    _measurementEngine.start(
      onTimeout: () => _stopMeasurement(
        'Measurement timed out before 10 valid samples were received.',
      ),
    );
    await _requestNextSample();
    // Completion is handled by _handleSamplePacket after ten valid frames.
    if (_isMeasuring) return;

    final gps = await _gpsService.getCurrentLocation();
    if (mounted) setState(() => _currentGpsLocation = gps);

    if (_usbStatus == UsbConnectionStatus.ready) {
      // Physical read โ€“ USB service will emit a validated packet
      await _usbService.sendQuery();
    } else {
      // Simulation mode โ€“ do NOT mark data as fresh for saving
      final now = DateTime.now();
      final simulated = SoilMeasurement(
        id: 'SIM-${now.millisecondsSinceEpoch}',
        temperature:
            (_currentData.temperature + (0.1 - (0.2 * (now.second % 2)))).clamp(
              20.0,
              35.0,
            ),
        moisture: _currentData.moisture,
        ec: _currentData.ec,
        salinity: _currentData.salinity,
        nitrogen: _currentData.nitrogen,
        phosphorus: _currentData.phosphorus,
        potassium: _currentData.potassium,
        ph: _currentData.ph,
        timestamp: now,
        latitude: gps?.latitude,
        longitude: gps?.longitude,
        gpsAccuracy: gps?.accuracy,
        locationTimestamp: gps?.timestamp,
      );
      if (mounted) {
        setState(() {
          _currentData = simulated;
        });
      }
      await _processNewMeasurement(simulated);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'อ่านค่าและบันทึกเรียบร้อย (${_formatTime(_currentData.timestamp)})',
          ),
          duration: const Duration(seconds: 1),
          backgroundColor: AppColors.softBlue,
        ),
      );
    }
  }

  void _showUsbStatus(UsbConnectionStatus status) {
    final message = switch (status) {
      UsbConnectionStatus.requestingPermission => 'Requesting USB permission…',
      UsbConnectionStatus.permissionDenied =>
        'USB permission was denied. Tap Read sensor to retry.',
      UsbConnectionStatus.connecting => 'Connecting to the CH340 sensor…',
      UsbConnectionStatus.initializing =>
        'Sensor is initializing for 3 seconds. Readings are being discarded.',
      UsbConnectionStatus.ready => 'CH340 sensor is ready.',
      UsbConnectionStatus.connectionFailed => 'Sensor initialization failed. Reconnect it or tap Read sensor to retry.',
      UsbConnectionStatus.disconnected => 'USB sensor disconnected.',
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        backgroundColor:
            status == UsbConnectionStatus.connectionFailed ||
                status == UsbConnectionStatus.permissionDenied
            ? AppColors.statusWarning
            : AppColors.softBlue,
      ),
    );
  }

  String _formatTime(DateTime dt) =>
      "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}";

  // ---------- Local Logs Modal ----------
  void _openLocalLogsView() {
    setState(() => _seenLogCount = _localLogs.length);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, scrollController) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.history_rounded, color: AppColors.softBlue),
                  const SizedBox(width: 8),
                  Text(
                    'บันทึกในเครื่อง (${_localLogs.length} รายการ)',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: _localLogs.isEmpty
                  ? const Center(child: Text('ยังไม่มีข้อมูลที่บันทึก'))
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: _localLogs.length,
                      itemBuilder: (c, i) {
                        final m = _localLogs[i];
                        return ListTile(
                          dense: true,
                          leading: const Icon(
                            Icons.eco_rounded,
                            color: AppColors.softBlue,
                            size: 20,
                          ),
                          title: Text(
                            '${m.timestamp.day}/${m.timestamp.month}/${m.timestamp.year} ${_formatTime(m.timestamp)}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            'ความชื้น: ${m.moisture.toStringAsFixed(1)}%  อุณหภูมิ: ${m.temperature.toStringAsFixed(2)} °C',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: m.isSyncedToCloud
                              ? const Icon(
                                  Icons.cloud_done_rounded,
                                  color: AppColors.softBlue,
                                  size: 18,
                                )
                              : const Icon(
                                  Icons.cloud_off_rounded,
                                  color: Colors.grey,
                                  size: 18,
                                ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
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

  // ---------- Map widget ----------
  Widget _buildMap() {
    final center = (_currentGpsLocation != null)
        ? LatLng(_currentGpsLocation!.latitude, _currentGpsLocation!.longitude)
        : const LatLng(13.75, 100.52); // Bangkok default
    final validLogs = _localLogs
        .where(
          (m) =>
              m.latitude != null &&
              m.longitude != null &&
              m.latitude!.isFinite &&
              m.longitude!.isFinite,
        )
        .toList();
    final groups = <({LatLng center, List<SoilMeasurement> logs})>[];
    for (final log in validLogs) {
      final point = LatLng(log.latitude!, log.longitude!);
      final i = groups.indexWhere(
        (g) =>
            const Distance().as(LengthUnit.Meter, g.center, point) <=
            _groupRadiusMeters,
      );
      if (i == -1) {
        groups.add((center: point, logs: [log]));
      } else {
        groups[i].logs.add(log);
      }
    }
    final savedMarkers = groups
        .map(
          (group) => Marker(
            point: group.center,
            width: 30,
            height: 36,
            child: GestureDetector(
              onTap: () => _showMeasurementGroupOnMap(group.logs),
              child: const Icon(
                Icons.location_on,
                color: Colors.green,
                size: 30,
              ),
            ),
          ),
        )
        .toList();
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

  void _showMeasurementGroupOnMap(List<SoilMeasurement> measurements) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.45,
        maxChildSize: 0.9,
        builder: (ctx, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'ข้อมูลหมุด ${measurements.length} รายการ',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const Divider(),
            ...(List<SoilMeasurement>.from(
              measurements,
            )..sort((a, b) => b.timestamp.compareTo(a.timestamp))).map(
              (m) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${m.timestamp}'),
                subtitle: Text(
                  'ความชื้น ${m.moisture.toStringAsFixed(1)}% · อุณหภูมิ ${m.temperature.toStringAsFixed(2)} °C\nEC ${m.ec} µS/cm · Salinity ${m.salinity} mg/L · N ${m.nitrogen} · P ${m.phosphorus} · K ${m.potassium} · pH ${m.ph.toStringAsFixed(2)}',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Action buttons ----------
  Widget _buildActionButtons({bool compact = false}) {
    final vPad = compact ? 8.0 : 10.0;
    final fontSize = compact ? 12.0 : 13.0;
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed:
                _isMeasuring ||
                    _usbStatus == UsbConnectionStatus.initializing ||
                    _usbStatus == UsbConnectionStatus.connecting ||
                    _usbStatus == UsbConnectionStatus.requestingPermission
                ? null
                : _triggerRead,
            icon: _isMeasuring
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(Icons.refresh_rounded, size: compact ? 16 : 18),
            label: Text(
              _isMeasuring
                  ? 'กำลังตรวจวัดค่าดิน'
                  : _usbStatus == UsbConnectionStatus.ready
                  ? 'Read sensor'
                  : 'Retry sensor',
              style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.softBlue,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: vPad, horizontal: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------- Sensor grid ----------
  Widget _buildSensorGrid({required int columns, required double aspectRatio}) {
    return GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 6,
      mainAxisSpacing: 6,
      childAspectRatio: aspectRatio,
      children: [
        SensorCard(
          title: 'ความชื้น',
          value: '${_currentData.moisture.toStringAsFixed(1)} %',
          icon: Icons.water_drop_rounded,
          color: AppColors.moistureColor,
          subtext: 'เหมาะสม: 15–35%',
        ),
        SensorCard(
          title: 'อุณหภูมิ',
          value: '${_currentData.temperature.toStringAsFixed(2)} °C',
          icon: Icons.thermostat_rounded,
          color: AppColors.tempColor,
          subtext: 'ปกติ: 20–30 °C',
        ),
        SensorCard(
          title: 'pH',
          value: _currentData.ph.toStringAsFixed(2),
          icon: Icons.science_rounded,
          color: AppColors.phColor,
          subtext: 'Neutral: 6.5-7.5',
        ),
        SensorCard(
          title: 'EC',
          value: '${_currentData.ec} µS/cm',
          icon: Icons.bolt_rounded,
          color: AppColors.ecColor,
          subtext: 'ปกติ: 100–1000',
        ),
        SensorCard(
          title: 'ไนโตรเจน',
          value: '${_currentData.nitrogen} mg/kg',
          icon: Icons.grass_rounded,
          color: AppColors.nitrogenColor,
          subtext: 'Available N',
        ),
        SensorCard(
          title: 'ฟอสฟอรัส',
          value: '${_currentData.phosphorus} mg/kg',
          icon: Icons.grain_rounded,
          color: AppColors.phosphorusColor,
          subtext: 'Available P',
        ),
        SensorCard(
          title: 'โพแทสเซียม',
          value: '${_currentData.potassium} mg/kg',
          icon: Icons.spa_rounded,
          color: AppColors.potassiumColor,
          subtext: 'Available K',
        ),
        SensorCard(
          title: 'ความเค็ม',
          value: '${_currentData.salinity} mg/L',
          icon: Icons.waves_rounded,
          color: AppColors.salinityColor,
          subtext: 'มาตรฐาน: <800 mg/L',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isPortrait = size.height > size.width;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Icon(
                Icons.eco_rounded,
                size: 18,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  'Soil Multi-Parameter Sensor',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                Text(
                  AppConstants.appSubtitle,
                  style: TextStyle(fontSize: 10, color: Colors.white70),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Local Log icon on AppBar top-right
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
        child: isPortrait ? _buildPortrait(size) : _buildLandscape(size),
      ),
    );
  }

  // ============================================================
  // PORTRAIT โ€” Map top 45%, buttons middle, 8 cards bottom 50%
  // ============================================================
  Widget _buildPortrait(Size size) {
    // Available height after AppBar + SafeArea (approximate)
    // Map: flex 9, buttons+gps: fixed, grid: flex 10
    return Column(
      children: [
        // MAP โ€” top ~45%
        Expanded(
          flex: 9,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: _buildMap(),
          ),
        ),

        // GPS bar + Action buttons โ€” compact middle strip
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            children: [
              _buildGpsBar(),
              const SizedBox(height: 4),
              _buildActionButtons(),
              const SizedBox(height: 4),
            ],
          ),
        ),

        // SENSOR GRID โ€” bottom ~50%, 2 columns ร— 4 rows, no scroll
        Expanded(
          flex: 10,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: LayoutBuilder(
              builder: (ctx, bc) {
                // 2 cols, 4 rows, 6px gap ร— 3 rows = 18, padding consumed
                final cardH = (bc.maxHeight - 18) / 4;
                final cardW = (bc.maxWidth - 6) / 2;
                final ratio = cardW / cardH;
                return _buildSensorGrid(columns: 2, aspectRatio: ratio);
              },
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // LANDSCAPE โ€” Map left 50%, right: buttons top + 8 cards
  // ============================================================
  Widget _buildLandscape(Size size) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // LEFT: Map fills full height
          Expanded(flex: 1, child: _buildMap()),

          const SizedBox(width: 8),

          // RIGHT: GPS + buttons + 4ร—2 grid
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildGpsBar(),
                const SizedBox(height: 4),
                _buildActionButtons(compact: true),
                const SizedBox(height: 6),
                // Grid fills remaining space โ€” 4 cols ร— 2 rows, equal cells
                Expanded(
                  child: LayoutBuilder(
                    builder: (ctx, bc) {
                      final cardH = (bc.maxHeight - 6) / 2;
                      final cardW = (bc.maxWidth - 18) / 4;
                      final ratio = cardW / cardH;
                      return _buildSensorGrid(columns: 4, aspectRatio: ratio);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
