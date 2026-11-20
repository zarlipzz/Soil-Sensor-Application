import 'package:flutter/material.dart';

import '../utils/app_fonts.dart';

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
  final String? abbreviation;
  final String value;
  final String? unit;
  final IconData icon;
  final Color color;
  final String? subtext;
  final CornerCutout cornerCutout;
  final double cutoutRadius;
  final bool unitOnRight;
  final double valueFontSize;
  final bool compact;

  const SensorCard({
    super.key,
    required this.title,
    this.abbreviation,
    required this.value,
    this.unit,
    required this.icon,
    required this.color,
    this.subtext,
    this.cornerCutout = CornerCutout.none,
    this.cutoutRadius = 46.0,
    this.unitOnRight = true,
    this.valueFontSize = 34,
    this.compact = false,
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
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    if (compact) return _clipCard(_buildCompactCard(isLandscape));
    final shortTitle = abbreviation;
    const titleStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: Color(0xFF475569),
    );
    final titleLabel = Text(
      shortTitle == null ? title : '($shortTitle) $title',
      style: titleStyle,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
    );
    final titleIcon = Icon(icon, color: color, size: 16);
    // Leave a small gap between content and the inward curve.
    final cutoutInset = cutoutRadius - 12;
    final cardWidget = Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isLandscape)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (shortTitle != null)
                        Text('($shortTitle)', style: titleStyle),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(title, style: titleStyle, maxLines: 1),
                      ),
                    ],
                  )
                else
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        child: titleLabel,
                      ),
                      Positioned(
                        right: cornerCutout == CornerCutout.topRight
                            ? cutoutInset
                            : 0,
                        child: titleIcon,
                      ),
                    ],
                  ),
                // Enlarged value centered both vertically and horizontally
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: _valueCornerInset,
                      vertical: _displayUnit.isEmpty ? 0 : 10,
                    ),
                    child: _buildValue(),
                  ),
                ),
              ],
            ),
            if (isLandscape)
              Positioned(
                top: -3,
                right: -4,
                child: Icon(icon, color: color, size: 13),
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
                style: AppFonts.manropeSemiBold.copyWith(
                  fontSize: 10,
                  color: Color(0xFF64748B),
                ),
                textAlign: unitOnRight ? TextAlign.right : TextAlign.left,
              ),
            ),
          ],
        ),
      ),
    );

    return _clipCard(cardWidget);
  }

  Widget _clipCard(Widget card) => cornerCutout == CornerCutout.none
      ? card
      : ClipPath(
          clipper: CornerCutoutClipper(corner: cornerCutout, radius: cutoutRadius),
          child: card,
        );

  double get _valueCornerInset =>
      cornerCutout == CornerCutout.none ? 0 : cutoutRadius * 0.6;

  Widget _buildValue() => Center(
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        _displayValue,
        maxLines: 1,
        softWrap: false,
        style: AppFonts.manropeBold.copyWith(
          color: color,
          fontSize: valueFontSize,
          height: compact ? 1.1 : null,
        ),
      ),
    ),
  );

  Widget _buildCompactCard(bool isLandscape) {
    const titleStyle = TextStyle(
      fontSize: 11,
      height: 1.15,
      fontWeight: FontWeight.w600,
      color: Color(0xFF475569),
    );
    final symbol = Icon(icon, color: color, size: isLandscape ? 11 : 13);
    final abbreviationLabel = abbreviation == null ? null : '($abbreviation)';
    final titleInset = cutoutRadius - 10;
    final unitInset = cornerCutout == CornerCutout.bottomRight ? titleInset : 0.0;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isLandscape) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(abbreviationLabel ?? '', style: titleStyle),
                  ),
                  symbol,
                ],
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(title, style: titleStyle, maxLines: 1),
                ),
              ),
            ] else
              Row(
                children: [
                  if (cornerCutout == CornerCutout.topLeft)
                    SizedBox(width: titleInset),
                  const SizedBox(width: 17),
                  Expanded(
                    child: Text(
                      abbreviationLabel == null
                          ? title
                          : '$abbreviationLabel $title',
                      style: titleStyle,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  symbol,
                  if (cornerCutout == CornerCutout.topRight)
                    SizedBox(width: titleInset),
                ],
              ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: _valueCornerInset),
                child: _buildValue(),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(right: unitInset),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  _displayUnit.isEmpty ? ' ' : _displayUnit,
                  key: Key('sensor-unit-$title'),
                  style: AppFonts.manropeSemiBold.copyWith(
                    fontSize: 9,
                    height: 1.1,
                    color: const Color(0xFF64748B),
                  ),
                  maxLines: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
