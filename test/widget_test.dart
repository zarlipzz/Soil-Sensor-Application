import 'package:flutter_test/flutter_test.dart';

import 'package:soil_app/main.dart';
import 'package:soil_app/utils/app_constants.dart';

void main() {
  testWidgets('SoilSensorApp smoke test and title verify', (WidgetTester tester) async {
    await tester.pumpWidget(const SoilSensorApp());
    expect(find.byType(SoilSensorApp), findsOneWidget);
    expect(find.text(AppConstants.appSubtitle), findsOneWidget);
  });
}
