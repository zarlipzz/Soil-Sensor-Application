import 'package:flutter/material.dart';

import '../utils/app_language.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

import '../models/soil_measurement.dart';
import '../services/local_storage_service.dart';
import '../services/map_pin_visibility.dart';
import '../services/gps_service.dart';
import '../utils/measurement_map_utils.dart';
import '../widgets/measurement_group_popup.dart';

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
    _loadFuture = MapPinVisibility.instance.load().then(
      (_) => _storage.loadMeasurements(),
    );
    _startLocationTracking();
  }

  Future<void> _startLocationTracking() async {
    final enabled = await _gpsService.isLocationServiceEnabled();
    if (!enabled || !await _gpsService.requestPermission()) return;
    final loc = await _gpsService.getCurrentLocation();
    if (!mounted) return;
    if (loc != null) {
      setState(() => _currentPosition = LatLng(loc.latitude, loc.longitude));
    }
    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
          ),
        ).listen((position) {
          if (!mounted) return;
          final point = LatLng(position.latitude, position.longitude);
          setState(() => _currentPosition = point);
          _mapController.move(point, 16);
        }, onError: (Object error) {
          debugPrint('[MapScreen] GPS tracking unavailable: $error');
        });
  }

  /// Build markers from measurements that contain GPS and have valid finite coordinates.
  List<Marker> _buildMarkers(List<SoilMeasurement> measurements) {
    final groups = measurementMarkerGroups(
      measurements,
      hiddenMeasurementIds: MapPinVisibility.instance.value,
    );
    final points = measurementGroupMarkerPoints(groups);
    return groups
        .map(
          (group) => Marker(
            point: points[group.key]!,
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
          ),
        )
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
    final LatLng sw = markers
        .map((m) => m.point)
        .reduce(
          (a, b) => LatLng(
            a.latitude < b.latitude ? a.latitude : b.latitude,
            a.longitude < b.longitude ? a.longitude : b.longitude,
          ),
        );
    final LatLng ne = markers
        .map((m) => m.point)
        .reduce(
          (a, b) => LatLng(
            a.latitude > b.latitude ? a.latitude : b.latitude,
            a.longitude > b.longitude ? a.longitude : b.longitude,
          ),
        );
    final bounds = LatLngBounds(sw, ne);
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)),
    );
  }

  /* Retired marker detail bottom-sheet implementation. Marker labels now open
     an anchored overlay.
  /// Bottomโ€‘sheet with measurement details.
  void _showDetailSheet(SoilMeasurement measurement) {
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
              measurement.measurementName.isEmpty
                  ? context.tr('รายละเอียดการวัด', 'Measurement details')
                  : measurement.measurementName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const Divider(),
            Text(context.tr('บันทึกเมื่อ: ${measurement.timestamp}', 'Recorded: ${measurement.timestamp}'),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            _detailRow(context.tr('อุณหภูมิ', 'Temperature'), '${measurement.temperature.toStringAsFixed(2)} °C'),
            _detailRow(context.tr('ความชื้น', 'Moisture'), '${measurement.moisture.toStringAsFixed(1)} %'),
            _detailRow('EC', '${measurement.ec.toStringAsFixed(0)} µS/cm'),
            _detailRow(context.tr('ความเค็ม', 'Salinity'), '${measurement.salinity.toStringAsFixed(0)} mg/L'),
            _detailRow(context.tr('ไนโตรเจน', 'N'), '${measurement.nitrogen.toStringAsFixed(0)} mg/kg'),
            _detailRow(context.tr('ฟอสฟอรัส', 'P'), '${measurement.phosphorus.toStringAsFixed(0)} mg/kg'),
            _detailRow(context.tr('โพแทสเซียม', 'K'), '${measurement.potassium.toStringAsFixed(0)} mg/kg'),
            _detailRow('pH', measurement.ph.toStringAsFixed(2)),
          ],
        ),
      ),
    );
  }

  */

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('แผนที่แปลง', 'Soil Field Map'))),
      body: ListenableBuilder(
        listenable: MapPinVisibility.instance,
        builder: (context, _) => _buildMapBody(),
      ),
    );
  }

  Widget _buildMapBody() => FutureBuilder<List<SoilMeasurement>>(
    future: _loadFuture,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Center(
          child: Text(
            context.tr(
              'โหลดข้อมูลการวัดไม่สำเร็จ: ${snapshot.error}',
              'Error loading measurements: ${snapshot.error}',
            ),
          ),
        );
      }

      final measurements = snapshot.data ?? [];
      final markers = _buildMarkers(measurements);
      if (_currentPosition != null) {
        markers.add(
          Marker(
            point: _currentPosition!,
            width: 40,
            height: 40,
            child: const Icon(Icons.my_location, color: Colors.red, size: 32),
          ),
        );
      }

      // Fit camera after the first frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fitCamera(markers);
      });

      return FlutterMap(
        mapController: _mapController,
        options: const MapOptions(initialCenter: LatLng(0, 0), initialZoom: 2),
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
  );
}
