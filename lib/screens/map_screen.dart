import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../models/soil_measurement.dart';
import '../services/local_storage_service.dart';
import '../services/gps_service.dart';
import 'dart:async';


/// Screen that displays historical soil measurements on an OpenStreetMap map.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // Services
  late final LocalStorageService _storage;
  late Future<List<SoilMeasurement>> _loadFuture;

  // flutter_map controller
  final MapController _mapController = MapController();
  final GpsService _gpsService = GpsService();
  StreamSubscription<Position>? _positionSubscription;
  LatLng? _currentPosition;

  @override
  void initState() {
    super.initState();
    _storage = LocalStorageService();
    _loadFuture = _storage.loadMeasurements();
    _startLocationTracking();
  }

  Future<void> _startLocationTracking() async {
    final enabled = await _gpsService.isLocationServiceEnabled();
    if (!enabled || !await _gpsService.requestPermission()) return;
    final loc = await _gpsService.getCurrentLocation();
    if (mounted && loc != null) setState(() => _currentPosition = LatLng(loc.latitude, loc.longitude));
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
    ).listen((position) {
      if (!mounted) return;
      final point = LatLng(position.latitude, position.longitude);
      setState(() => _currentPosition = point);
      _mapController.move(point, 16);
    });
  }

  /// Build markers from measurements that contain GPS and have valid finite coordinates.
  List<Marker> _buildMarkers(List<SoilMeasurement> measurements) {
    final valid = measurements
        .where((m) =>
            m.latitude != null &&
            m.longitude != null &&
            m.latitude!.isFinite &&
            m.longitude!.isFinite)
        .toList();
    final groups = <({LatLng center, List<SoilMeasurement> logs})>[];
    for (final m in valid) {
      final point = LatLng(m.latitude!, m.longitude!);
      final i = groups.indexWhere((g) => const Distance().as(LengthUnit.Meter, g.center, point) <= 15);
      if (i == -1) { groups.add((center: point, logs: [m])); } else { groups[i].logs.add(m); }
    }
    return groups.map((g) => Marker(
              point: g.center,
              width: 40,
              height: 40,
              // flutter_map 6.x uses a child widget instead of builder.
              child: IconButton(
                icon: const Icon(Icons.location_on, color: Colors.green),
                onPressed: () => _showDetailSheet(g.logs),
              ),
            ))
        .toList();
  }

  /// Fit the map view to the supplied markers.
  Future<void> _fitCamera(List<Marker> markers) async {
    if (markers.isEmpty) {
      // Default world view.
      _mapController.move(const LatLng(0, 0), 2);
      return;
    }
    if (markers.length == 1) {
      _mapController.move(markers.first.point, 15);
      return;
    }
    // Compute bounds using min/max.
    final LatLng sw = markers.map((m) => m.point).reduce((a, b) =>
        LatLng(
            a.latitude < b.latitude ? a.latitude : b.latitude,
            a.longitude < b.longitude ? a.longitude : b.longitude));
    final LatLng ne = markers.map((m) => m.point).reduce((a, b) =>
        LatLng(
            a.latitude > b.latitude ? a.latitude : b.latitude,
            a.longitude > b.longitude ? a.longitude : b.longitude));
    final bounds = LatLngBounds(sw, ne);
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(50),
      ),
    );
  }

  /// Bottomโ€‘sheet with measurement details.
  void _showDetailSheet(List<SoilMeasurement> measurements) {
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
            Text('ข้อมูลหมุดนี้ ${measurements.length} รายการ', style: const TextStyle(fontWeight: FontWeight.bold)),
            const Divider(),
            ...measurements.reversed.map((m) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Recorded: ${m.timestamp}', style: const TextStyle(fontWeight: FontWeight.bold)),
              _detailRow('Temperature', '${m.temperature.toStringAsFixed(1)} °C'),
              _detailRow('Moisture', '${m.moisture.toStringAsFixed(1)} %'),
              _detailRow('EC', '${m.ec} µS/cm'),
              _detailRow('Salinity', '${m.salinity} mg/L'),
              _detailRow('N', '${m.nitrogen} mg/kg'),
              _detailRow('P', '${m.phosphorus} mg/kg'),
              _detailRow('K', '${m.potassium} mg/kg'),
              _detailRow('pH', m.ph.toStringAsFixed(2)),
              const Divider(),
            ])),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  Widget _detailRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Soil Field Map')),
      body: FutureBuilder<List<SoilMeasurement>>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
                child: Text('Error loading measurements: ${snapshot.error}'));
          }

          final measurements = snapshot.data ?? [];
          final markers = _buildMarkers(measurements);
          if (_currentPosition != null) {
            markers.add(Marker(point: _currentPosition!, width: 40, height: 40,
              child: const Icon(Icons.my_location, color: Colors.red, size: 32)));
          }

          // Fit camera after the first frame.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _fitCamera(markers);
          });

          return FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: LatLng(0, 0),
              initialZoom: 2,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.soil_app',
              ),
              const SimpleAttributionWidget(
                source: Text('ยฉ OpenStreetMap contributors'),
                alignment: Alignment.bottomRight,
              ),
              MarkerLayer(markers: markers),
            ],
          );
        },
      ),
    );
  }
}
