import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// A fade that runs from the top of a box to its bottom: the colours at
/// [stops] (0 = top, 1 = bottom), blended in between.
@immutable
class ShadeSpec {
  /// As many [stops] as [colors], at least two, from 0 up to 1.
  const ShadeSpec({required this.colors, required this.stops});

  final List<Color> colors;
  final List<double> stops;

  /// The colour at [t], 0 (top) to 1 (bottom).
  Color colorAt(double t) {
    if (t <= stops.first) return colors.first;
    for (var i = 1; i < stops.length; i++) {
      if (t <= stops[i]) {
        final span = stops[i] - stops[i - 1];
        return Color.lerp(
          colors[i - 1],
          colors[i],
          span <= 0 ? 1 : (t - stops[i - 1]) / span,
        )!;
      }
    }
    return colors.last;
  }
}

/// Draws a [ShadeSpec] over its box, to darken a picture under text.
///
/// Every card of a row or a grid has one. Drawn as a gradient, each costs
/// the graphics card two render passes per frame (measured with Impeller
/// on OpenGL ES, 2026-11-16: a grid of 23 cards took 117 passes a frame,
/// 15 without their gradients). So the fade is made into a small picture
/// once, and every card just stretches that picture over itself. Until
/// the picture is there, and where it cannot be made, the gradient is
/// drawn as before: it looks the same.
class Shade extends StatefulWidget {
  const Shade(this.spec, {super.key});

  final ShadeSpec spec;

  @override
  State<Shade> createState() => _ShadeState();
}

class _ShadeState extends State<Shade> {
  late ValueListenable<ui.Image?> _picture = shadePicture(widget.spec);

  @override
  void initState() {
    super.initState();
    _picture.addListener(_changed);
  }

  @override
  void didUpdateWidget(Shade old) {
    super.didUpdateWidget(old);
    if (!identical(old.spec, widget.spec)) {
      _picture.removeListener(_changed);
      _picture = shadePicture(widget.spec)..addListener(_changed);
    }
  }

  @override
  void dispose() {
    _picture.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final picture = _picture.value;
    return IgnorePointer(
      child: picture == null
          ? DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: widget.spec.colors,
                  stops: widget.spec.stops,
                ),
              ),
            )
          : RawImage(
              image: picture,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.low,
            ),
    );
  }
}

/// The picture of [spec]: `null` until it is made (the first ask starts
/// that), then the same picture for everyone, for as long as the app runs.
ValueListenable<ui.Image?> shadePicture(ShadeSpec spec) =>
    _pictures[spec] ??= _make(spec);

final _pictures = Expando<ValueNotifier<ui.Image?>>('shade pictures');

/// Rows of the picture; it is stretched to the height of the box.
const shadePictureRows = 256;

ValueNotifier<ui.Image?> _make(ShadeSpec spec) {
  final picture = ValueNotifier<ui.Image?>(null);
  try {
    ui.decodeImageFromPixels(
      shadePixels(spec),
      2,
      shadePictureRows,
      ui.PixelFormat.rgba8888,
      (image) => picture.value = image,
    );
  } on Object {
    // The gradient stays.
  }
  return picture;
}

/// The pixels of the picture of [spec]: two columns of [shadePictureRows]
/// rows, red, green, blue and alpha, the colours multiplied by the alpha.
Uint8List shadePixels(ShadeSpec spec) {
  final pixels = Uint8List(2 * shadePictureRows * 4);
  for (var row = 0; row < shadePictureRows; row++) {
    final color = spec.colorAt(row / (shadePictureRows - 1));
    final alpha = color.a;
    for (var column = 0; column < 2; column++) {
      final at = (row * 2 + column) * 4;
      pixels[at] = (color.r * alpha * 255).round();
      pixels[at + 1] = (color.g * alpha * 255).round();
      pixels[at + 2] = (color.b * alpha * 255).round();
      pixels[at + 3] = (alpha * 255).round();
    }
  }
  return pixels;
}
