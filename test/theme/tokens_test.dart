import 'dart:io';

import 'package:dhara/theme/tokens.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The prototype's `<style id="design-tokens">` block as name -> value,
/// without the leading `--`.
Map<String, String> _prototypeTokens() {
  final html = File('design/prototype/index.html').readAsStringSync();
  final start = html.indexOf('<style id="design-tokens">');
  final end = html.indexOf('</style>', start);
  if (start < 0) fail('the prototype has no design-tokens block');
  final css = html
      .substring(start, end)
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  return {
    for (final match in RegExp(r'--([\w-]+):\s*([^;]+);').allMatches(css))
      match[1]!: match[2]!.trim(),
  };
}

/// `#rrggbb` or `rgba(r, g, b, a)` as 0xAARRGGBB.
int _argb(String css) {
  final hex = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(css.trim());
  if (hex != null) return 0xFF000000 | int.parse(hex[1]!, radix: 16);
  final rgba = RegExp(
    r'^rgba\(\s*(\d+),\s*(\d+),\s*(\d+),\s*([\d.]+)\s*\)$',
  ).firstMatch(css.trim());
  if (rgba == null) fail('not a colour: $css');
  final alpha = (double.parse(rgba[4]!) * 255).round();
  return alpha << 24 |
      int.parse(rgba[1]!) << 16 |
      int.parse(rgba[2]!) << 8 |
      int.parse(rgba[3]!);
}

/// The same colour, give or take one step of opacity (how a share like .7
/// is rounded to a byte).
void _expectColor(Color actual, String css, {required String reason}) {
  final got = actual.toARGB32();
  final want = _argb(css);
  expect(got & 0xFFFFFF, want & 0xFFFFFF, reason: '$reason: colour');
  expect((got >>> 24) - (want >>> 24), inInclusiveRange(-1, 1), reason: reason);
}

/// `0`, `12px` or `.5rem` in the pixels of the tokens.
double _length(String css) {
  final value = css.trim();
  if (value == '0') return 0;
  if (value.endsWith('rem')) {
    return double.parse(value.substring(0, value.length - 3)) * rem;
  }
  if (value.endsWith('px')) {
    return double.parse(value.substring(0, value.length - 2));
  }
  fail('not a length: $css');
}

Duration _duration(String css) => css.endsWith('ms')
    ? Duration(milliseconds: int.parse(css.substring(0, css.length - 2)))
    : Duration(seconds: int.parse(css.substring(0, css.length - 1)));

List<double> _numbersIn(String css) => [
  for (final match in RegExp(r'-?\d*\.?\d+').allMatches(css))
    double.parse(match[0]!),
];

/// The parts of a list of shadows, split at the commas outside brackets.
List<String> _topLevelParts(String css) {
  final parts = <String>[];
  var depth = 0;
  var from = 0;
  for (var i = 0; i < css.length; i++) {
    final char = css[i];
    if (char == '(') depth++;
    if (char == ')') depth--;
    if (char == ',' && depth == 0) {
      parts.add(css.substring(from, i).trim());
      from = i + 1;
    }
  }
  return parts..add(css.substring(from).trim());
}

void _expectShadows(List<BoxShadow> actual, String css, String name) {
  final parts = _topLevelParts(css);
  expect(actual, hasLength(parts.length), reason: name);
  for (final (index, part) in parts.indexed) {
    final split = part.indexOf('rgba(');
    final lengths = part
        .substring(0, split)
        .trim()
        .split(RegExp(r'\s+'))
        .map(_length)
        .toList();
    final shadow = actual[index];
    final reason = '$name, shadow ${index + 1}';
    expect(shadow.offset.dx, closeTo(lengths[0], 1e-9), reason: reason);
    expect(shadow.offset.dy, closeTo(lengths[1], 1e-9), reason: reason);
    expect(shadow.blurRadius, closeTo(lengths[2], 1e-9), reason: reason);
    expect(
      shadow.spreadRadius,
      closeTo(lengths.length > 3 ? lengths[3] : 0, 1e-9),
      reason: reason,
    );
    _expectColor(shadow.color, part.substring(split), reason: reason);
  }
}

const _colors = {
  'bg': DharaColors.bg,
  'bg-elev': DharaColors.bgElev,
  'surface': DharaColors.surface,
  'surface-2': DharaColors.surface2,
  'glass': DharaColors.glass,
  'glass-strong': DharaColors.glassStrong,
  'stroke': DharaColors.stroke,
  'stroke-strong': DharaColors.strokeStrong,
  'text': DharaColors.text,
  'text-2': DharaColors.text2,
  'text-3': DharaColors.text3,
  'accent': DharaColors.accent,
  'accent-2': DharaColors.accent2,
  'on-accent': DharaColors.onAccent,
  'good': DharaColors.good,
  'warn': DharaColors.warn,
  'bad': DharaColors.bad,
};

const _gradients = {
  'accent-grad': DharaColors.accentGradient,
  'accent-soft': DharaColors.accentSoftGradient,
};

const _lengths = {
  'fs-xs': DharaType.xs,
  'fs-sm': DharaType.sm,
  'fs-md': DharaType.md,
  'fs-lg': DharaType.lg,
  'fs-xl': DharaType.xl,
  'fs-2xl': DharaType.xxl,
  'sp-1': DharaSpace.s1,
  'sp-2': DharaSpace.s2,
  'sp-3': DharaSpace.s3,
  'sp-4': DharaSpace.s4,
  'sp-5': DharaSpace.s5,
  'sp-6': DharaSpace.s6,
  'sp-7': DharaSpace.s7,
  'sp-8': DharaSpace.s8,
  'r-sm': DharaRadii.sm,
  'r-md': DharaRadii.md,
  'r-lg': DharaRadii.lg,
  'r-pill': DharaRadii.pill,
  'blur': DharaBlur.glass,
  'titlebar-h': DharaLayout.titleBarHeight,
  'page-l': DharaLayout.pageLeft,
  'page-r': DharaLayout.pageRight,
  'gap-card': DharaLayout.cardGap,
  'w-poster': DharaLayout.posterWidth,
  'w-wide': DharaLayout.wideCardWidth,
};

const _numbers = {
  'lh-tight': DharaType.tight,
  'lh-snug': DharaType.snug,
  'lh-body': DharaType.body,
  'hover-scale': DharaMotion.hoverScale,
};

const _weights = {
  'fw-regular': DharaType.regular,
  'fw-medium': DharaType.medium,
  'fw-semibold': DharaType.semibold,
  'fw-bold': DharaType.bold,
  'fw-black': DharaType.black,
};

const _fonts = {
  'font-ui': DharaFonts.ui,
  'font-display': DharaFonts.display,
  'font-mono': DharaFonts.mono,
};

const _durations = {
  'dur-fast': DharaMotion.fast,
  'dur-base': DharaMotion.base,
  'dur-slow': DharaMotion.slow,
  'dur-hero': DharaMotion.hero,
  'hero-interval': DharaMotion.heroInterval,
};

const _curves = {
  'ease-out': DharaMotion.easeOut,
  'ease-in-out': DharaMotion.easeInOut,
};

const _shadows = {
  'shadow-card': DharaShadows.card,
  'shadow-pop': DharaShadows.pop,
  'glow': DharaShadows.glow,
  'focus-ring': DharaShadows.focusRing,
};

/// Checked one by one below.
const _others = {'fs-display', 'display-tracking'};

void main() {
  // Read by the first test that needs it, not while the tests are listed.
  late final tokens = _prototypeTokens();

  test('every token of the prototype has its value in the app', () {
    final covered = {
      ..._colors.keys,
      ..._gradients.keys,
      ..._lengths.keys,
      ..._numbers.keys,
      ..._weights.keys,
      ..._fonts.keys,
      ..._durations.keys,
      ..._curves.keys,
      ..._shadows.keys,
      ..._others,
    };

    expect(tokens.keys.toSet().difference(covered), isEmpty);
    expect(covered.difference(tokens.keys.toSet()), isEmpty);
  });

  test('colours are the prototype\'s', () {
    for (final MapEntry(key: name, value: color) in _colors.entries) {
      _expectColor(color, tokens[name]!, reason: name);
    }
  });

  test('gradients run from top left to bottom right through the '
      'prototype\'s colours', () {
    for (final MapEntry(key: name, value: gradient) in _gradients.entries) {
      final stops = RegExp(
        r'#[0-9a-fA-F]{6}|rgba\([^)]*\)',
      ).allMatches(tokens[name]!).map((match) => match[0]!).toList();

      expect(tokens[name], startsWith('linear-gradient(135deg'));
      expect(gradient.begin, Alignment.topLeft);
      expect(gradient.end, Alignment.bottomRight);
      expect(gradient.colors, hasLength(stops.length), reason: name);
      for (final (index, stop) in stops.indexed) {
        _expectColor(gradient.colors[index], stop, reason: '$name $index');
      }
    }
  });

  test('sizes, spacing, radii and layout are the prototype\'s, at $rem '
      'pixels a rem', () {
    for (final MapEntry(key: name, value: pixels) in _lengths.entries) {
      expect(pixels, closeTo(_length(tokens[name]!), 1e-9), reason: name);
    }
  });

  test('line heights and the hover scale are the prototype\'s', () {
    for (final MapEntry(key: name, value: number) in _numbers.entries) {
      expect(number, double.parse(tokens[name]!), reason: name);
    }
  });

  test('font weights are the prototype\'s', () {
    for (final MapEntry(key: name, value: weight) in _weights.entries) {
      expect(weight.value, int.parse(tokens[name]!), reason: name);
    }
  });

  test('each font stack starts with the family the app uses', () {
    for (final MapEntry(key: name, value: family) in _fonts.entries) {
      expect(tokens[name], startsWith('"$family"'), reason: name);
    }
  });

  test('durations and curves are the prototype\'s', () {
    for (final MapEntry(key: name, value: duration) in _durations.entries) {
      expect(duration, _duration(tokens[name]!), reason: name);
    }
    for (final MapEntry(key: name, value: curve) in _curves.entries) {
      expect(tokens[name], startsWith('cubic-bezier('), reason: name);
      expect(
        [curve.a, curve.b, curve.c, curve.d],
        _numbersIn(tokens[name]!),
        reason: name,
      );
    }
  });

  test('shadows are the prototype\'s', () {
    for (final MapEntry(key: name, value: shadows) in _shadows.entries) {
      _expectShadows(shadows, tokens[name]!, name);
    }
  });

  test('the largest title is a share of the window width between two '
      'sizes', () {
    final parts = RegExp(
      r'^clamp\(([\d.]+rem),\s*([\d.]+)vw,\s*([\d.]+rem)\)$',
    ).firstMatch(tokens['fs-display']!)!;

    expect(DharaType.displayMin, closeTo(_length(parts[1]!), 1e-9));
    expect(
      DharaType.displayWidthShare,
      closeTo(double.parse(parts[2]!) / 100, 1e-9),
    );
    expect(DharaType.displayMax, closeTo(_length(parts[3]!), 1e-9));

    expect(DharaType.display(600), DharaType.displayMin);
    expect(DharaType.display(1280), closeTo(56.32, 1e-9));
    expect(DharaType.display(4000), DharaType.displayMax);
  });

  test('display text is set as tight as in the prototype', () {
    final tracking = tokens['display-tracking']!;

    expect(tracking, endsWith('em'));
    expect(
      DharaType.displayTracking,
      double.parse(tracking.substring(0, tracking.length - 2)),
    );
  });
}
