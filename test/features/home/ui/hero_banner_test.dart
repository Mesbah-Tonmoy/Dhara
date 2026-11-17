import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/core/settings/key_value_store.dart';
import 'package:dhara/core/settings/settings_controller.dart';
import 'package:dhara/features/home/home_store.dart';
import 'package:dhara/features/home/ui/hero_banner.dart';
import 'package:dhara/features/home/ui/title_meta.dart';
import 'package:dhara/features/home/ui/wide_card.dart';
import 'package:dhara/features/metadata/video_identity.dart';
import 'package:dhara/features/my_list/my_list_controller.dart';
import 'package:dhara/shell/page_bleed.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:dhara/widgets/buttons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TitleCard _title(int id, {TitleKind kind = TitleKind.movie}) => TitleCard(
  id: id,
  kind: kind,
  name: 'Title $id',
  year: 2020 + id,
  rating: 7.5,
  runtime: 112,
  genres: const ['Drama', 'Mystery', 'Thriller', 'Crime'],
  overview: 'What title $id is about.',
  height: 2160,
  videos: 2,
);

final _titles = [for (var id = 1; id <= 4; id++) _title(id)];

void main() {
  late MyListController myList;
  final played = <int>[];
  final opened = <int>[];

  setUp(() {
    myList = MyListController(library: const NoLibrary());
    played.clear();
    opened.clear();
  });

  tearDown(() => myList.dispose());

  Future<void> pump(
    WidgetTester tester, {
    List<TitleCard>? titles,
    Set<int> resumable = const {},
    bool disableAnimations = false,
    Size window = const Size(1280, 720),
    SettingsController? settings,
    ScrollController? scroll,
  }) async {
    tester.view
      ..physicalSize = window
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MyListScope(
        controller: myList,
        child: SettingsScope(
          settings: settings ?? SettingsController(MemoryKeyValueStore()),
          child: MaterialApp(
            builder: (context, page) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(disableAnimations: disableAnimations),
              child: page!,
            ),
            home: Material(
              color: DharaColors.bg,
              child: ListView(
                controller: scroll,
                clipBehavior: Clip.none,
                children: [
                  HeroBanner(
                    titles: titles ?? _titles,
                    resumable: resumable,
                    scroll: scroll,
                    onPlay: (title) => played.add(title.id),
                    onMore: (title) => opened.add(title.id),
                  ),
                  // A page to scroll, where the test asks for one.
                  if (scroll != null) const SizedBox(height: 2000),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  String shown(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('hero-title')).last).data!;

  testWidgets('shows the first featured title with what is known of it', (
    tester,
  ) async {
    await pump(tester);

    expect(shown(tester), 'Title 1');
    expect(find.text('MOVIE'), findsOneWidget);
    expect(find.text('7.5'), findsOneWidget);
    expect(find.text('2021'), findsOneWidget);
    expect(find.text('1h 52m'), findsOneWidget);
    expect(find.text('Drama, Mystery, Thriller'), findsOneWidget);
    expect(find.text('4K'), findsOneWidget);
    expect(find.text('What title 1 is about.'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
  });

  testWidgets('is as tall as the window allows, within its limits', (
    tester,
  ) async {
    expect(HeroBanner.heightFor(720), 720 * .74);
    expect(HeroBanner.heightFor(300), 27 * rem);
    expect(HeroBanner.heightFor(2000), 48 * rem);
  });

  testWidgets('a backdrop that is zoomed is cut off at the banner\'s foot', (
    tester,
  ) async {
    await pump(tester);

    // The backdrops not on show are drawn 8% larger than their place.
    final zoomed = tester.widget<AnimatedScale>(
      find.descendant(
        of: find.byKey(const ValueKey('hero-art-2')),
        matching: find.byType(AnimatedScale),
      ),
    );
    expect(zoomed.scale, greaterThan(1));

    final clip = find.byKey(const Key('hero-art'));
    expect(tester.widget(clip), isA<ClipRect>());
    expect(
      find.descendant(
        of: clip,
        matching: find.byKey(const ValueKey('hero-art-2')),
      ),
      findsOneWidget,
    );
    expect(
      tester.getRect(clip).bottom,
      moreOrLessEquals(HeroBanner.heightFor(720) - PageInsets.top),
    );
  });

  testWidgets('moves on by itself, and round again', (tester) async {
    await pump(tester);

    await tester.pump(DharaMotion.heroInterval);
    await tester.pump(const Duration(milliseconds: 600));
    expect(shown(tester), 'Title 2');

    for (var i = 0; i < 3; i++) {
      await tester.pump(DharaMotion.heroInterval);
      await tester.pump(const Duration(milliseconds: 600));
    }
    expect(shown(tester), 'Title 1');
  });

  testWidgets('holds while the pointer is over it', (tester) async {
    await pump(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1270, 710));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(HeroBanner)));
    await tester.pump();

    await tester.pump(DharaMotion.heroInterval * 2);
    await tester.pump(const Duration(seconds: 1));
    expect(shown(tester), 'Title 1');

    await mouse.moveTo(const Offset(1270, 710));
    await tester.pump();
    await tester.pump(DharaMotion.heroInterval);
    await tester.pump(const Duration(seconds: 1));
    expect(shown(tester), 'Title 2');
  });

  testWidgets('holds still while the page has scrolled it out of the '
      'window', (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await pump(tester, scroll: scroll);

    // Out of the window, but still built.
    String kept() => tester
        .widget<Text>(
          find.byKey(const Key('hero-title'), skipOffstage: false).last,
        )
        .data!;

    scroll.jumpTo(HeroBanner.heightFor(720) + 10);
    await tester.pump();
    await tester.pump(DharaMotion.heroInterval * 2);
    await tester.pump(const Duration(seconds: 1));
    expect(kept(), 'Title 1');
    expect(
      tester.binding.hasScheduledFrame,
      isFalse,
      reason: 'nothing of it animates',
    );

    scroll.jumpTo(0);
    await tester.pump();
    await tester.pump(DharaMotion.heroInterval);
    await tester.pump(const Duration(milliseconds: 600));
    expect(shown(tester), 'Title 2');
  });

  testWidgets('does not move on when animations are switched off', (
    tester,
  ) async {
    await pump(tester, disableAnimations: true);

    await tester.pump(DharaMotion.heroInterval * 3);
    expect(shown(tester), 'Title 1');
  });

  testWidgets('stays on its title while "Rotate featured titles" is off, '
      'and moves on again once it is on', (tester) async {
    final settings = SettingsController(MemoryKeyValueStore())
      ..setRotateFeatured(false);
    await pump(tester, settings: settings);

    await tester.pump(DharaMotion.heroInterval * 3);
    expect(shown(tester), 'Title 1');

    settings.setRotateFeatured(true);
    await tester.pump();
    await tester.pump(DharaMotion.heroInterval);
    await tester.pump(const Duration(milliseconds: 600));
    expect(shown(tester), 'Title 2');
  });

  testWidgets('a small picture picks its title', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(const Key('hero-pick-2')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(shown(tester), 'Title 3');
    // And its time starts from the beginning.
    await tester.pump(DharaMotion.heroInterval - const Duration(seconds: 2));
    expect(shown(tester), 'Title 3');
  });

  testWidgets('one title alone has no pictures to pick from, and a narrow '
      'window leaves them out', (tester) async {
    await pump(tester, titles: [_title(1)]);
    expect(find.byKey(const Key('hero-pick-0')), findsNothing);

    await pump(tester, window: const Size(960, 600));
    expect(find.byKey(const Key('hero-pick-0')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Play, More info and My List act on the title on show', (
    tester,
  ) async {
    await pump(tester, resumable: {2});
    await tester.tap(find.byKey(const Key('hero-pick-1')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Resume'), findsOneWidget);
    await tester.tap(find.byKey(const Key('hero-play')));
    await tester.tap(find.byKey(const Key('hero-more')));
    expect(played, [2]);
    expect(opened, [2]);

    expect(find.text('My List'), findsOneWidget);
    await tester.tap(find.byKey(const Key('my-list-button')));
    await tester.pump();
    expect(myList.contains(2), isTrue);
    expect(find.text('In My List'), findsOneWidget);
    expect(
      tester.widget<DharaButton>(find.byKey(const Key('my-list-button'))).on,
      isTrue,
    );
  });

  group('labels', () {
    test('a length is told in hours and minutes', () {
      expect(runtimeLabel(112), '1h 52m');
      expect(runtimeLabel(60), '1h 00m');
      expect(runtimeLabel(48), '48 min');
    });

    test('a title is a movie, a series or anime', () {
      expect(kindLabel(_title(1)), 'MOVIE');
      expect(kindLabel(_title(1, kind: TitleKind.series)), 'SERIES');
      expect(
        kindLabel(
          const TitleCard(
            id: 1,
            kind: TitleKind.series,
            name: 'A',
            videos: 1,
            isAnime: true,
          ),
        ),
        'ANIME',
      );
    });

    test('what is left of a video is told in minutes', () {
      expect(timeLeftLabel(const Duration(minutes: 65)), '1h 05m left');
      expect(timeLeftLabel(const Duration(minutes: 34)), '34 min left');
      expect(timeLeftLabel(const Duration(seconds: 20)), 'Under a minute left');
    });
  });

  group('WideCard', () {
    Future<void> show(WidgetTester tester, ContinueItem item) =>
        tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: DharaLayout.wideCardWidth,
                child: WideCard(item: item, onPlay: () => played.add(1)),
              ),
            ),
          ),
        );

    testWidgets('names the title, the episode and what is left', (
      tester,
    ) async {
      await show(
        tester,
        ContinueItem(
          url: 'http://a.test/bay.mkv',
          watchedAt: DateTime(2026, 11, 15),
          position: const Duration(minutes: 10),
          duration: const Duration(minutes: 40),
          title: _title(1, kind: TitleKind.series),
          season: 1,
          episode: 2,
        ),
      );

      expect(find.text('Title 1'), findsOneWidget);
      expect(find.text('S1 · E2 · 30 min left'), findsOneWidget);
      expect(
        tester
            .widget<FractionallySizedBox>(
              find.descendant(
                of: find.byType(WatchedBar),
                matching: find.byType(FractionallySizedBox),
              ),
            )
            .widthFactor,
        .25,
      );
      expect(tester.getSize(find.byType(WideCard)).aspectRatio, 16 / 9);

      await tester.tap(find.byType(WideCard));
      expect(played, [1]);
    });

    testWidgets('a video that is not in the library goes by its file name', (
      tester,
    ) async {
      await show(
        tester,
        ContinueItem(
          url: 'http://a.test/clips/My%20Clip.mkv',
          watchedAt: DateTime(2026, 11, 15),
          position: const Duration(minutes: 1),
          duration: const Duration(minutes: 3),
        ),
      );

      expect(find.text('My Clip.mkv'), findsOneWidget);
      expect(find.text('2 min left'), findsOneWidget);
    });
  });
}
