import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soil_app/widgets/sensor_card.dart';

void main() {
  testWidgets('places a sensor unit in the bottom-right of its card', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 180,
          height: 120,
          child: SensorCard(
            title: 'EC',
            value: '123 µS/cm',
            icon: Icons.bolt,
            color: Colors.blue,
            subtext: 'Normal range',
          ),
        ),
      ),
    ));

    final card = tester.getRect(find.byType(Card));
    final unit = tester.getRect(find.byKey(const Key('sensor-unit-EC')));
    // Card contributes a 4px outer margin around its 10px internal padding.
    expect(unit.right, closeTo(card.right - 14, 1));
    expect(unit.bottom, closeTo(card.bottom - 12, 1));
    expect(tester.takeException(), isNull);
  });
}
