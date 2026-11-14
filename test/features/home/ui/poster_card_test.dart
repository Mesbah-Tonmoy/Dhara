import 'package:dhara/features/home/home_store.dart';
import 'package:dhara/features/home/ui/poster_card.dart';
import 'package:dhara/features/metadata/video_identity.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:dhara/widgets/placeholder_art.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../widgets/support.dart';

TitleCard _film({
  String name = 'Vivarium',
  int? year = 2019,
  double? rating = 6.1,
  int? height = 1080,
  int videos = 2,
  List<String> genres = const ['Science Fiction', 'Thriller', 'Mystery'],
}) => TitleCard(
  id: 7,
  kind: TitleKind.movie,
  name: name,
  year: year,
  rating: rating,
  height: height,
  videos: videos,
  genres: genres,
);

const _show = TitleCard(
  id: 8,
  kind: TitleKind.series,
  name: 'The Bay',
  videos: 30,
  episodes: 24,
);

Future<void> _pump(WidgetTester tester, Widget card) => tester.pumpWidget(
  host(SizedBox(width: DharaLayout.posterWidth, child: card)),
);

/// How far the panel at the foot of the card is slid out of it (0: in).
double _peekOffset(WidgetTester tester) =>
    tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).offset.dy;

void main() {
  group('labels', () {
    test('a picture height is named as people name it', () {
      expect(qualityLabel(2160), '4K');
      expect(qualityLabel(1080), '1080p');
      expect(qualityLabel(1088), '1080p');
      expect(qualityLabel(720), '720p');
      expect(qualityLabel(480), '480p');
      expect(qualityLabel(360), 'SD');
      expect(qualityLabel(null), isNull);
    });

    test('a film has copies, a show has episodes', () {
      expect(holdingsLabel(_film()), '2 copies');
      expect(holdingsLabel(_film(videos: 1)), '1 copy');
      expect(holdingsLabel(_show), '24 episodes');
      expect(
        holdingsLabel(
          const TitleCard(
            id: 1,
            kind: TitleKind.series,
            name: 'Unnumbered',
            videos: 1,
          ),
        ),
        '1 video',
      );
    });
  });

  testWidgets('without a poster it draws artwork from the name, with the '
      'name on it', (tester) async {
    await _pump(tester, PosterCard(title: _film(), onOpen: () {}));

    expect(
      tester.widget<PlaceholderArt>(find.byType(PlaceholderArt)).seed,
      'Vivarium',
    );
    expect(find.text('VIVARIUM'), findsOneWidget);
    expect(tester.getSize(find.byType(PosterCard)).aspectRatio, 2 / 3);
  });

  testWidgets('shows the quality and the rating in its corners', (
    tester,
  ) async {
    await _pump(tester, PosterCard(title: _film(), onOpen: () {}));
    expect(find.text('1080p'), findsOneWidget);
    expect(find.text('6.1'), findsOneWidget);

    await _pump(
      tester,
      PosterCard(title: _film(height: null, rating: null), onOpen: () {}),
    );
    expect(find.text('1080p'), findsNothing);
    expect(find.text('6.1'), findsNothing);
    expect(find.byIcon(Icons.star_rounded), findsNothing);
  });

  testWidgets('a card of a ranked row shows its place', (tester) async {
    await _pump(tester, PosterCard(title: _film(), rank: 3, onOpen: () {}));

    expect(find.text('#3'), findsOneWidget);
    expect(find.text('1080p'), findsOneWidget);
    expect(
      tester.getCenter(find.text('#3')).dx,
      lessThan(tester.getCenter(find.text('1080p')).dx),
    );
  });

  testWidgets('under the pointer it grows, glows and tells more', (
    tester,
  ) async {
    useKeyboardHighlight();
    await _pump(tester, PosterCard(title: _film(), onOpen: () {}));
    expect(_peekOffset(tester), greaterThan(1));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(PosterCard)));
    await tester.pumpAndSettle();

    expect(_peekOffset(tester), 0);
    expect(
      tester.widgetList<AnimatedScale>(find.byType(AnimatedScale)).first.scale,
      DharaMotion.hoverScale,
    );
    expect(
      tester
          .widget<AnimatedContainer>(find.byType(AnimatedContainer))
          .decoration,
      isA<BoxDecoration>().having(
        (box) => box.boxShadow,
        'shadow',
        DharaShadows.glow,
      ),
    );
    expect(find.text('Vivarium'), findsOneWidget);
    expect(find.text('2019 · Science Fiction, Thriller'), findsOneWidget);
    expect(find.text('2 copies'), findsOneWidget);
  });

  testWidgets('a title without genres says what kind it is', (tester) async {
    await _pump(tester, PosterCard(title: _show, onOpen: () {}));
    expect(find.text('Show'), findsOneWidget);
    expect(find.text('24 episodes'), findsOneWidget);

    await _pump(
      tester,
      PosterCard(
        title: _film(year: null, genres: const []),
        onOpen: () {},
      ),
    );
    expect(find.text('Film'), findsOneWidget);
  });

  testWidgets('a click opens it, and so does Enter', (tester) async {
    useKeyboardHighlight();
    var opened = 0;
    await _pump(
      tester,
      PosterCard(title: _film(), autofocus: true, onOpen: () => opened++),
    );
    await tester.pumpAndSettle();

    // With the keyboard on it, it tells more as well.
    expect(_peekOffset(tester), 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(opened, 1);

    await tester.tap(find.byType(PosterCard));
    expect(opened, 2);
  });

  testWidgets('is announced by the name of the title', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, PosterCard(title: _film(), onOpen: () {}));

    expect(
      tester.getSemantics(find.byType(PosterCard)),
      isSemantics(label: 'Vivarium', isButton: true),
    );
    handle.dispose();
  });

  testWidgets('draws a hostile name as plain text', (tester) async {
    const name = '<script>alert(1)</script> {{x}} %s';
    await _pump(
      tester,
      PosterCard(
        title: _film(name: name),
        onOpen: () {},
      ),
    );

    // On the artwork, in capitals; the panel under it is not looked at here.
    expect(find.text(name.toUpperCase()), findsOneWidget);
    expect(find.text(name), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
