import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soil_app/services/gps_service.dart';

void main() {
  testWidgets('a missing GPS fix stops waiting after four seconds', (
    tester,
  ) async {
    const channel = MethodChannel('flutter.baseflow.com/geolocator');
    final messenger = tester.binding.defaultBinaryMessenger;
    final pendingPosition = Completer<Object?>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      return call.method == 'getCurrentPosition' ? pendingPosition.future : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final gps = GpsService();
    var finished = false;
    final location = gps.getCurrentLocation().then((result) {
      finished = true;
      return result;
    });
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(finished, isFalse);
    await tester.pump(const Duration(seconds: 1));
    expect(finished, isTrue);
    expect(await location, isNull);

    pendingPosition.complete(null);
    await tester.pump();
  });
}
