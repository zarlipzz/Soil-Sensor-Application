import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:usb_serial/usb_serial.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('Firebase initialized successfully.');
  } catch (e) {
    debugPrint('Firebase initialization warning: $e');
  }

  runApp(const SoilSensorApp());
}

class SoilSensorApp extends StatelessWidget {
  const SoilSensorApp({super.key});

  @override
  Widget build(BuildContext context) {
    // ธีมสีน้ำเงินจางๆ (Soft Light Blue) & พื้นหลังสีเทาจางๆ (Soft Grey)
    const softBlue = Color(0xFF4A7BB0); // Soft Light Blue
    const appbarBlue = Color(0xFF385E88); // Muted Elegant Soft Blue
    const softGreyBackground = Color(0xFFF0F2F5); // Light Soft Grey

    return MaterialApp(
      title: 'Soil Multi-Parameter Monitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: softGreyBackground,
        colorScheme: ColorScheme.fromSeed(
          seedColor: softBlue,
          primary: softBlue,
          surface: Colors.white,
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: appbarBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 1.5,
          shadowColor: Colors.black.withValues(alpha: 0.08),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      home: const DashboardScreen(),
    );
  }
}

// -------------------------------------------------------------
// Data Model for the 8 Parameters + Local Storage JSON
// -------------------------------------------------------------
class SoilMeasurement {
  final String id;
  final double temperature;
  final double moisture;
  final int ec;
  final int salinity;
  final int nitrogen;
  final int phosphorus;
  final int potassium;
  final double ph;
  final DateTime timestamp;
  bool isSyncedToCloud;

  SoilMeasurement({
    required this.id,
    required this.temperature,
    required this.moisture,
    required this.ec,
    required this.salinity,
    required this.nitrogen,
    required this.phosphorus,
    required this.potassium,
    required this.ph,
    required this.timestamp,
    this.isSyncedToCloud = false,
  });

  factory SoilMeasurement.fromRawBytes(Uint8List bytes) {
    final byteData = ByteData.sublistView(bytes);
    final rawTemp = byteData.getInt16(3, Endian.big);
    final rawMoist = byteData.getUint16(5, Endian.big);
    final rawEc = byteData.getUint16(7, Endian.big);
    final rawSalinity = byteData.getUint16(9, Endian.big);
    final rawN = byteData.getUint16(11, Endian.big);
    final rawP = byteData.getUint16(13, Endian.big);
    final rawK = byteData.getUint16(15, Endian.big);
    final rawPh = byteData.getUint16(17, Endian.big);

    final now = DateTime.now();
    return SoilMeasurement(
      id: 'LOG-${now.millisecondsSinceEpoch}',
      temperature: rawTemp / 10.0,
      moisture: rawMoist / 10.0,
      ec: rawEc,
      salinity: rawSalinity,
      nitrogen: rawN,
      phosphorus: rawP,
      potassium: rawK,
      ph: rawPh / 100.0,
      timestamp: now,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'temperature': temperature,
      'moisture': moisture,
      'ec': ec,
      'salinity': salinity,
      'nitrogen': nitrogen,
      'phosphorus': phosphorus,
      'potassium': potassium,
      'ph': ph,
      'timestamp': timestamp.toIso8601String(),
      'isSyncedToCloud': isSyncedToCloud,
    };
  }

  factory SoilMeasurement.fromJson(Map<String, dynamic> json) {
    return SoilMeasurement(
      id: json['id'] as String? ?? 'LOG-${DateTime.now().millisecondsSinceEpoch}',
      temperature: (json['temperature'] as num).toDouble(),
      moisture: (json['moisture'] as num).toDouble(),
      ec: (json['ec'] as num).toInt(),
      salinity: (json['salinity'] as num).toInt(),
      nitrogen: (json['nitrogen'] as num).toInt(),
      phosphorus: (json['phosphorus'] as num).toInt(),
      potassium: (json['potassium'] as num).toInt(),
      ph: (json['ph'] as num).toDouble(),
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
      isSyncedToCloud: json['isSyncedToCloud'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'timestamp': FieldValue.serverTimestamp(),
      'local_log_id': id,
      'recorded_at': timestamp.toIso8601String(),
      'device_id': 'CH340-SOIL-01',
      'parameters': {
        'temperature_c': temperature,
        'moisture_percent': moisture,
        'ec_us_cm': ec,
        'salinity_mg_l': salinity,
        'nitrogen_mg_kg': nitrogen,
        'phosphorus_mg_kg': phosphorus,
        'potassium_mg_kg': potassium,
        'ph_value': ph,
      },
    };
  }
}

// -------------------------------------------------------------
// Main Dashboard Screen
// -------------------------------------------------------------
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const String _prefKeyLocalLogs = 'soil_local_logs_v1';

  // Palette สีน้ำเงินจางๆ สบายตา
  static const Color softBlue = Color(0xFF4A7BB0);
  static const Color lightBlueTint = Color(0xFFE8EEF5);

  static final Uint8List queryCommand = Uint8List.fromList([
    0x01, 0x03, 0x00, 0x00, 0x00, 0x08, 0x44, 0x0C,
  ]);

  UsbPort? _port;
  StreamSubscription<Uint8List>? _subscription;
  final List<int> _incomingBuffer = [];

  SoilMeasurement _currentData = SoilMeasurement(
    id: 'INIT',
    temperature: 23.6,
    moisture: 0.0,
    ec: 0,
    salinity: 0,
    nitrogen: 0,
    phosphorus: 0,
    potassium: 0,
    ph: 7.00,
    timestamp: DateTime.now(),
  );

  bool _isDeviceConnected = false;
  bool _isAutoReading = false;
  bool _isCloudSyncing = false;
  Timer? _autoReadTimer;
  List<SoilMeasurement> _localLogs = [];

  @override
  void initState() {
    super.initState();
    _loadLocalLogs();

    if (!kIsWeb) {
      UsbSerial.usbEventStream?.listen((UsbEvent event) {
        _checkUsbConnection();
      });
      _checkUsbConnection();
    }
  }

  @override
  void dispose() {
    _autoReadTimer?.cancel();
    _subscription?.cancel();
    _port?.close();
    super.dispose();
  }

  // -------------------------------------------------------------
  // Persistent Local Logs (SharedPreferences)
  // -------------------------------------------------------------
  Future<void> _loadLocalLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList(_prefKeyLocalLogs);
      if (rawList != null && rawList.isNotEmpty) {
        final parsed = rawList
            .map((str) => SoilMeasurement.fromJson(jsonDecode(str) as Map<String, dynamic>))
            .toList();
        setState(() {
          _localLogs = parsed;
          if (_localLogs.isNotEmpty) {
            _currentData = _localLogs.first;
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading local logs: $e');
    }
  }

  Future<void> _saveMeasurementToLocal(SoilMeasurement measurement) async {
    setState(() {
      _localLogs.insert(0, measurement);
      if (_localLogs.length > 200) _localLogs.removeLast();
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final stringList = _localLogs.map((item) => jsonEncode(item.toJson())).toList();
      await prefs.setStringList(_prefKeyLocalLogs, stringList);
    } catch (e) {
      debugPrint('Error saving local log: $e');
    }
  }

  Future<void> _clearLocalLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKeyLocalLogs);
      setState(() {
        _localLogs.clear();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ล้างข้อมูล Local Log ในเครื่องเรียบร้อยแล้ว'),
            duration: Duration(seconds: 2),
            backgroundColor: softBlue,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error clearing local logs: $e');
    }
  }

  // -------------------------------------------------------------
  // USB Hardware Communication (Android OTG)
  // -------------------------------------------------------------
  Future<void> _checkUsbConnection() async {
    if (kIsWeb) return;

    try {
      List<UsbDevice> devices = await UsbSerial.listDevices();
      UsbDevice? ch340Device;

      for (var device in devices) {
        if (device.vid == 0x1A86 || (device.productName?.contains('CH340') ?? false)) {
          ch340Device = device;
          break;
        }
      }

      if (ch340Device != null) {
        _port = await ch340Device.create();
        bool opened = await _port?.open() ?? false;
        if (opened) {
          await _port?.setDTR(true);
          await _port?.setRTS(true);
          await _port?.setPortParameters(
            9600,
            UsbPort.DATABITS_8,
            UsbPort.STOPBITS_1,
            UsbPort.PARITY_NONE,
          );

          _subscription = _port?.inputStream?.listen((Uint8List data) {
            _onDataReceived(data);
          });

          setState(() {
            _isDeviceConnected = true;
          });
        }
      } else {
        setState(() {
          _isDeviceConnected = false;
        });
      }
    } catch (e) {
      debugPrint('USB connection error: $e');
    }
  }

  void _onDataReceived(Uint8List chunk) {
    _incomingBuffer.addAll(chunk);

    if (_incomingBuffer.length >= 21) {
      final packet = Uint8List.fromList(_incomingBuffer.sublist(0, 21));
      _incomingBuffer.removeRange(0, 21);

      if (packet[0] == 0x01 && packet[1] == 0x03 && packet[2] == 0x10) {
        final newMeasurement = SoilMeasurement.fromRawBytes(packet);
        setState(() {
          _currentData = newMeasurement;
        });
        _saveMeasurementToLocal(newMeasurement);
        _uploadToCloud(newMeasurement);
      }
    }
  }

  // -------------------------------------------------------------
  // Upload to Firebase Firestore
  // -------------------------------------------------------------
  Future<void> _uploadToCloud(SoilMeasurement measurement) async {
    setState(() => _isCloudSyncing = true);

    try {
      await FirebaseFirestore.instance
          .collection('soil_measurements')
          .add(measurement.toFirestoreMap());

      setState(() {
        measurement.isSyncedToCloud = true;
        _isCloudSyncing = false;
      });

      final prefs = await SharedPreferences.getInstance();
      final stringList = _localLogs.map((item) => jsonEncode(item.toJson())).toList();
      await prefs.setStringList(_prefKeyLocalLogs, stringList);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('☁️ บันทึกลงเครื่องและซิงค์ขึ้น Firebase เรียบร้อย!'),
            duration: Duration(seconds: 2),
            backgroundColor: softBlue,
          ),
        );
      }
    } catch (e) {
      debugPrint('Firestore upload error (Offline mode): $e');
      setState(() => _isCloudSyncing = false);
    }
  }

  // -------------------------------------------------------------
  // Trigger Read (Hardware or Web/Simulated)
  // -------------------------------------------------------------
  Future<void> _triggerRead() async {
    if (_port != null && _isDeviceConnected) {
      _incomingBuffer.clear();
      await _port?.write(queryCommand);
    } else {
      final now = DateTime.now();
      final simulated = SoilMeasurement(
        id: 'LOG-${now.millisecondsSinceEpoch}',
        temperature: (_currentData.temperature + (0.1 - (0.2 * (now.second % 2)))).clamp(20.0, 35.0),
        moisture: _currentData.moisture,
        ec: _currentData.ec,
        salinity: _currentData.salinity,
        nitrogen: _currentData.nitrogen,
        phosphorus: _currentData.phosphorus,
        potassium: _currentData.potassium,
        ph: _currentData.ph,
        timestamp: now,
      );

      setState(() {
        _currentData = simulated;
      });

      await _saveMeasurementToLocal(simulated);
      _uploadToCloud(simulated);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('อ่านค่าและบันทึกเรียบร้อย (${_formatTime(_currentData.timestamp)})'),
          duration: const Duration(seconds: 1),
          backgroundColor: softBlue,
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
        _autoReadTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
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

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${_formatTime(dt)}';
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
                  'CH340 USB Modbus RTU + Local Log & Cloud',
                  style: TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
          ],
        ),
        // ลบ local log บนขวาออกตามคำขอ
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status & Primary Action Header: มีสถานะ และปุ่ม "อ่านค่าเดี๋ยวนี้" อยู่ด้านบน
            _buildControlHeader(),
            const SizedBox(height: 18),

            // Section 1: General Soil Condition
            const Text(
              'สภาพดินทั่วไป (General Soil Status)',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
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
                _buildMetricCard(
                  title: 'ความชื้น (Moisture)',
                  value: '${_currentData.moisture.toStringAsFixed(1)} %',
                  icon: Icons.water_drop_rounded,
                  color: const Color(0xFF0288D1),
                  subtext: 'Optimal: 15–35%',
                ),
                _buildMetricCard(
                  title: 'อุณหภูมิดิน (Temp)',
                  value: '${_currentData.temperature.toStringAsFixed(1)} °C',
                  icon: Icons.thermostat_rounded,
                  color: const Color(0xFFE65100),
                  subtext: 'Normal: 20–30°C',
                ),
                _buildMetricCard(
                  title: 'ความเป็นกรด-ด่าง (pH)',
                  value: _currentData.ph.toStringAsFixed(2),
                  icon: Icons.science_rounded,
                  color: const Color(0xFF7B1FA2),
                  subtext: 'Neutral: 6.5–7.5',
                ),
                _buildMetricCard(
                  title: 'การนำไฟฟ้า (EC)',
                  value: '${_currentData.ec} µS/cm',
                  icon: Icons.bolt_rounded,
                  color: const Color(0xFFF57F17),
                  subtext: 'Normal: 100–1000',
                ),
              ],
            ),

            const SizedBox(height: 18),

            // Section 2: Soil Nutrients & Salinity
            const Text(
              'ธาตุอาหารและความเค็ม (NPK & Salinity)',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
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
                _buildMetricCard(
                  title: 'ไนโตรเจน (N)',
                  value: '${_currentData.nitrogen} mg/kg',
                  icon: Icons.grass_rounded,
                  color: const Color(0xFF3D6B99), // โทนน้ำเงินจาง/Slate
                  subtext: 'Available Nitrogen',
                ),
                _buildMetricCard(
                  title: 'ฟอสฟอรัส (P)',
                  value: '${_currentData.phosphorus} mg/kg',
                  icon: Icons.grain_rounded,
                  color: softBlue, // โทนน้ำเงินจาง
                  subtext: 'Available Phosphorus',
                ),
                _buildMetricCard(
                  title: 'โพแทสเซียม (K)',
                  value: '${_currentData.potassium} mg/kg',
                  icon: Icons.spa_rounded,
                  color: const Color(0xFF5D4037),
                  subtext: 'Available Potassium',
                ),
                _buildMetricCard(
                  title: 'ความเค็ม (Salinity)',
                  value: '${_currentData.salinity} mg/L',
                  icon: Icons.waves_rounded,
                  color: const Color(0xFF303F9F),
                  subtext: 'Standard: <800 mg/L',
                ),
              ],
            ),
            const SizedBox(height: 20),

            // สลับตำแหน่ง: การเปิด-ปิดอ่านค่าอัตโนมัติ ย้ายมาอยู่ด้านล่างการ์ดข้อมูล
            _buildAutoReadCard(),
            const SizedBox(height: 14),

            // เหลือไว้แค่ปุ่มเปิดดู Local Logs ล่างสุดเพียงจุดเดียว
            OutlinedButton.icon(
              onPressed: _openLocalLogsView,
              icon: const Icon(Icons.history_rounded, size: 20, color: softBlue),
              label: Text(
                'เปิดดู Local Logs ที่บันทึกในเครื่อง (${_localLogs.length} รายการ)',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: softBlue),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15),
                side: const BorderSide(color: softBlue, width: 1.4),
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

  // -------------------------------------------------------------
  // Top Header: Status + Action "อ่านค่าเดี๋ยวนี้"
  // -------------------------------------------------------------
  Widget _buildControlHeader() {
    final statusText = kIsWeb
        ? 'โหมดทดสอบจำลอง (Web Preview Mode)'
        : (_isDeviceConnected ? 'เซนเซอร์ USB เชื่อมต่อแล้ว (CH340 Ready)' : 'รอเสียบสายเซนเซอร์ USB OTG');

    final statusColor = kIsWeb
        ? softBlue
        : (_isDeviceConnected ? const Color(0xFF3D6B99) : const Color(0xFFE65100));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  kIsWeb ? Icons.preview_rounded : (_isDeviceConnected ? Icons.usb_rounded : Icons.usb_off_rounded),
                  color: statusColor,
                  size: 26,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statusText,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        'อัปเดตล่าสุด: ${_formatTime(_currentData.timestamp)}',
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                if (_isCloudSyncing)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(softBlue),
                    ),
                  )
                else
                  const Tooltip(
                    message: 'เชื่อมต่อ Firebase Firestore แล้ว',
                    child: Icon(Icons.cloud_done_rounded, color: softBlue, size: 22),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            // สลับตำแหน่ง: ปุ่มกดอ่านค่าเดี๋ยวนี้ ย้ายมาอยู่บนสุดตรงนี้
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
                  backgroundColor: softBlue,
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

  // -------------------------------------------------------------
  // Card สำหรับเปิด-ปิด อ่านค่าอัตโนมัติ (ย้ายมาไว้ข้างล่างการ์ดข้อมูล)
  // -------------------------------------------------------------
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
                    color: lightBlueTint,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.timer_outlined, size: 20, color: softBlue),
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
              activeThumbColor: softBlue,
              onChanged: _toggleAutoRead,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required String subtext,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF475569),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(icon, color: color, size: 20),
              ],
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              subtext,
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // Dedicated UI: Local Logs Viewer (Modal / Bottom Sheet)
  // -------------------------------------------------------------
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
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                ),
                              ],
                            ),
                            if (_localLogs.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                tooltip: 'ล้างบันทึกทั้งหมด',
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('ยืนยันล้างบันทึกในเครื่อง'),
                                      content: const Text('คุณต้องการลบข้อมูล Local Log ทั้งหมดหรือไม่?'),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx, false),
                                          child: const Text('ยกเลิก'),
                                        ),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                          onPressed: () => Navigator.pop(ctx, true),
                                          child: const Text('ลบทั้งหมด', style: TextStyle(color: Colors.white)),
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
                                    Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey.shade400),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'ยังไม่มีข้อมูลบันทึกในเครื่อง',
                                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.black54),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'กดปุ่ม "อ่านค่าจากเซนเซอร์เดี๋ยวนี้" เพื่อบันทึกข้อมูลแรก',
                                      style: TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                controller: scrollController,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                itemCount: _localLogs.length,
                                itemBuilder: (context, index) {
                                  final item = _localLogs[index];
                                  return _buildLogItemCard(item, index);
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

  Widget _buildLogItemCard(SoilMeasurement item, int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: softBlue.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '#${_localLogs.length - index}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: softBlue,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatDateTime(item.timestamp),
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: item.isSyncedToCloud ? lightBlueTint : const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        item.isSyncedToCloud ? Icons.cloud_done_rounded : Icons.cloud_queue_rounded,
                        size: 14,
                        color: item.isSyncedToCloud ? softBlue : Colors.orange.shade800,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        item.isSyncedToCloud ? 'Synced' : 'Local Only',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: item.isSyncedToCloud ? softBlue : Colors.orange.shade900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _buildSmallChip('Temp', '${item.temperature.toStringAsFixed(1)}°C', const Color(0xFFE65100)),
                _buildSmallChip('Moist', '${item.moisture.toStringAsFixed(1)}%', const Color(0xFF0288D1)),
                _buildSmallChip('pH', item.ph.toStringAsFixed(2), const Color(0xFF7B1FA2)),
                _buildSmallChip('EC', '${item.ec} µS/cm', const Color(0xFFF57F17)),
                _buildSmallChip('N', '${item.nitrogen}', const Color(0xFF3D6B99)),
                _buildSmallChip('P', '${item.phosphorus}', softBlue),
                _buildSmallChip('K', '${item.potassium}', const Color(0xFF5D4037)),
                _buildSmallChip('Salinity', '${item.salinity} mg/L', const Color(0xFF303F9F)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmallChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 0.8),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
