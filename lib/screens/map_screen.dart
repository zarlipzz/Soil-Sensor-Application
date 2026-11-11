import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/soil_measurement.dart';
import '../services/local_storage_service.dart';


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

  @override
  void initState() {
    super.initState();
    _storage = LocalStorageService();
    _loadFuture = _storage.loadMeasurements();
  }

  /// Build markers from measurements that contain GPS and have valid finite coordinates.
  List<Marker> _buildMarkers(List<SoilMeasurement> measurements) {
    return measurements
        .where((m) =>
            m.latitude != null &&
            m.longitude != null &&
            m.latitude!.isFinite &&
            m.longitude!.isFinite)
        .map((m) => Marker(
              point: LatLng(m.latitude!, m.longitude!),
              width: 40,
              height: 40,
              // flutter_map 6.x uses a child widget instead of builder.
              child: IconButton(
                icon: const Icon(Icons.location_on, color: Colors.red),
                onPressed: () => _showDetailSheet(m),
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

  /// Bottom‑sheet with measurement details.
  void _showDetailSheet(SoilMeasurement m) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Recorded: ${m.timestamp}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _detailRow('Temperature', '${m.temperature.toStringAsFixed(1)} °C'),
            _detailRow('Moisture', '${m.moisture.toStringAsFixed(1)} %'),
            _detailRow('EC', '${m.ec} μS/cm'),
            _detailRow('Salinity', '${m.salinity} mg/L'),
            _detailRow('N', '${m.nitrogen} mg/kg'),
            _detailRow('P', '${m.phosphorus} mg/kg'),
            _detailRow('K', '${m.potassium} mg/kg'),
            _detailRow('pH', m.ph.toStringAsFixed(2)),
          ],
        ),
      ),
    );
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

          // Fit camera after the first frame.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _fitCamera(markers);
          });

          if (markers.isEmpty) {
            return Center(
              child: Text('No measurements with GPS data.',
                  style: TextStyle(color: Colors.grey[600])),
            );
          }

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
                source: Text('© OpenStreetMap contributors'),
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
