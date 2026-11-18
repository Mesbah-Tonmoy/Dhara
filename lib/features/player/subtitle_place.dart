import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The highest the subtitles are ever lifted, whatever the sizes say.
const minSubtitlePosition = 50;

/// Where libmpv draws the subtitles: mpv's `sub-pos`, in percent of the
/// picture's height. 100 is their own place, at the foot of the picture.
///
/// libmpv draws them into the picture, so while the control bar shows they
/// would sit underneath it. They are lifted just far enough to stand on the
/// bar's top edge. A picture that ends above the bar anyway (a wide film in
/// a taller window has a black strip below it) keeps them at its foot: they
/// cannot be drawn outside the picture.
///
/// [area] is what the player fills, [barHeight] how much of its foot the
/// control bar covers (0 while it is hidden), and [aspect] the picture's
/// width divided by its height (`null` while that is not known: the picture
/// is then taken to fill the area).
int subtitlePosition({
  required Size area,
  required double barHeight,
  required double? aspect,
}) {
  if (barHeight <= 0 || area.width <= 0 || area.height <= 0) return 100;
  final ratio = aspect == null || aspect <= 0 ? area.aspectRatio : aspect;
  // The picture is fitted into the area and centred in it.
  final height = math.min(area.height, area.width / ratio);
  final top = (area.height - height) / 2;
  final barTop = area.height - barHeight;
  final percent = ((barTop - top) * 100 / height).floor();
  return percent.clamp(minSubtitlePosition, 100);
}
