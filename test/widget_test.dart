import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:soil_app/main.dart';
import 'package:soil_app/utils/app_constants.dart';

void main() {
  testWidgets('shows history on tap, removes a name, and selects a name', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'soil_measurement_name_history': ['Plot Alpha', 'Plot Beta'],
    });
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const gpsChannel = MethodChannel('flutter.baseflow.com/geolocator');
    messenger.setMockMethodCallHandler(gpsChannel, (_) async => false);
    addTearDown(() => messenger.setMockMethodCallHandler(gpsChannel, null));

    await tester.pumpWidget(const SoilSensorApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.text('Plot Alpha').hitTestable(), findsOneWidget);

    await tester.tap(find.byTooltip('ลบชื่อ Plot Alpha จากประวัติ'));
    await tester.pumpAndSettle();
    expect(find.text('Plot Alpha'), findsNothing);

    await tester.tap(find.text('Plot Beta').hitTestable());
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'Plot Beta');
  });

  testWidgets('SoilSensorApp smoke test and title verify', (WidgetTester tester) async {
    await tester.pumpWidget(const SoilSensorApp());
    expect(find.byType(SoilSensorApp), findsOneWidget);
    expect(find.text(AppConstants.appSubtitle), findsOneWidget);
  });
}
