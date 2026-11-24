import 'package:flutter/material.dart';

class AppFonts {
  AppFonts._();

  static const primary = 'IBM Plex Sans Thai';
  static const fallback = ['sans-serif'];
  static const _manropeFallback = [primary, ...fallback];

  static const manrope = TextStyle(
    fontFamily: 'Manrope',
    fontFamilyFallback: _manropeFallback,
    fontVariations: [FontVariation.weight(400)],
  );

  static const manropeSemiBold = TextStyle(
    fontFamily: 'Manrope',
    fontFamilyFallback: _manropeFallback,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation.weight(600)],
  );

  static const manropeBold = TextStyle(
    fontFamily: 'Manrope',
    fontFamilyFallback: _manropeFallback,
    fontWeight: FontWeight.bold,
    fontVariations: [FontVariation.weight(700)],
  );
}
