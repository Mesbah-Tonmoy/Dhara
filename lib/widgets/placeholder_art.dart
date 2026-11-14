import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Artwork drawn from a title's name, for titles that have no poster: the
/// same name always gives the same picture, and nothing is downloaded.
///
/// A port of the prototype's `art()`: a dark two-colour sky, a glow, and
/// one of five scenes (hills, an orbit, shards, a skyline, waves).
class PlaceholderArt extends StatelessWidget {
  const PlaceholderArt({super.key, required this.seed, this.wide = false});

  /// What the picture is made from; a title's name.
  final String seed;

  /// A 16:9 picture (a backdrop or a still) instead of a 2:3 poster.
  final bool wide;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: ClipRect(
      child: CustomPaint(
        painter: _ArtPainter(seed, wide),
        isComplex: true,
        size: Size.infinite,
      ),
    ),
  );
}

/// The 32-bit FNV-1a hash of [text], as the prototype's `hash()`.
int artHash(String text) {
  var hash = 2166136261;
  for (final unit in text.codeUnits) {
    hash = ((hash ^ unit) * 16777619) & _mask;
  }
  return hash;
}

/// The prototype's `rng()` (mulberry32): the same numbers for the same
/// seed, on every machine.
class ArtRandom {
  ArtRandom(int seed) : _seed = seed & _mask;

  int _seed;

  /// The next number, from 0 up to but not including 1.
  double next() {
    _seed = (_seed + 0x6D2B79F5) & _mask;
    var t = _multiply(_seed ^ (_seed >> 15), 1 | _seed);
    t = ((t + _multiply(t ^ (t >> 7), 61 | t)) & _mask) ^ t;
    return ((t ^ (t >> 14)) & _mask) / 4294967296;
  }
}

const _mask = 0xFFFFFFFF;

// The low 32 bits of the product; a 64-bit product that wraps keeps them.
int _multiply(int a, int b) => (a * b) & _mask;

enum ArtScene { horizon, orbit, shards, skyline, waves }

/// What decides a picture, read off the first numbers of its [ArtRandom].
@immutable
class ArtSpec {
  const ArtSpec._({
    required this.hue1,
    required this.hue2,
    required this.hue3,
    required this.scene,
    required this.focalX,
    required this.focalY,
    required this.slanted,
  });

  /// The spec of the picture for [seed], and the random numbers left for
  /// drawing it.
  static (ArtSpec, ArtRandom) of(String seed, {required bool wide}) {
    final random = ArtRandom(artHash(seed));
    final hue1 = _cinematic((random.next() * 360).floor());
    final hue2 = _cinematic((hue1 + 20 + (random.next() * 70).floor()) % 360);
    final hue3 = _cinematic((hue1 + 150 + (random.next() * 90).floor()) % 360);
    final scene = ArtScene.values[(random.next() * 5).floor()];
    // On wide art the bright spot stays right, clear of the text.
    final focalX = wide ? .6 + random.next() * .22 : .28 + random.next() * .44;
    final focalY = .22 + random.next() * .24;
    final slanted = random.next() > .5;
    return (
      ArtSpec._(
        hue1: hue1,
        hue2: hue2,
        hue3: hue3,
        scene: scene,
        focalX: focalX,
        focalY: focalY,
        slanted: slanted,
      ),
      random,
    );
  }

  /// Sky from [hue1] to [hue2]; the glow, the sun and the lights in [hue3].
  final int hue1;
  final int hue2;
  final int hue3;
  final ArtScene scene;

  /// Where the glow sits, as shares of the width and the height.
  final double focalX;
  final double focalY;

  /// Whether the sky's gradient runs corner to corner or straight down.
  final bool slanted;

  // Away from yellow-green, which reads cheap on a dark interface.
  static int _cinematic(int hue) =>
      hue >= 50 && hue <= 160 ? (hue + 135) % 360 : hue;
}

Color _hsl(num hue, double saturation, double lightness, [double alpha = 1]) =>
    HSLColor.fromAHSL(
      alpha,
      hue.toDouble() % 360,
      saturation / 100,
      (lightness / 100).clamp(0, 1),
    ).toColor();

class _ArtPainter extends CustomPainter {
  const _ArtPainter(this.seed, this.wide);

  final String seed;
  final bool wide;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    // Drawn on the prototype's canvas, then scaled to cover the box.
    final w = wide ? 960.0 : 400.0;
    final h = wide ? 540.0 : 600.0;
    final scale = math.max(size.width / w, size.height / h);
    canvas
      ..save()
      ..translate((size.width - w * scale) / 2, (size.height - h * scale) / 2)
      ..scale(scale);
    _paintScene(canvas, w, h);
    canvas.restore();
  }

  void _paintScene(Canvas canvas, double w, double h) {
    final (spec, random) = ArtSpec.of(seed, wide: wide);
    final r = random.next;
    final all = Offset.zero & Size(w, h);
    final cx = w * spec.focalX;
    final cy = h * spec.focalY;

    canvas
      ..drawRect(
        all,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset.zero,
            Offset(spec.slanted ? w : 0, h),
            [_hsl(spec.hue1, 58, 24), _hsl(spec.hue2, 70, 6)],
          ),
      )
      // The glow: a circle in a unit square, stretched over the picture.
      ..save()
      ..scale(w, h)
      ..drawRect(
        const Rect.fromLTWH(0, 0, 1, 1),
        Paint()
          ..shader = ui.Gradient.radial(Offset(spec.focalX, spec.focalY), .62, [
            _hsl(spec.hue3, 90, 58, .62),
            _hsl(spec.hue3, 90, 58, 0),
          ]),
      )
      ..restore();

    void sun(double x, double y, double radius) {
      final halo = radius * 2.4;
      canvas
        ..drawCircle(
          Offset(x, y),
          halo,
          Paint()
            ..shader = ui.Gradient.radial(
              Offset(x, y),
              halo,
              [_hsl(spec.hue3, 96, 70, .5), _hsl(spec.hue3, 96, 70, 0)],
              const [.35, 1],
            ),
        )
        ..drawCircle(
          Offset(x, y),
          radius,
          Paint()
            ..shader = ui.Gradient.radial(
              Offset(x - radius * .2, y - radius * .28),
              radius * 1.5,
              [
                _hsl(spec.hue3, 100, 93),
                _hsl(spec.hue3, 96, 72),
                _hsl(spec.hue3, 88, 52),
              ],
              const [0, .55, 1],
            ),
        );
    }

    if (spec.scene != ArtScene.shards) {
      for (var i = 0; i < 46; i++) {
        final x = r() * w;
        final y = r() * h * .6;
        final radius = .5 + r() * 1.2;
        final opacity = .15 + r() * .6;
        canvas.drawCircle(
          Offset(x, y),
          radius,
          Paint()..color = Color.fromRGBO(255, 255, 255, opacity),
        );
      }
    }

    switch (spec.scene) {
      case ArtScene.horizon:
        sun(cx, cy + h * .1, h * (wide ? .12 : .1));
        for (final (y, saturation, lightness) in const [
          (.56, 30.0, 16.0),
          (.68, 26.0, 10.0),
          (.8, 22.0, 5.0),
        ]) {
          final hill = Path()
            ..moveTo(0, h)
            ..lineTo(0, h * y);
          for (var i = 1; i <= 4; i++) {
            final x = w * i / 4;
            final bend = h * (y + (r() - .5) * .16);
            final end = h * (y + (r() - .5) * .07);
            hill.quadraticBezierTo(x - w / 8, bend, x, end);
          }
          hill
            ..lineTo(w, h)
            ..close();
          canvas.drawPath(
            hill,
            Paint()..color = _hsl(spec.hue2, saturation, lightness),
          );
        }
      case ArtScene.orbit:
        for (var i = 1; i <= 6; i++) {
          canvas.drawCircle(
            Offset(cx, cy),
            h * .09 * i,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = Color.fromRGBO(255, 255, 255, .34 - i * .045),
          );
        }
        sun(cx, cy, h * .1);
        canvas.drawCircle(
          Offset(cx + h * .27, cy + h * .05),
          h * .02,
          Paint()..color = const Color(0xFFFFFFFF),
        );
      case ArtScene.shards:
        for (var i = 0; i < 9; i++) {
          final px = cx + (r() - .5) * w * .9;
          final py = cy + (r() - .3) * h * .9;
          final length = h * (.12 + r() * .3);
          final angle = r() * 6.28;
          final shard = Path();
          for (final (index, turn) in const [0.0, 2.1, 4.2].indexed) {
            final x = px + math.cos(angle + turn) * length;
            final y = py + math.sin(angle + turn) * length * (.5 + r());
            if (index == 0) {
              shard.moveTo(x, y);
            } else {
              shard.lineTo(x, y);
            }
          }
          shard.close();
          final lightness = 55 + r() * 20;
          final opacity = .1 + r() * .26;
          canvas.drawPath(
            shard,
            Paint()
              ..color = _hsl(
                i.isOdd ? spec.hue3 : spec.hue1,
                85,
                lightness,
                opacity,
              ),
          );
        }
      case ArtScene.skyline:
        sun(cx, cy, h * .075);
        for (var x = -10.0; x < w;) {
          final width = (wide ? 34 : 26) + r() * (wide ? 70 : 46);
          final height = h * (.16 + r() * .36);
          canvas.drawRect(
            Rect.fromLTWH(x, h - height, width, height),
            Paint()..color = _hsl(spec.hue2, 45, 4 + r() * 5),
          );
          for (var k = 0; k < 5; k++) {
            if (r() <= .45) continue;
            final left = x + 5 + r() * (width - 14);
            final top = h - height + 8 + r() * (height - 20);
            final opacity = .5 + r() * .5;
            canvas.drawRect(
              Rect.fromLTWH(left, top, 4, 6),
              Paint()..color = _hsl(spec.hue3, 95, 72, opacity),
            );
          }
          x += width + 2;
        }
      case ArtScene.waves:
        sun(cx, h * .4, h * .06);
        for (var i = 0; i < 7; i++) {
          final y = h * (.42 + i * .085);
          final swell = h * (.02 + r() * .035);
          final phase = r() * 6.28;
          final wave = Path()
            ..moveTo(0, h)
            ..lineTo(0, y);
          for (var step = 0; step <= 16; step++) {
            final x = w * step / 16;
            wave.lineTo(x, y + math.sin(x / w * 9 + phase) * swell);
          }
          wave
            ..lineTo(w, h)
            ..close();
          canvas.drawPath(
            wave,
            Paint()..color = _hsl(spec.hue2 + i * 6, 60, 24.0 - i * 3, .7),
          );
        }
    }
  }

  @override
  bool shouldRepaint(_ArtPainter old) => seed != old.seed || wide != old.wide;
}
