import 'package:flutter/widgets.dart';

/// Design tokens from the approved prototype
/// (`design/prototype/index.html`, `<style id="design-tokens">`).
///
/// Only the tokens in use so far are listed; the rest are added as the
/// screens that need them are built.
abstract final class DharaColors {
  static const bg = Color(0xFF06070C);
  static const bgElev = Color(0xFF0D0F18);

  static const text = Color(0xFFF2F4FB);
  static const text2 = Color(0xFFAAB0C6);
  static const text3 = Color(0xFF6D748C);

  static const accent = Color(0xFF8B6CFF);
  static const accent2 = Color(0xFF2AD4F0);
  static const accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, accent2],
  );

  static const stroke = Color(0x1AFFFFFF);
  static const strokeStrong = Color(0x3DFFFFFF);
  static const bad = Color(0xFFFF5D6C);
}

abstract final class DharaMotion {
  static const fast = Duration(milliseconds: 120);
  static const base = Duration(milliseconds: 220);
  static const slow = Duration(milliseconds: 420);

  static const easeOut = Cubic(.16, 1, .3, 1);
}

abstract final class DharaRadii {
  static const sm = 8.0;
  static const md = 14.0;
  static const lg = 20.0;
}
