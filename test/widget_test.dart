import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:soil_app/main.dart';
import 'package:soil_app/utils/app_constants.dart';
import 'package:soil_app/widgets/sensor_card.dart';

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

  testWidgets('phone cards keep labels, values and units clear in both orientations', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const gpsChannel = MethodChannel('flutter.baseflow.com/geolocator');
    const networkChannel = MethodChannel('com.soil.sensor.soil_app/network');
    messenger.setMockMethodCallHandler(gpsChannel, (_) async => false);
    messenger.setMockMethodCallHandler(networkChannel, (_) async => null);
    addTearDown(() {
      messenger.setMockMethodCallHandler(gpsChannel, null);
      messenger.setMockMethodCallHandler(networkChannel, null);
      tester.view.reset();
    });
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 12);

    for (final size in [const Size(360, 800), const Size(800, 360)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(const SoilSensorApp());
      await tester.pumpAndSettle();

      final button = find.byKey(const ValueKey('phone-measure-button'));
      final buttonRect = tester.getRect(button);
      final cards = find.byType(SensorCard);
      expect(cards, findsNWidgets(8));
      for (var index = 0; index < 8; index++) {
        final card = cards.at(index);
        final metric = tester.widget<SensorCard>(card);
        expect(tester.getRect(card).overlaps(buttonRect), isFalse);
        final titleLabel = size.width > size.height
            ? '(${metric.abbreviation})'
            : '(${metric.abbreviation}) ${metric.title}';
        final title = find.descendant(of: card, matching: find.text(titleLabel));
        final icon = find.descendant(
          of: card,
          matching: find.byIcon(metric.icon),
        );
        expect(tester.getRect(title).overlaps(tester.getRect(icon)), isFalse);
        final value = find.descendant(of: card, matching: find.text(metric.value));
        final unit = find.byKey(Key('sensor-unit-${metric.title}'));
        expect(tester.getRect(value).bottom, lessThanOrEqualTo(tester.getRect(unit).top));
      }
      expect(tester.takeException(), isNull);
    }

    tester.view.physicalSize = const Size(1000, 600);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('phone-measure-button')), findsNothing);
    expect(
      tester.widgetList<SensorCard>(find.byType(SensorCard)).every(
        (card) => !card.compact,
      ),
      isTrue,
    );
  });
}
