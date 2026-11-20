import 'package:dhara/core/settings/settings_controller.dart';
import 'package:dhara/theme/logo_style.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:flutter/widgets.dart';

export 'package:dhara/theme/logo_style.dart';

/// The app's mark. Drawn, so it is sharp at every size.
class DharaLogo extends StatelessWidget {
  const DharaLogo({super.key, this.size = 1.5 * rem, this.style});

  final double size;

  /// Which drawing; without one, the one chosen in Settings.
  final DharaLogoStyle? style;

  @override
  Widget build(BuildContext context) {
    final style =
        this.style ??
        SettingsScope.maybeOf(context)?.logoStyle ??
        defaultLogoStyle;
    return ExcludeSemantics(
      child: CustomPaint(
        // Says which drawing this is, to whoever looks for it.
        key: ValueKey(style),
        size: Size.square(size),
        painter: _LogoPainter(style),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter(this.style);

  final DharaLogoStyle style;

  static const _white = Color(0xFFFFFFFF);
  static const _box = Rect.fromLTWH(0, 0, 32, 32);
  static const _deepGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF5A3FD6), Color(0xFF0F8FB3)],
  );
  static const _darkGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1B1640), Color(0xFF07222E)],
  );
  static const _markGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFA48BFF), DharaColors.accent2],
  );

  @override
  void paint(Canvas canvas, Size size) {
    // Every drawing is 32 by 32, as in the prototype.
    canvas
      ..save()
      ..scale(size.width / 32, size.height / 32);
    switch (style) {
      case DharaLogoStyle.water:
        _water(canvas, dark: false);
      case DharaLogoStyle.darkWater:
        _water(canvas, dark: true);
      case DharaLogoStyle.classic:
        _square(canvas, DharaColors.accentGradient);
        _sharpPlay(canvas, Paint()..color = _white);
        _wave(canvas, _stroke(2.2)..color = _white);
      case DharaLogoStyle.dark:
        _dark(canvas, roundPlay: false);
      case DharaLogoStyle.darkRounded:
        _dark(canvas, roundPlay: true);
      case DharaLogoStyle.rounded:
        _rounded(canvas);
    }
    canvas.restore();
  }

  void _water(Canvas canvas, {required bool dark}) {
    final square = RRect.fromRectAndRadius(_box, const Radius.circular(9));
    // On the dark square the water and the triangle carry the colours.
    final wet = dark
        ? DharaColors.accentGradient.createShader(
            const Rect.fromLTRB(0, 20, 32, 32),
          )
        : null;
    final mark = dark
        ? _markGradient.createShader(const Rect.fromLTRB(7, 8, 25, 26))
        : null;
    final crest = Path()
      ..moveTo(0, 22.5)
      ..cubicTo(4, 19.8, 8, 25.2, 12, 22.5)
      ..cubicTo(16, 19.8, 20, 25.2, 24, 22.5)
      ..cubicTo(28, 19.8, 30, 20.6, 32, 22);
    final water = Path.from(crest)
      ..lineTo(32, 32)
      ..lineTo(0, 32)
      ..close();
    canvas
      ..drawRRect(
        square,
        Paint()
          ..shader = (dark ? _darkGradient : _deepGradient).createShader(_box),
      )
      ..save()
      ..clipRRect(square)
      ..drawPath(
        water,
        Paint()
          // With a shader, only the colour's opacity counts.
          ..color = dark ? const Color(0x61FFFFFF) : const Color(0x38FFFFFF)
          ..shader = wet,
      )
      ..drawPath(
        crest,
        _stroke(1.8)
          ..color = _white
          ..shader = wet,
      )
      ..restore();
    if (dark) _darkEdge(canvas);
    _roundPlay(
      canvas,
      13.4,
      8.6,
      16,
      19.7,
      Paint()
        ..color = _white
        ..shader = mark,
    );
  }

  /// The thin accent line around a dark square.
  void _darkEdge(Canvas canvas) => canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(.6, .6, 30.8, 30.8),
      const Radius.circular(8.4),
    ),
    _stroke(1.2)..color = const Color(0x8C8B6CFF),
  );

  void _dark(Canvas canvas, {required bool roundPlay}) {
    _square(canvas, _darkGradient);
    final mark = _markGradient.createShader(const Rect.fromLTRB(7, 8, 25, 26));
    _darkEdge(canvas);
    if (roundPlay) {
      _roundPlay(canvas, 13.4, 9.8, 17.2, 19.7, Paint()..shader = mark);
    } else {
      _sharpPlay(canvas, Paint()..shader = mark);
    }
    _wave(canvas, _stroke(2.2)..shader = mark);
  }

  void _rounded(Canvas canvas) {
    _square(canvas, DharaColors.accentGradient);
    _roundPlay(canvas, 13.4, 9.6, 16.4, 19.2, Paint()..color = _white);
    canvas
      ..drawPath(
        Path()
          ..moveTo(7, 22.4)
          ..cubicTo(10, 20, 13, 24.8, 16, 22.4)
          ..cubicTo(19, 20, 22, 24.8, 25, 22.4),
        _stroke(2.2)..color = _white,
      )
      ..drawPath(
        Path()
          ..moveTo(10, 26.4)
          ..cubicTo(12, 24.9, 14, 27.9, 16, 26.4)
          ..cubicTo(18, 24.9, 20, 27.9, 22, 26.4),
        _stroke(1.7)..color = const Color(0x99FFFFFF),
      );
  }

  void _square(Canvas canvas, Gradient gradient) => canvas.drawRRect(
    RRect.fromRectAndRadius(_box, const Radius.circular(9)),
    Paint()..shader = gradient.createShader(_box),
  );

  /// The first mark's triangle.
  void _sharpPlay(Canvas canvas, Paint paint) => canvas.drawPath(
    Path()
      ..moveTo(12.5, 8.5)
      ..lineTo(12.5, 18.5)
      ..lineTo(21, 13.5)
      ..close(),
    paint,
  );

  /// A triangle with its left side at [left] from [top] to [bottom] and its
  /// point at [tip], drawn once more as a thick round-cornered outline:
  /// that is what rounds its corners.
  void _roundPlay(
    Canvas canvas,
    double left,
    double top,
    double bottom,
    double tip,
    Paint paint,
  ) {
    final triangle = Path()
      ..moveTo(left, top)
      ..lineTo(left, bottom)
      ..lineTo(tip, (top + bottom) / 2)
      ..close();
    canvas
      ..drawPath(triangle, paint)
      ..drawPath(
        triangle,
        Paint()
          ..color = paint.color
          ..shader = paint.shader
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeJoin = StrokeJoin.round,
      );
  }

  /// The first mark's wave.
  void _wave(Canvas canvas, Paint paint) => canvas.drawPath(
    Path()
      ..moveTo(7, 23.5)
      ..cubicTo(10, 21.1, 13, 25.9, 16, 23.5)
      ..cubicTo(19, 21.1, 22, 25.9, 25, 23.5),
    paint,
  );

  static Paint _stroke(double width) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round;

  @override
  bool shouldRepaint(_LogoPainter old) => old.style != style;
}
