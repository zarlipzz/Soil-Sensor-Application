import 'dart:async';

import '../models/soil_measurement.dart';

enum MeasurementEngineStatus { idle, collecting, completed, timedOut, cancelled }

/// Collects exactly ten valid samples for one user-initiated measurement.
class MeasurementEngine {
  MeasurementEngine({
    this.sampleTarget = 10,
    this.timeout = const Duration(seconds: 30),
    DateTime Function()? clock,
  })  : _clock = clock ?? DateTime.now,
        assert(sampleTarget > 0);

  final int sampleTarget;
  final Duration timeout;
  final DateTime Function() _clock;
  final List<SoilSample> _samples = [];
  Timer? _timeoutTimer;
  MeasurementEngineStatus _status = MeasurementEngineStatus.idle;

  MeasurementEngineStatus get status => _status;
  bool get isCollecting => _status == MeasurementEngineStatus.collecting;
  List<SoilSample> get rawSamples => List.unmodifiable(_samples);

  void start({required void Function() onTimeout}) {
    if (isCollecting) return;
    _timeoutTimer?.cancel();
    _samples.clear();
    _status = MeasurementEngineStatus.collecting;
    _timeoutTimer = Timer(timeout, () {
      if (!isCollecting) return;
      _status = MeasurementEngineStatus.timedOut;
      onTimeout();
    });
  }

  /// Invalid or incomplete samples are ignored and do not count toward ten.
  List<SoilSample>? addSample(SoilSample sample) {
    if (!isCollecting || !sample.isComplete) return null;
    _samples.add(sample);
    if (_samples.length != sampleTarget) return null;
    _timeoutTimer?.cancel();
    _status = MeasurementEngineStatus.completed;
    return List.unmodifiable(_samples);
  }

  void cancel() {
    _timeoutTimer?.cancel();
    if (isCollecting) _status = MeasurementEngineStatus.cancelled;
  }

  DateTime get completedAt => _clock();

  void dispose() => _timeoutTimer?.cancel();
}
