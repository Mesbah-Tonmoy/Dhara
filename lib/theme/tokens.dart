/// Design tokens from the approved prototype
/// (`design/prototype/index.html`, `<style id="design-tokens">`).
///
/// The prototype measures in `rem`, and one rem is [rem] pixels in a window
/// 1280 wide. Every size here is in those pixels; `DharaScale` enlarges the
/// whole interface on wider windows, so nothing here depends on the window.
///
/// `test/theme/tokens_test.dart` reads the prototype and checks that these
/// values are still the ones it declares.
library;

import 'package:flutter/widgets.dart';

/// One `rem` of the prototype, in logical pixels at a window width of 1280.
const rem = 15.0;

abstract final class DharaColors {
  static const bg = Color(0xFF06070C);
  static const bgElev = Color(0xFF0D0F18);

  static const text = Color(0xFFF2F4FB);
  static const text2 = Color(0xFFAAB0C6);
  static const text3 = Color(0xFF6D748C);

  static const accent = Color(0xFF8B6CFF);
  static const accent2 = Color(0xFF2AD4F0);
  static const onAccent = Color(0xFFFFFFFF);
  static const accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, accent2],
  );

  static const accentSoftGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x6B8B6CFF), Color(0x382AD4F0)],
  );

  /// Border of a selected chip or toggled control.
  static const accentStroke = Color(0xB38B6CFF);

  static const surface = Color(0x0FFFFFFF);
  static const surface2 = Color(0x1CFFFFFF);

  /// Panels that blur what is behind them: the title bar once the page has
  /// scrolled, the navigation rail.
  static const glass = Color(0x940C0E18);
  static const glassStrong = Color(0xD60D0F18);

  static const stroke = Color(0x1AFFFFFF);
  static const strokeStrong = Color(0x3DFFFFFF);

  static const good = Color(0xFF3DDC97);
  static const warn = Color(0xFFFFC04D);
  static const bad = Color(0xFFFF5D6C);
}

/// Font families. [ui] and [display] are bundled in `assets/fonts`
/// (declared in `pubspec.yaml`); nothing is fetched.
abstract final class DharaFonts {
  /// Body and interface text.
  static const ui = 'Inter';

  /// Titles and headings.
  static const display = 'Plus Jakarta Sans';

  /// File names and addresses. A font of the system, with stand-ins for
  /// systems that lack it.
  static const mono = 'Cascadia Mono';
  static const monoFallback = ['Consolas', 'monospace'];
}

/// Text sizes, weights and line heights.
abstract final class DharaType {
  static const xs = .72 * rem;
  static const sm = .82 * rem;
  static const md = .95 * rem;
  static const lg = 1.2 * rem;
  static const xl = 1.5 * rem;
  static const xxl = 2.25 * rem;

  /// The size of the largest title (the Home banner) is 4.4% of the window
  /// width, kept between these two.
  static const displayMin = 2.6 * rem;
  static const displayMax = 5.6 * rem;
  static const displayWidthShare = .044;

  /// Letter spacing of display text, as a share of its font size.
  static const displayTracking = -.035;

  static const regular = FontWeight.w400;
  static const medium = FontWeight.w500;
  static const semibold = FontWeight.w600;
  static const bold = FontWeight.w700;
  static const black = FontWeight.w800;

  /// Line heights, as multiples of the font size.
  static const tight = 1.02;
  static const snug = 1.3;
  static const body = 1.55;

  /// The size of the largest title in a window [width] wide, both in the
  /// pixels the interface is laid out in (see `DharaScale`).
  static double display(double width) =>
      (width * displayWidthShare).clamp(displayMin, displayMax);
}

abstract final class DharaSpace {
  static const s1 = .25 * rem;
  static const s2 = .5 * rem;
  static const s3 = .75 * rem;
  static const s4 = 1 * rem;
  static const s5 = 1.5 * rem;
  static const s6 = 2 * rem;
  static const s7 = 3 * rem;
  static const s8 = 4 * rem;
}

abstract final class DharaRadii {
  static const sm = .5 * rem;
  static const md = .875 * rem;
  static const lg = 1.25 * rem;

  /// Fully rounded ends, whatever the height.
  static const pill = 999.0;
}

abstract final class DharaShadows {
  /// Under a poster or a floating panel.
  static const card = [
    BoxShadow(
      color: Color(0x73000000),
      offset: Offset(0, .6 * rem),
      blurRadius: 1.6 * rem,
    ),
  ];

  /// Under a menu, a sheet or a dialog.
  static const pop = [
    BoxShadow(
      color: Color(0x99000000),
      offset: Offset(0, 1.5 * rem),
      blurRadius: 4 * rem,
    ),
  ];

  /// Around the card the pointer or the keyboard is on.
  static const glow = [
    BoxShadow(color: Color(0xB38B6CFF), spreadRadius: 1),
    BoxShadow(
      color: Color(0x806366F1),
      offset: Offset(0, .9 * rem),
      blurRadius: 2.6 * rem,
    ),
  ];

  /// Around a text field that has the keyboard.
  static const focusRing = [
    BoxShadow(color: Color(0x478B6CFF), spreadRadius: .2 * rem),
  ];
}

/// How strongly a glass panel blurs what is behind it (the sigma of the
/// blur).
abstract final class DharaBlur {
  static const glass = 1.4 * rem;
}

abstract final class DharaMotion {
  static const fast = Duration(milliseconds: 120);
  static const base = Duration(milliseconds: 220);
  static const slow = Duration(milliseconds: 420);

  /// The cross-fade between two banners on Home.
  static const hero = Duration(milliseconds: 900);

  /// How long Home shows one banner before the next.
  static const heroInterval = Duration(seconds: 9);

  static const easeOut = Cubic(.16, 1, .3, 1);
  static const easeInOut = Cubic(.65, 0, .35, 1);

  /// How much a card grows under the pointer or the keyboard.
  static const hoverScale = 1.06;
}

/// Fixed measures of the window's layout.
abstract final class DharaLayout {
  static const titleBarHeight = 2.75 * rem;

  /// Left edge of a page's content: clear of the navigation rail.
  static const pageLeft = 6.25 * rem;
  static const pageRight = 3 * rem;

  static const cardGap = 1 * rem;
  static const posterWidth = 11.25 * rem;
  static const wideCardWidth = 20 * rem;
}
