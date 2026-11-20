import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soil_app/models/soil_measurement.dart';
import 'package:soil_app/screens/dashboard_screen.dart';
import 'package:soil_app/services/local_storage_service.dart';
import 'package:soil_app/utils/app_constants.dart';
import 'package:soil_app/widgets/measurement_group_popup.dart';

SoilMeasurement record(String name, int day, double longitude) =>
    SoilMeasurement(
      id: '$day',
      measurementName: name,
      timestamp: DateTime(2026, 11, day),
      latitude: 13.75,
      longitude: longitude,
      temperature: 20,
      moisture: 30,
      ec: 40,
      salinity: 50,
      nitrogen: 1,
      phosphorus: 2,
      potassium: 3,
      ph: 6.5,
    );

Future<void> openDashboard(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: DashboardScreen()));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      AppConstants.prefKeyLocalLogs: [
        for (final measurement in [
          record('แปลง B', 3, 104),
          record('แปลง A', 2, 100.52),
          record('แปลง A', 1, 100.52),
        ])
          jsonEncode(measurement.toJson()),
      ],
    });
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const gps = MethodChannel('flutter.baseflow.com/geolocator');
    const network = MethodChannel('com.soil.sensor.soil_app/network');
    messenger.setMockMethodCallHandler(gps, (_) async => false);
    messenger.setMockMethodCallHandler(network, (_) async => null);
    addTearDown(() {
      messenger.setMockMethodCallHandler(gps, null);
      messenger.setMockMethodCallHandler(network, null);
    });
  });

  testWidgets('removes one pin persistently while keeping its local logs', (
    tester,
  ) async {
    await openDashboard(tester);
    Finder pin(String name) => find.byWidgetPredicate(
      (widget) =>
          widget is MeasurementGroupMarkerLabel && widget.group.name == name,
    );
    final pinA = pin('แปลง A');
    expect(pinA.hitTestable(), findsOneWidget);
    expect(pin('แปลง B'), findsOneWidget);

    await tester.tap(pinA.hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('ลบหมุด'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    expect(pinA, findsOneWidget);

    await tester.tap(find.byTooltip('ลบหมุด'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'ลบหมุด'));
    await tester.pumpAndSettle();
    expect(pinA, findsNothing);
    expect(pin('แปลง B'), findsOneWidget);
    expect(await LocalStorageService().loadMeasurements(), hasLength(3));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await openDashboard(tester);
    expect(pinA, findsNothing);
    expect(pin('แปลง B'), findsOneWidget);
  });

  testWidgets('Log confirms a selection from the bottom of the filter panel', (
    tester,
  ) async {
    await openDashboard(tester);
    await tester.tap(find.byTooltip('บันทึกในเครื่อง'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('ตัวกรอง'));
    await tester.pumpAndSettle();

    final confirm = find.ancestor(
      of: find.text('ยืนยัน'),
      matching: find.byWidgetPredicate((widget) => widget is ElevatedButton),
    );
    final filters = find.byKey(const ValueKey('history-filters'));
    final disabled = tester.widget<ElevatedButton>(confirm);
    expect(disabled.onPressed, isNull);
    expect(
      disabled.style!.backgroundColor!.resolve({WidgetState.disabled}),
      Colors.grey.shade300,
    );
    expect(
      tester.getTopLeft(confirm).dy,
      greaterThan(tester.getBottomLeft(filters).dy),
    );

    await tester.tap(find.widgetWithText(FilterChip, 'แปลง A'));
    await tester.pumpAndSettle();
    expect(tester.widget<ElevatedButton>(confirm).onPressed, isNotNull);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.textContaining('แปลง A —'), findsNWidgets(2));
    expect(find.textContaining('แปลง B —'), findsNothing);
  });

  testWidgets('landscape Log can shrink and stays usable with the keyboard', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(802, 360);
    tester.view.padding = const FakeViewPadding(top: 24);
    tester.view.viewPadding = const FakeViewPadding(top: 24);
    addTearDown(tester.view.reset);

    await openDashboard(tester);
    await tester.tap(find.byTooltip('บันทึกในเครื่อง'));
    await tester.pumpAndSettle();
    final results = find.byKey(const ValueKey('history-results'));
    final originalHeight = tester.getSize(results).height;
    final drag = await tester.startGesture(tester.getCenter(results));
    await drag.moveBy(const Offset(0, 25));
    await tester.pump(const Duration(milliseconds: 40));
    await drag.moveBy(const Offset(0, 85));
    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.getSize(results).height, lessThan(originalHeight));
    await drag.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final search = find.descendant(of: results, matching: find.byType(TextField));
    await tester.ensureVisible(search);
    await tester.enterText(search, 'แปลง A');
    tester.view.viewInsets = const FakeViewPadding(bottom: 235);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    tester.testTextInput.hide();
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    final record = find.textContaining('แปลง A —').first;
    await tester.ensureVisible(record);
    expect(record.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
