import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/soil_measurement.dart';
import '../services/firebase_service.dart';
import '../services/gps_service.dart';
import '../services/local_storage_service.dart';
import '../services/usb_serial_service.dart';

import '../utils/app_constants.dart';

import '../widgets/device_status_indicator.dart';
import '../widgets/measurement_detail.dart';
import '../widgets/sensor_card.dart';
import 'map_screen.dart';

/// Main Dashboard Screen displaying realtime metrics, hardware state, and controls.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Services
  final UsbSerialService _usbService = UsbSerialService();
  final LocalStorageService _storageService = LocalStorageService();
  FirebaseService? _firebaseService;
  final GpsService _gpsService = GpsService();

  // State variables
  SoilMeasurement _currentData = SoilMeasurement.initial();
  List<SoilMeasurement> _localLogs = [];

  bool _isDeviceConnected = false;
  bool _isAutoReading = false;
  bool _isCloudSyncing = false;
  Timer? _autoReadTimer;
  GpsLocationData? _currentGpsLocation;

  @override
  void initState() {
    super.initState();
    _initServices();
  }

  Future<void> _initServices() async {
    // 1. Load cached logs
    final logs = await _storageService.loadMeasurements();
    if (mounted) {
      setState(() {
        _localLogs = logs;
        if (_localLogs.isNotEmpty) {
          _currentData = _localLogs.first;
        }
      });
    }

    // 2. Setup USB Service callbacks
    _usbService.onConnectionChanged = (connected) {
      if (mounted) {
        setState(() => _isDeviceConnected = connected);
      }
    };

    _usbService.onPacketReceived = (Uint8List packet) async {
      final gps = await _gpsService.getCurrentLocation();
      final measurement = SoilMeasurement.fromRawBytes(
        packet,
        latitude: gps?.latitude,
        longitude: gps?.longitude,
        gpsAccuracy: gps?.accuracy,
        locationTimestamp: gps?.timestamp,
      );

      if (mounted) {
        setState(() {
          _currentData = measurement;
          _currentGpsLocation = gps;
        });
      }

      await _processNewMeasurement(measurement);
    };

    // 3. Initialize USB detection
    _usbService.initialize();

    // 4. Initial GPS location check
    _gpsService.getCurrentLocation().then((loc) {
      if (mounted) {
        setState(() => _currentGpsLocation = loc);
      }
    });
  }

  @override
  void dispose() {
    _autoReadTimer?.cancel();
    _usbService.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------
  // Data Processing (Local Storage + Cloud Sync)
  // -------------------------------------------------------------
  Future<void> _processNewMeasurement(SoilMeasurement measurement) async {
    // 1. Save to local storage
    final updatedList = await _storageService.saveMeasurement(
      measurement,
      _localLogs,
    );

    if (mounted) {
      setState(() => _localLogs = updatedList);
    }

    // 2. Upload to Cloud Firestore
    if (mounted) setState(() => _isCloudSyncing = true);
    final uploaded = await _firebaseService?.uploadMeasurement(measurement) ?? false;

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
            content: Text('☁️ บันทึกลงเครื่องและซิงค์ขึ้น Firebase เรียบร้อย!'),
            duration: Duration(seconds: 2),
            backgroundColor: AppColors.softBlue,
          ),
        );
      }
    } else {
      if (mounted) {
        setState(() => _isCloudSyncing = false);
      }
    }
  }

  // -------------------------------------------------------------
  // Trigger Read Flow (Hardware or Simulated)
  // -------------------------------------------------------------
  Future<void> _triggerRead() async {
    final gps = await _gpsService.getCurrentLocation();
    if (mounted) {
      setState(() => _currentGpsLocation = gps);
    }

    if (_isDeviceConnected) {
      // Send query frame to USB device
      await _usbService.sendQuery();
    } else {
      // Development / Web / Disconnected simulation mode
      final now = DateTime.now();
      final simulated = SoilMeasurement(
        id: 'LOG-${now.millisecondsSinceEpoch}',
        temperature: (_currentData.temperature +
                (0.1 - (0.2 * (now.second % 2))))
            .clamp(20.0, 35.0),
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

  // -------------------------------------------------------------
  // Auto-Read (Interval: 1 Minute)
  // -------------------------------------------------------------
  void _toggleAutoRead(bool value) {
    setState(() {
      _isAutoReading = value;
      if (_isAutoReading) {
        _triggerRead();
        _autoReadTimer = Timer.periodic(AppConstants.autoReadInterval, (_) {
          _triggerRead();
        });
      } else {
        _autoReadTimer?.cancel();
      }
    });
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  Future<void> _clearLocalLogs() async {
    await _storageService.clearAll();
    if (mounted) {
      setState(() {
        _localLogs.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ล้างข้อมูล Local Log ในเครื่องเรียบร้อยแล้ว'),
          duration: Duration(seconds: 2),
          backgroundColor: AppColors.softBlue,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.eco_rounded, size: 22, color: Colors.white),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Soil Multi-Parameter Sensor',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                ),
                Text(
                  AppConstants.appSubtitle,
                  style: TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.map_outlined),
            tooltip: 'เปิดแผนที่แปลง',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const MapScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status & Primary Action Header
            _buildControlHeader(),
            const SizedBox(height: 18),

            // Section 1: General Soil Condition
            const Text(
              'สภาพดินทั่วไป (General Soil Status)',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppColors.statusDarkText,
              ),
            ),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.35,
              children: [
                SensorCard(
                  title: 'ความชื้น (Moisture)',
                  value: '${_currentData.moisture.toStringAsFixed(1)} %',
                  icon: Icons.water_drop_rounded,
                  color: AppColors.moistureColor,
                  subtext: 'Optimal: 15–35%',
                ),
                SensorCard(
                  title: 'อุณหภูมิดิน (Temp)',
                  value: '${_currentData.temperature.toStringAsFixed(1)} °C',
                  icon: Icons.thermostat_rounded,
                  color: AppColors.tempColor,
                  subtext: 'Normal: 20–30°C',
                ),
                SensorCard(
                  title: 'ความเป็นกรด-ด่าง (pH)',
                  value: _currentData.ph.toStringAsFixed(2),
                  icon: Icons.science_rounded,
                  color: AppColors.phColor,
                  subtext: 'Neutral: 6.5–7.5',
                ),
                SensorCard(
                  title: 'การนำไฟฟ้า (EC)',
                  value: '${_currentData.ec} µS/cm',
                  icon: Icons.bolt_rounded,
                  color: AppColors.ecColor,
                  subtext: 'Normal: 100–1000',
                ),
              ],
            ),

            const SizedBox(height: 18),

            // Section 2: Soil Nutrients & Salinity
            const Text(
              'ธาตุอาหารและความเค็ม (NPK & Salinity)',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppColors.statusDarkText,
              ),
            ),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.35,
              children: [
                SensorCard(
                  title: 'ไนโตรเจน (N)',
                  value: '${_currentData.nitrogen} mg/kg',
                  icon: Icons.grass_rounded,
                  color: AppColors.nitrogenColor,
                  subtext: 'Available Nitrogen',
                ),
                SensorCard(
                  title: 'ฟอสฟอรัส (P)',
                  value: '${_currentData.phosphorus} mg/kg',
                  icon: Icons.grain_rounded,
                  color: AppColors.phosphorusColor,
                  subtext: 'Available Phosphorus',
                ),
                SensorCard(
                  title: 'โพแทสเซียม (K)',
                  value: '${_currentData.potassium} mg/kg',
                  icon: Icons.spa_rounded,
                  color: AppColors.potassiumColor,
                  subtext: 'Available Potassium',
                ),
                SensorCard(
                  title: 'ความเค็ม (Salinity)',
                  value: '${_currentData.salinity} mg/L',
                  icon: Icons.waves_rounded,
                  color: AppColors.salinityColor,
                  subtext: 'Standard: <800 mg/L',
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Auto-read switch card
            _buildAutoReadCard(),
            const SizedBox(height: 14),

            // Button to open Local Logs
            OutlinedButton.icon(
              onPressed: _openLocalLogsView,
              icon: const Icon(
                Icons.history_rounded,
                size: 20,
                color: AppColors.softBlue,
              ),
              label: Text(
                'เปิดดู Local Logs ที่บันทึกในเครื่อง (${_localLogs.length} รายการ)',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.softBlue,
                ),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15),
                side: const BorderSide(color: AppColors.softBlue, width: 1.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildControlHeader() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            DeviceStatusIndicator(
              isDeviceConnected: _isDeviceConnected,
              isCloudSyncing: _isCloudSyncing,
              lastUpdated: _currentData.timestamp,
              gpsStatus: _gpsService.status,
              gpsLocation: _currentGpsLocation,
            ),
            const SizedBox(height: 14),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _triggerRead,
                icon: const Icon(Icons.refresh_rounded, size: 22),
                label: const Text(
                  'อ่านค่าจากเซนเซอร์เดี๋ยวนี้ (On-Demand Read)',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.softBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAutoReadCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppColors.lightBlueTint,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.timer_outlined,
                    size: 20,
                    color: AppColors.softBlue,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'อ่านค่าอัตโนมัติ (ทุก 1 นาที):',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                ),
              ],
            ),
            Switch(
              value: _isAutoReading,
              activeThumbColor: AppColors.softBlue,
              onChanged: _toggleAutoRead,
            ),
          ],
        ),
      ),
    );
  }

  void _openLocalLogsView() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          minChildSize: 0.4,
          builder: (context, scrollController) {
            return StatefulBuilder(
              builder: (context, setSheetState) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Column(
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 10, bottom: 6),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'บันทึกในเครื่อง (Local Logs)',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                Text(
                                  'เก็บถาวรในเครื่อง ${_localLogs.length} รายการ (แม้ปิดแอปข้อมูลก็ไม่หาย)',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.statusSubText,
                                  ),
                                ),
                              ],
                            ),
                            if (_localLogs.isNotEmpty)
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.redAccent,
                                ),
                                tooltip: 'ล้างบันทึกทั้งหมด',
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('ยืนยันล้างบันทึกในเครื่อง'),
                                      content: const Text(
                                        'คุณต้องการลบข้อมูล Local Log ทั้งหมดหรือไม่?',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx, false),
                                          child: const Text('ยกเลิก'),
                                        ),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.red,
                                          ),
                                          onPressed: () => Navigator.pop(ctx, true),
                                          child: const Text(
                                            'ลบทั้งหมด',
                                            style: TextStyle(color: Colors.white),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );

                                  if (confirm == true) {
                                    await _clearLocalLogs();
                                    setSheetState(() {});
                                  }
                                },
                              ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),

                      Expanded(
                        child: _localLogs.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.inventory_2_outlined,
                                      size: 48,
                                      color: Colors.grey.shade400,
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'ยังไม่มีข้อมูลบันทึกในเครื่อง',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.black54,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'กดปุ่ม "อ่านค่าจากเซนเซอร์เดี๋ยวนี้" เพื่อบันทึกข้อมูลแรก',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                controller: scrollController,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                itemCount: _localLogs.length,
                                itemBuilder: (context, index) {
                                  final item = _localLogs[index];
                                  return MeasurementDetailCard(
                                    item: item,
                                    index: index,
                                    totalCount: _localLogs.length,
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
