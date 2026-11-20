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

  testWidgets('long numbers scale down without dropping digits or covering units', (
    tester,
  ) async {
    const longValue = '1234567890.12345';
    Future<Rect> renderValue(String value) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 92,
              height: 80,
              child: SensorCard(
                title: 'Conductivity',
                abbreviation: 'EC',
                value: value,
                unit: 'µS/cm',
                icon: Icons.bolt,
                color: Colors.blue,
                valueFontSize: 24,
                compact: true,
              ),
            ),
          ),
        ),
      );
      return tester.getRect(find.text(value));
    }

    final short = await renderValue('12.3');
    final long = await renderValue(longValue);
    final card = tester.getRect(find.byType(Card));
    final unit = tester.getRect(find.text('µS/cm'));
    expect(long.height, lessThan(short.height));
    expect(long.left, greaterThan(card.left));
    expect(long.right, lessThan(card.right));
    expect(long.bottom, lessThanOrEqualTo(unit.top));
    expect(tester.takeException(), isNull);
  });
}
