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
    expect(find.text(AppConstants.appTitle), findsOneWidget);
    expect(find.textContaining(AppConstants.sensorConnectionType), findsNothing);
    expect(tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight, 48);
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
    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 12);

    for (final size in [const Size(360, 800), const Size(800, 360)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(const SoilSensorApp());
      await tester.pumpAndSettle();

      final portrait = size.height > size.width;
      expect(tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight, 44);
      final button = find.byKey(
        ValueKey(portrait ? 'portrait-measure-button' : 'landscape-measure-button'),
      );
      final buttonRect = tester.getRect(button);
      final cards = find.byType(SensorCard);
      expect(cards, findsNWidgets(8));
      if (portrait) {
        expect(buttonRect.size, const Size(120, 58));
        expect(buttonRect.center.dx, closeTo(size.width / 2, 1));
        expect(buttonRect.bottom, closeTo(size.height - 12, 1));
        expect(tester.getRect(cards.last).bottom, lessThan(buttonRect.top));
      } else {
        final nameField = tester.getRect(find.byType(TextField));
        expect(buttonRect.width, 86);
        expect(buttonRect.left, greaterThan(nameField.right));
        expect(buttonRect.center.dy, closeTo(nameField.center.dy, 1));
        expect(buttonRect.bottom, lessThan(tester.getRect(cards.first).top));
      }
      for (var index = 0; index < 8; index++) {
        final card = cards.at(index);
        final metric = tester.widget<SensorCard>(card);
        expect(metric.cornerCutout, CornerCutout.none);
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
    final tabletButton = find.byKey(const ValueKey('landscape-measure-button'));
    final tabletButtonRect = tester.getRect(tabletButton);
    expect(tabletButtonRect.size, const Size(132, 64));
    expect(tabletButtonRect.center.dx, closeTo(500, 1));
    expect(tabletButtonRect.bottom, closeTo(600 - 12, 1));
    expect(
      tester.widgetList<SensorCard>(find.byType(SensorCard)).every(
        (card) => !card.compact,
      ),
      isTrue,
    );
  });

  testWidgets('not ready can rescan USB and request permission again', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const usb = MethodChannel('usb_serial');
    const usbEvents = MethodChannel('usb_serial/usb_events');
    const gps = MethodChannel('flutter.baseflow.com/geolocator');
    const network = MethodChannel('com.soil.sensor.soil_app/network');
    var visible = false;
    var attempts = 0;
    messenger.setMockMethodCallHandler(usb, (call) async {
      if (call.method == 'listDevices') {
        return [
          if (visible)
            {'deviceName': 'CH340', 'vid': 0x1a86, 'pid': 0x7523, 'deviceId': 1},
        ];
      }
      if (call.method == 'create') {
        attempts++;
        throw PlatformException(code: 'usb', message: 'USB permission denied');
      }
      return null;
    });
    messenger.setMockMethodCallHandler(usbEvents, (_) async => null);
    messenger.setMockMethodCallHandler(network, (_) async => null);
    messenger.setMockMethodCallHandler(gps, (_) async => false);
    addTearDown(() {
      for (final channel in [usb, usbEvents, network, gps]) {
        messenger.setMockMethodCallHandler(channel, null);
      }
    });

    await tester.pumpWidget(const SoilSensorApp());
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('landscape-measure-button'));
    final retry = find.text('ลองเชื่อมต่อใหม่');
    expect(attempts, 0);
    visible = true;
    for (var count = 1; count <= 2; count++) {
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text(AppConstants.sensorConnectionType), findsOneWidget);
      if (count == 2) {
        expect(find.textContaining('กรุณาอนุญาตให้แอป'), findsOneWidget);
      }
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(attempts, count);
    }
  });
}
