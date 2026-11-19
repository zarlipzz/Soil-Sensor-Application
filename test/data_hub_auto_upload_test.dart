import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soil_app/models/soil_measurement.dart';
import 'package:soil_app/screens/dashboard_screen.dart';
import 'package:soil_app/services/home_assistant_service.dart';
import 'package:soil_app/services/local_storage_service.dart';
import 'package:soil_app/utils/app_constants.dart';

const networkChannel = MethodChannel('com.soil.sensor.soil_app/network');
const gpsChannel = MethodChannel('flutter.baseflow.com/geolocator');

Future<void> sendNetworkEvent(int? network, {bool? hasInternet}) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        networkChannel.name,
        const StandardMethodCodec().encodeSuccessEnvelope({
          'network': network,
          'hasInternet': hasInternet ?? (network != null),
        }),
        (_) {},
      );
}

Future<HomeAssistantService> openDashboard(
  WidgetTester tester, {
  required bool? autoUpload,
  required Future<http.Response> Function(String id) upload,
}) async {
  SharedPreferences.setMockInitialValues({
    'soil_data_hub_settings': [
      'http://example.test/api/ingest',
      'test-key',
      if (autoUpload != null) autoUpload.toString(),
    ],
    AppConstants.prefKeyLocalLogs: [
      for (final (id, day) in [('newer', 2), ('older', 1)])
        jsonEncode(
          SoilMeasurement(
            id: id,
            deviceId: 'tablet',
            measurementName: 'Plot A',
            temperature: 20,
            moisture: 31,
            ec: 10,
            salinity: 25,
            nitrogen: 1,
            phosphorus: 2,
            potassium: 3,
            ph: 7,
            timestamp: DateTime(2026, 11, day),
          ).toJson(),
        ),
    ],
  });
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(networkChannel, (_) async => null);
  messenger.setMockMethodCallHandler(gpsChannel, (_) async => false);
  final service = HomeAssistantService(
    client: MockClient((request) {
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      return upload(
        payload['readings'][0]['attributes']['local_log_id'] as String,
      );
    }),
  );
  addTearDown(() {
    messenger.setMockMethodCallHandler(networkChannel, null);
    messenger.setMockMethodCallHandler(gpsChannel, null);
    service.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(home: DashboardScreen(dataHubService: service)),
  );
  await tester.pumpAndSettle();
  return service;
}

void main() {
  testWidgets('manual upload is gray offline and enabled when internet returns', (
    tester,
  ) async {
    final sent = <String>[];
    await openDashboard(
      tester,
      autoUpload: false,
      upload: (id) async {
        sent.add(id);
        return http.Response('{}', 202);
      },
    );
    await tester.tap(find.byTooltip('บันทึกในเครื่อง'));
    await tester.pumpAndSettle();
    final label = find.text('ส่งรายการค้าง (2)');
    final button = find.ancestor(
      of: label,
      matching: find.byWidgetPredicate((widget) => widget is FilledButton),
    );
    final offlineButton = tester.widget<FilledButton>(button);
    expect(offlineButton.onPressed, isNull);
    expect(
      offlineButton.style!.backgroundColor!.resolve({WidgetState.disabled}),
      Colors.grey.shade300,
    );
    await tester.tap(label);
    expect(sent, isEmpty);

    await sendNetworkEvent(10, hasInternet: false);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(button).onPressed, isNull);

    await sendNetworkEvent(10);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);

    await sendNetworkEvent(10, hasInternet: false);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(button).onPressed, isNull);

    await sendNetworkEvent(10);
    await tester.pumpAndSettle();
    await tester.tap(label);
    await tester.pumpAndSettle();
    expect(sent, ['older', 'newer']);
  });

  testWidgets('waits seven seconds after reconnect and sends oldest first', (
    tester,
  ) async {
    final sent = <String>[];
    final firstResponse = Completer<http.Response>();
    await openDashboard(
      tester,
      autoUpload: true,
      upload: (id) async {
        sent.add(id);
        return id == 'older' ? firstResponse.future : http.Response('{}', 202);
      },
    );

    await sendNetworkEvent(10);
    await tester.pump(const Duration(seconds: 5));
    await sendNetworkEvent(null);
    await tester.pump(const Duration(seconds: 10));
    expect(sent, isEmpty);

    await sendNetworkEvent(20);
    await tester.pump(const Duration(seconds: 6));
    expect(sent, isEmpty);
    await tester.pump(const Duration(seconds: 1));
    expect(sent, ['older']);

    firstResponse.complete(http.Response('{}', 202));
    await tester.pumpAndSettle();
    expect(sent, ['older', 'newer']);
    expect(
      (await LocalStorageService().loadMeasurements()).every(
        (record) => record.isSyncedToCloud,
      ),
      isTrue,
    );
  });

  testWidgets('Log toggle sits by the filter and saves both upload modes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sent = <String>[];
    final service = await openDashboard(
      tester,
      autoUpload: null,
      upload: (id) async {
        sent.add(id);
        return http.Response('{}', 202);
      },
    );
    await sendNetworkEvent(10);
    await tester.pump(const Duration(seconds: 10));
    expect(sent, isEmpty);

    await tester.tap(find.byTooltip('บันทึกในเครื่อง'));
    await tester.pumpAndSettle();
    final label = find.text('ส่งข้อมูลอัตโนมัติ');
    final toggle = find.byType(Switch);
    final filter = find.byTooltip('ตัวกรอง');
    expect(tester.getCenter(label).dx, lessThan(tester.getCenter(toggle).dx));
    expect(tester.getCenter(toggle).dx, lessThan(tester.getCenter(filter).dx));
    expect(
      tester.getCenter(toggle).dy,
      closeTo(tester.getCenter(filter).dy, 1),
    );
    expect(tester.widget<Switch>(toggle).value, isFalse);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(toggle).value, isTrue);
    expect((await service.loadSettings()).autoUpload, isTrue);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(toggle).value, isFalse);
    expect((await service.loadSettings()).autoUpload, isFalse);
    await tester.pump(const Duration(seconds: 10));
    expect(sent, isEmpty);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    final settings = await service.loadSettings();
    expect(settings.autoUpload, isTrue);
    expect(settings.apiKey, 'test-key');
    await tester.pump(const Duration(seconds: 7));
    expect(sent, ['older', 'newer']);
  });

  testWidgets(
    'leaves failed uploads pending and retries them after reconnect',
    (tester) async {
      final sent = <String>[];
      await openDashboard(
        tester,
        autoUpload: true,
        upload: (id) async {
          sent.add(id);
          return http.Response('{}', sent.length == 1 ? 503 : 202);
        },
      );
      await sendNetworkEvent(10);
      await tester.pump(const Duration(seconds: 7));
      expect(sent, ['older']);
      expect(
        (await LocalStorageService().loadMeasurements()).every(
          (record) => !record.isSyncedToCloud,
        ),
        isTrue,
      );
      await sendNetworkEvent(null);
      await sendNetworkEvent(20);
      await tester.pump(const Duration(seconds: 7));
      expect(sent, ['older', 'older', 'newer']);
    },
  );
}
