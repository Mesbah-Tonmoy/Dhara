import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/features/metadata/anilist_client.dart';
import 'package:dhara/features/metadata/anime_controller.dart';
import 'package:dhara/features/metadata/anime_store.dart';
import 'package:dhara/features/metadata/ui/anime_screen.dart';
import 'package:dhara/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 14, 12);

  /// Shows the screen over lists that were fetched a moment ago, so that
  /// AniList is not asked.
  Future<AnimeController> show(
    WidgetTester tester, {
    List<AnimeEntry>? trending,
    List<AnimeEntry> seasonal = const [],
    LibraryWorker? library,
  }) async {
    tester.view.physicalSize = const Size(1400, 900);
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
        child: MaterialApp(theme: buildDharaTheme(), home: const AnimeScreen()),
      ),
    );
    await tester.pump();
    return anime;
  }

  testWidgets('lists the season and what is trending, marked', (tester) async {
    await show(
      tester,
      trending: const [
        AnimeEntry(
          id: 21,
          english: 'ONE PIECE',
          romaji: 'ONE PIECE',
          format: 'TV',
          year: 1999,
          score: 87,
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
      ],
      seasonal: const [
        AnimeEntry(
          id: 7,
          romaji: 'Eiga no Namae',
          format: 'MOVIE',
          episodes: 1,
        ),
      ],
    );

    expect(find.text('FALL 2026  ·  0 OF 1 IN YOUR LIBRARY'), findsOneWidget);
    expect(
      find.text('TRENDING NOW  ·  1 OF 2 IN YOUR LIBRARY'),
      findsOneWidget,
    );
    expect(find.text('ONE PIECE (1999)'), findsOneWidget);
    expect(find.text('Series  ·  87 / 100'), findsOneWidget);
    expect(find.text('In your library'), findsOneWidget);
    expect(
      find.text(
        'Kusuriya no Hitorigoto 3rd Season  ·  Series  ·  12 episodes  ·  '
        '85 / 100',
      ),
      findsOneWidget,
    );
    expect(find.text('Eiga no Namae'), findsOneWidget);
    expect(find.text('Film  ·  1 episode'), findsOneWidget);
    expect(find.text('Not on your servers'), findsNWidgets(2));
    expect(find.byKey(const Key('anime-failure')), findsNothing);

    // Only what the library has can be opened.
    final absent = tester.widget<InkWell>(
      find.byKey(const Key('anime-195516')),
    );
    final present = tester.widget<InkWell>(find.byKey(const Key('anime-21')));
    expect(absent.onTap, isNull);
    expect(present.onTap, isNotNull);
  });

  testWidgets('says why there are no lists', (tester) async {
    await show(tester, library: const NoLibrary());

    expect(
      tester.widget<Text>(find.byKey(const Key('anime-failure'))).data,
      contains('error in the app'),
    );
    expect(find.text('Ask again'), findsOneWidget);
  });
}
