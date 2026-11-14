import 'package:dhara/theme/tokens.dart';
import 'package:flutter/widgets.dart';

/// The app's mark: a play triangle over a wave ("dhara": a stream) on the
/// accent gradient. Drawn, so it is sharp at every size.
class DharaLogo extends StatelessWidget {
  const DharaLogo({super.key, this.size = 1.5 * rem});

  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(size: Size.square(size), painter: const _LogoPainter()),
  );
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // The prototype's 32 by 32 drawing.
    canvas
      ..save()
      ..scale(size.width / 32, size.height / 32);
    const box = Rect.fromLTWH(0, 0, 32, 32);
    const white = Color(0xFFFFFFFF);
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(9)),
        Paint()..shader = DharaColors.accentGradient.createShader(box),
      )
      ..drawPath(
        Path()
          ..moveTo(12.5, 8.5)
          ..lineTo(12.5, 18.5)
          ..lineTo(21, 13.5)
          ..close(),
        Paint()..color = white,
      )
      ..drawPath(
        Path()
          ..moveTo(7, 23.5)
          ..cubicTo(10, 21.1, 13, 25.9, 16, 23.5)
          ..cubicTo(19, 21.1, 22, 25.9, 25, 23.5),
        Paint()
          ..color = white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_LogoPainter old) => false;
}
