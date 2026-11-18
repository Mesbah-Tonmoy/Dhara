import 'package:dhara/features/player/subtitle_place.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const window = Size(1600, 900);

  test('with the bar hidden the subtitles keep their own place', () {
    expect(
      subtitlePosition(area: window, barHeight: 0, aspect: 16 / 9),
      100,
    );
  });

  test('a picture that fills the window has them stand on the bar', () {
    // The bar covers the last 90 of 900 pixels: its top edge is at 90%.
    expect(
      subtitlePosition(area: window, barHeight: 90, aspect: 16 / 9),
      90,
    );
    expect(
      subtitlePosition(area: window, barHeight: 135, aspect: 16 / 9),
      85,
    );
  });

  test('a wide film that ends above the bar keeps them at its foot', () {
    // 2.39:1 in a 16:9 window is 669 pixels high, with 115 black ones
    // below it: more than the bar covers.
    expect(
      subtitlePosition(area: window, barHeight: 90, aspect: 2.39),
      100,
    );
  });

  test('a film a little wider than the window lifts them a little', () {
    // 1.9:1 is 842 pixels high and ends 29 above the foot of the window;
    // the bar's top edge is 61 pixels into the picture from below.
    expect(
      subtitlePosition(area: window, barHeight: 90, aspect: 1.9),
      92,
    );
  });

  test('a narrow picture is as high as the window', () {
    expect(
      subtitlePosition(area: window, barHeight: 90, aspect: 4 / 3),
      90,
    );
  });

  test('a picture of unknown size is taken to fill the window', () {
    expect(subtitlePosition(area: window, barHeight: 90, aspect: null), 90);
    expect(subtitlePosition(area: window, barHeight: 90, aspect: 0), 90);
  });

  test('they are never lifted beyond the middle of the picture', () {
    expect(
      subtitlePosition(area: window, barHeight: 700, aspect: 16 / 9),
      minSubtitlePosition,
    );
  });

  test('an area without a size changes nothing', () {
    expect(
      subtitlePosition(area: Size.zero, barHeight: 90, aspect: 16 / 9),
      100,
    );
  });
}
