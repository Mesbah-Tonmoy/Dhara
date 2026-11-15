import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/core/images/remote_image.dart';
import 'package:dhara/features/home/ui/card_row.dart';
import 'package:dhara/features/metadata/anilist_client.dart';
import 'package:dhara/features/metadata/anime_controller.dart';
import 'package:dhara/features/metadata/anime_store.dart';
import 'package:dhara/features/metadata/ui/anime_screen.dart';
import 'package:dhara/theme/theme.dart';
import 'package:dhara/widgets/pressable.dart';
import 'package:dhara/widgets/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _cover = '/file/anilistcdn/media/anime/cover/large/bx21-YCDoj1.jpg';

const _trending = [
  AnimeEntry(
    id: 21,
    english: 'ONE PIECE',
    romaji: 'ONE PIECE',
    format: 'TV',
    year: 1999,
    score: 87,
    coverPath: _cover,
  ),
  AnimeEntry(
    id: 195516,
    english: 'The Apothecary Diaries Season 3',
    romaji: 'Kusuriya no Hitorigoto 3rd Season',
    format: 'TV',
    episodes: 12,
    year: 2026,
    score: 85,
  ),
];

const _seasonal = [
  AnimeEntry(id: 7, romaji: 'Eiga no Namae', format: 'MOVIE', episodes: 1),
];

void main() {
  final now = DateTime(2026, 11, 14, 12);

  /// Shows the page over lists that were fetched a moment ago, so that
  /// AniList is not asked.
  Future<AnimeController> show(
    WidgetTester tester, {
    List<AnimeEntry>? trending,
    List<AnimeEntry> seasonal = const [],
    LibraryWorker? library,
  }) async {
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = LibraryDb.inMemory();
    addTearDown(db.close);
    if (trending != null) {
      AnimeStore(db, now: () => now)
        ..keepList('trending', trending)
        ..keepList('season|fall|2026', seasonal);
      // One show of the library, by the name its files give it.
      db.db
        ..execute(
          'INSERT INTO titles (id, kind, name, added_at) '
          "VALUES (1, 1, 'One Piece', 0)",
        )
        ..execute(
          'INSERT INTO title_keys (key, title, name) '
          "VALUES ('s|one piece', 1, 'One Piece')",
        );
    }
    final anime = AnimeController(
      library: library ?? LocalLibrary(db),
      clock: () => now,
    );
    addTearDown(anime.dispose);
    await tester.pumpWidget(
      AnimeScope(
        controller: anime,
        child: MaterialApp(
          theme: buildDharaTheme(),
          builder: (context, page) => ToastHost(child: page!),
          home: const Material(child: AnimeScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return anime;
  }

  List<int> listed(WidgetTester tester, String row) => [
    for (final card in tester.widgetList<AnimeCard>(
      find.descendant(
        of: find.byKey(Key(row)),
        matching: find.byType(AnimeCard),
      ),
    ))
      card.row.anime.id,
  ];

  testWidgets('lists the season and what is trending as rows of covers', (
    tester,
  ) async {
    await show(tester, trending: _trending, seasonal: _seasonal);

    expect(listed(tester, 'anime-season'), [7]);
    expect(listed(tester, 'anime-trending'), [21, 195516]);
    expect(
      tester.widget<CardRow>(find.byKey(const Key('anime-season'))).title,
      'Airing this season · Fall 2026',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('anime-info'))).data,
      '0 of 1 of this season and 1 of 2 of what is trending on your '
      'servers. Nothing about your library is sent to AniList.',
    );
    expect(find.byKey(const Key('anime-failure')), findsNothing);
    // No library row without anything that is known to be anime.
    expect(find.byKey(const Key('anime-mine')), findsNothing);
  });

  testWidgets('a card says what the anime is and whether the library has '
      'it', (tester) async {
    await show(tester, trending: _trending, seasonal: _seasonal);

    expect(find.text('ONE PIECE'), findsOneWidget);
    expect(find.text('Series · 1999'), findsOneWidget);
    expect(find.text('8.7'), findsOneWidget);
    expect(find.text('IN LIBRARY'), findsOneWidget);
    expect(find.text('Series · 12 episodes · 2026'), findsOneWidget);
    expect(find.text('Eiga no Namae'), findsOneWidget);
    expect(find.text('Film'), findsOneWidget);
    expect(find.text('Not on your servers'), findsNWidgets(2));

    // The cover comes from AniList's picture server, when there is one.
    TmdbCover cover(int id) => tester.widget<TmdbCover>(
      find.descendant(
        of: find.byKey(Key('anime-$id')),
        matching: find.byType(TmdbCover),
      ),
    );
    expect((cover(21).anilist, cover(21).path), (true, _cover));
    expect(cover(195516).path, isNull);

    expect(
      tester
          .widget<Pressable>(
            find.descendant(
              of: find.byKey(const Key('anime-21')),
              matching: find.byType(Pressable),
            ),
          )
          .semanticLabel,
      'ONE PIECE, in your library',
    );
  });

  testWidgets('one the library lacks says so when it is clicked', (
    tester,
  ) async {
    await show(tester, trending: _trending, seasonal: _seasonal);

    await tester.tap(find.byKey(const Key('anime-195516')));
    await tester.pump();

    expect(
      find.textContaining('is not on your enabled servers.'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('says why there are no lists', (tester) async {
    await show(tester, library: const NoLibrary());

    expect(
      tester.widget<Text>(find.byKey(const Key('anime-failure'))).data,
      contains('error in the app'),
    );
    expect(find.text('Ask again'), findsOneWidget);
    expect(find.byType(AnimeCard), findsNothing);
  });

  test('an anime is described by kind, length and year', () {
    expect(describeAnime(_trending[1]), 'Series · 12 episodes · 2026');
    expect(describeAnime(_seasonal.single), 'Film');
    expect(describeAnime(const AnimeEntry(id: 1, format: 'OVA')), 'OVA');
    expect(describeAnime(const AnimeEntry(id: 1)), '');
  });
}
