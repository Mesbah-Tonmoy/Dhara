import 'dart:ui' as ui;

import 'package:dhara/widgets/placeholder_art.dart';
import 'package:dhara/widgets/shade.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _shade = ShadeSpec(
  colors: [
    Color(0x59000000),
    Color(0x00000000),
    Color(0x00000000),
    Color(0xC7000000),
  ],
  stops: [0, .22, .54, 1],
);

Widget _host(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: Center(child: SizedBox(width: 90, height: 135, child: child)),
);

/// Lets work that needs the real clock (making a picture) finish: waits
/// until a picture is showing, or for [atLeast] where none should come.
Future<void> _settle(
  WidgetTester tester, {
  Duration atLeast = Duration.zero,
}) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < const Duration(seconds: 10)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    await tester.pump();
    final shown = find.byType(RawImage).evaluate().isNotEmpty;
    if (watch.elapsed >= atLeast && (shown || atLeast > Duration.zero)) return;
  }
}

void main() {
  group('ShadeSpec', () {
    test('blends between its stops', () {
      expect(_shade.colorAt(0), const Color(0x59000000));
      expect(_shade.colorAt(.11).a, closeTo(0x59 / 255 / 2, .01));
      expect(_shade.colorAt(.22).a, 0);
      expect(_shade.colorAt(.4).a, 0);
      expect(_shade.colorAt(.77).a, closeTo(0xC7 / 255 / 2, .01));
      expect(_shade.colorAt(1), const Color(0xC7000000));
      // Outside the stops it is the colour at the end.
      expect(_shade.colorAt(-1), const Color(0x59000000));
      expect(_shade.colorAt(2), const Color(0xC7000000));
    });

    test('its picture is two columns of the same fade', () {
      final pixels = shadePixels(_shade);
      expect(pixels.length, 2 * shadePictureRows * 4);
      int alpha(int row, int column) => pixels[(row * 2 + column) * 4 + 3];

      expect(alpha(0, 0), 0x59);
      expect(alpha(0, 1), 0x59);
      expect(alpha(shadePictureRows ~/ 2, 0), 0);
      expect(alpha(shadePictureRows - 1, 1), 0xC7);
      // Black, whatever the alpha.
      for (var at = 0; at < pixels.length; at += 4) {
        expect(pixels[at] + pixels[at + 1] + pixels[at + 2], 0);
      }
    });

    test('colours are multiplied by their alpha', () {
      const half = ShadeSpec(
        colors: [Color(0x80FF8000), Color(0x80FF8000)],
        stops: [0, 1],
      );
      final pixels = shadePixels(half);
      expect(pixels.sublist(0, 4), [128, 64, 0, 128]);
    });
  });

  testWidgets('Shade is a gradient until its picture is made, then the '
      'picture, stretched', (tester) async {
    const spec = ShadeSpec(
      colors: [Color(0x00000000), Color(0xD9000000)],
      stops: [0, 1],
    );
    await tester.pumpWidget(_host(const Shade(spec)));
    final gradient =
        tester.widget<DecoratedBox>(find.byType(DecoratedBox)).decoration
            as BoxDecoration;
    expect((gradient.gradient! as LinearGradient).colors, spec.colors);
    expect(find.byType(RawImage), findsNothing);

    await _settle(tester);

    expect(find.byType(DecoratedBox), findsNothing);
    final picture = tester.widget<RawImage>(find.byType(RawImage));
    expect(picture.fit, BoxFit.fill);
    expect(picture.image!.height, shadePictureRows);
    expect(tester.getSize(find.byType(RawImage)), const Size(90, 135));

    // Every Shade of the same kind shares that one picture.
    await tester.pumpWidget(
      _host(
        const Stack(fit: StackFit.expand, children: [Shade(spec), Shade(spec)]),
      ),
    );
    final both = tester.widgetList<RawImage>(find.byType(RawImage)).toList();
    expect(both, hasLength(2));
    expect(identical(both.first.image, both.last.image), isTrue);
  });

  group('PlaceholderArt', () {
    setUp(ArtPictures.clear);

    testWidgets('is drawn into an image once it has stayed a moment', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const PlaceholderArt(seed: 'Harbor')));
      expect(find.byType(CustomPaint), findsOneWidget);
      expect(ArtPictures.take('Harbor', wide: false), isNull);

      await tester.pump(PlaceholderArt.settle);
      await _settle(tester);

      expect(find.byType(CustomPaint), findsNothing);
      final image = tester.widget<RawImage>(find.byType(RawImage)).image!;
      expect((image.width, image.height), (160, 240));
      expect(tester.getSize(find.byType(RawImage)), const Size(90, 135));

      // The next one of that name starts with the image.
      await tester.pumpWidget(
        _host(const PlaceholderArt(key: Key('again'), seed: 'Harbor')),
      );
      expect(find.byType(CustomPaint), findsNothing);
      expect(find.byType(RawImage), findsOneWidget);
    });

    testWidgets('one that is gone again at once is never made into an '
        'image', (tester) async {
      await tester.pumpWidget(_host(const PlaceholderArt(seed: 'Brief')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(_host(const SizedBox()));
      await tester.pump(PlaceholderArt.settle);
      await _settle(tester, atLeast: const Duration(milliseconds: 300));

      expect(ArtPictures.take('Brief', wide: false), isNull);
    });

    testWidgets('a wide one has an image of its own shape', (tester) async {
      await tester.pumpWidget(
        _host(const PlaceholderArt(seed: 'Harbor', wide: true)),
      );
      await tester.pump(PlaceholderArt.settle);
      await _settle(tester);

      final image = tester.widget<RawImage>(find.byType(RawImage)).image!;
      expect((image.width, image.height), (320, 180));
      expect(ArtPictures.take('Harbor', wide: false), isNull);
    });

    test('keeps the images used last', () async {
      for (var i = 0; i < ArtPictures.capacity + 5; i++) {
        await ArtPictures.make('title $i', wide: false);
      }
      ui.Image? of(int i) => ArtPictures.take('title $i', wide: false);

      expect(of(0), isNull);
      expect(of(4), isNull);
      final kept = of(5);
      expect(kept, isNotNull);
      kept!.dispose();
      expect(of(ArtPictures.capacity + 4), isNotNull);
    });
  });
}
