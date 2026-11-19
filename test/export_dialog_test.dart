import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soil_app/models/soil_measurement.dart';
import 'package:soil_app/widgets/export_dialog.dart';

SoilMeasurement record(String name, int day) => SoilMeasurement(
  id: '$day',
  measurementName: name,
  timestamp: DateTime(2026, 11, day),
  temperature: 20,
  moisture: 30,
  ec: 40,
  salinity: 50,
  nitrogen: 1,
  phosphorus: 2,
  potassium: 3,
  ph: 6.5,
);

void main() {
  testWidgets('export shows dates for the selected measurements', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
            records: [
              record('แปลง A', 1),
              record('แปลง B', 2),
              record('แปลง B', 3),
            ],
          ),
        ),
      ),
    );

    Future<void> tap(String label) async {
      final target = find.text(label);
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    final noSelection = find.text('ส่งออก 0 รายการ');
    await tap('ทั้งหมด (3 รายการ)');
    expect(noSelection, findsOneWidget);

    await tap('03/11/2026');
    await tap('แปลง A');
    expect(find.text('01/11/2026'), findsOneWidget);
    expect(find.text('02/11/2026'), findsNothing);
    expect(find.text('03/11/2026'), findsNothing);
    expect(find.text('ส่งออก 1 รายการ (csv)'), findsOneWidget);

    await tap('แปลง B');
    expect(find.text('02/11/2026'), findsOneWidget);
    expect(find.text('03/11/2026'), findsOneWidget);
    expect(find.text('ส่งออก 3 รายการ (csv)'), findsOneWidget);
    await tap('02/11/2026');
    expect(find.text('ส่งออก 1 รายการ (csv)'), findsOneWidget);

    await tap('แปลง B');
    expect(find.text('02/11/2026'), findsNothing);
    expect(find.text('ส่งออก 1 รายการ (csv)'), findsOneWidget);
    await tap('แปลง A');
    expect(find.text('02/11/2026'), findsOneWidget);
    expect(noSelection, findsOneWidget);
    final exportButton = find.ancestor(
      of: noSelection,
      matching: find.byWidgetPredicate((widget) => widget is ElevatedButton),
    );
    expect(tester.widget<ElevatedButton>(exportButton).onPressed, isNull);
  });
}
