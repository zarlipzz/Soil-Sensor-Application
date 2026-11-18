import 'package:flutter/material.dart';

enum CornerCutout { none, topLeft, topRight, bottomLeft, bottomRight }

class CornerCutoutClipper extends CustomClipper<Path> {
  final CornerCutout corner;
  final double radius;
  final double cornerRadius;

  const CornerCutoutClipper({
    required this.corner,
    this.radius = 46.0,
    this.cornerRadius = 12.0,
  });

  @override
  Path getClip(Size size) {
    final rectPath = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width, size.height),
          Radius.circular(cornerRadius),
        ),
      );

    if (corner == CornerCutout.none) return rectPath;

    final circleCenter = switch (corner) {
      CornerCutout.bottomRight => Offset(size.width + 3, size.height + 3),
      CornerCutout.bottomLeft => Offset(-3, size.height + 3),
      CornerCutout.topRight => Offset(size.width + 3, -3),
      CornerCutout.topLeft => Offset(-3, -3),
      CornerCutout.none => Offset.zero,
    };

    final circlePath = Path()
      ..addOval(Rect.fromCircle(center: circleCenter, radius: radius));

    return Path.combine(PathOperation.difference, rectPath, circlePath);
  }

  @override
  bool shouldReclip(covariant CornerCutoutClipper oldClipper) =>
      oldClipper.corner != corner ||
      oldClipper.radius != radius ||
      oldClipper.cornerRadius != cornerRadius;
}

/// Reusable metric card widget for displaying individual soil sensor parameters.
class SensorCard extends StatelessWidget {
  final String title;
  final String value;
  final String? unit;
  final IconData icon;
  final Color color;
  final String? subtext;
  final CornerCutout cornerCutout;
  final double cutoutRadius;
  final bool unitOnRight;
  final double valueFontSize;

  const SensorCard({
    super.key,
    required this.title,
    required this.value,
    this.unit,
    required this.icon,
    required this.color,
    this.subtext,
    this.cornerCutout = CornerCutout.none,
    this.cutoutRadius = 46.0,
    this.unitOnRight = true,
    this.valueFontSize = 34,
  });

  String get _displayUnit => unit ?? _extractUnit(value);
  String get _displayValue => unit != null ? value : _extractNumber(value);

  static String _extractUnit(String raw) {
    final parts = raw.trim().split(RegExp(r'\s+'));
    return parts.length > 1 ? parts.last : '';
  }

  static String _extractNumber(String raw) {
    final parts = raw.trim().split(RegExp(r'\s+'));
    return parts.isNotEmpty ? parts.first : '';
  }

  @override
  Widget build(BuildContext context) {
    // Leave a small gap between content and the inward curve.
    final cutoutInset = cutoutRadius - 12;
    final cardWidget = Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF475569),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Positioned(
                      right: cornerCutout == CornerCutout.topRight
                          ? cutoutInset
                          : 0,
                      child: Icon(icon, color: color, size: 16),
                    ),
                  ],
                ),
                // Enlarged value centered both vertically and horizontally
                Expanded(
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _displayValue,
                        style: TextStyle(
                          fontSize: valueFontSize,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              right: unitOnRight
                  ? (cornerCutout == CornerCutout.bottomRight ? cutoutInset : 0)
                  : null,
              left: unitOnRight
                  ? null
                  : (cornerCutout == CornerCutout.bottomLeft ? cutoutInset : 0),
              bottom: 0,
              child: Text(
                _displayUnit,
                key: Key('sensor-unit-$title'),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
                textAlign: unitOnRight ? TextAlign.right : TextAlign.left,
              ),
            ),
          ],
        ),
      ),
    );

    if (cornerCutout == CornerCutout.none) {
      return cardWidget;
    }

    return ClipPath(
      clipper: CornerCutoutClipper(corner: cornerCutout, radius: cutoutRadius),
      child: cardWidget,
    );
  }
}
