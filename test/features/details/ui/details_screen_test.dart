import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/features/details/ui/copies_table.dart';
import 'package:dhara/features/details/ui/details_screen.dart';
import 'package:dhara/features/details/ui/episode_list.dart';
import 'package:dhara/features/home/ui/poster_card.dart';
import 'package:dhara/features/playback/copy_choice.dart';
import 'package:dhara/features/sources/source.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:dhara/shell/nav_rail.dart';
import 'package:dhara/shell/shell_controller.dart';
import 'package:dhara/widgets/buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/test_app.dart';

Source _server(String id) => Source(
  id: id,
  name: 'Server $id',
  type: SourceType.h5ai,
  category: SourceCategory.mixed,
  isp: 'ISP $id',
  baseUrls: [Uri.parse('http://10.0.0.1/$id/')],
);

/// "Vivarium" (title 1) with a copy on each of the servers "a" and "b",
/// and a trailer; two more thrillers; a show, "The Bay" (title 9).
LibraryDb _library({String scheme = 'http'}) {
  final library = LibraryDb.inMemory();
  final db = library.db;
  for (final (index, id) in ['a', 'b'].indexed) {
    db
      ..execute('INSERT INTO sources (id, source_id) VALUES (?, ?)', [
        index + 1,
        id,
      ])
      ..execute(
        'INSERT INTO folders (id, source, url, path, depth) '
        'VALUES (?, ?, ?, ?, 0)',
        [index + 1, index + 1, 'http://10.0.0.1/$id/', 'All'],
      );
  }
  void title(int id, int kind, String name, int year, {int votes = 100}) =>
      db.execute(
        'INSERT INTO titles (id, kind, name, year, tmdb_id, match_state, '
        'rating, votes, genres, language, original_name, overview, runtime, '
        "added_at) VALUES (?, ?, ?, ?, ?, 1, 6.1, ?, 'Thriller, Mystery', "
        "'en', ?, ?, 98, 0)",
        [id, kind, name, year, id, votes, 'Original $name', 'About $name.'],
      );
  var files = 0;
  void file(
    int title,
    int folder,
    String name, {
    int? height,
    int? size,
    int? season,
    int? episode,
    int? extra,
  }) {
    files++;
    db
      ..execute(
        'INSERT INTO files (id, folder, name, url, size, added_at) '
        'VALUES (?, ?, ?, ?, ?, 0)',
        [files, folder, name, '$scheme://10.0.0.1/f/$name', size],
      )
      ..execute(
        'INSERT INTO file_meta (file, parser, kind, title, season, episode, '
        'extra, height, codec, languages) '
        "VALUES (?, 1, ?, ?, ?, ?, ?, ?, 'hevc', 'Hindi,English')",
        [
          files,
          if (season == null) 0 else 1,
          title,
          season,
          episode,
          extra,
          height,
        ],
      );
  }

  title(1, 0, 'Vivarium', 2019);
  file(1, 1, 'vivarium.720p.mkv', height: 720, size: 800 * 1024 * 1024);
  file(1, 2, 'vivarium.2160p.mkv', height: 2160, size: 9 * 1024 * 1024 * 1024);
  file(1, 2, 'vivarium.trailer.mkv', height: 1080, extra: 1);
  title(2, 0, 'Loud Thriller', 2001, votes: 9000);
  file(2, 1, 'loud.mkv', height: 1080);
  title(3, 0, 'Quiet Thriller', 2020, votes: 12);
  file(3, 1, 'quiet.mkv', height: 1080);
  title(9, 1, 'The Bay', 2019);
  file(9, 1, 'bay.s01e01.mkv', height: 720, season: 1, episode: 1);
  file(9, 1, 'bay.s01e02.mkv', height: 720, season: 1, episode: 2);
  return library;
}

/// The app on [db] with both servers switched on, showing the page of the
/// title [id].
Future<SourceStore> _open(
  WidgetTester tester,
  LibraryDb db, {
  int id = 1,
  Map<String, (bool, int?)> tested = const {},
  Size window = const Size(1440, 900),
}) async {
  tester.view
    ..physicalSize = window
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final (:app, :sources) = testApp(
    db: db,
    sources: [_server('a'), _server('b')],
  );
  await sources.setEnabled(['a', 'b'], enabled: true);
  await sources.recordHealth({
    for (final MapEntry(:key, value: (reachable, ms)) in tested.entries)
      key: SourceHealth(
        checkedAt: DateTime(2026, 11, 15),
        reachable: reachable,
        readable: reachable,
        ping: ms == null ? null : Duration(milliseconds: ms),
      ),
  });
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
  final shell = ShellScope.read(tester.element(find.byType(NavRail)));
  shell.navigatorKey.currentState!.push(
    MaterialPageRoute<void>(builder: (_) => DetailsScreen(titleId: id)),
  );
  await tester.pumpAndSettle();
  return sources;
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

/// The file names of the copies, in the order they are listed.
List<String> _listed(WidgetTester tester) => [
  for (final copy
      in tester.widget<CopiesTable>(find.byType(CopiesTable)).copies)
    copy.name,
];

void main() {
  testWidgets('shows what is known of a film', (tester) async {
    await _open(tester, _library());

    expect(_text(tester, 'details-title'), 'Vivarium');
    expect(_text(tester, 'details-overview'), 'About Vivarium.');
    expect(find.text('MOVIE'), findsOneWidget);
    expect(find.text('THRILLER, MYSTERY'), findsOneWidget);
    expect(find.text('1h 38m'), findsOneWidget);
    expect(find.text('Original Vivarium'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Hindi, English'), findsWidgets);
    expect(find.text('Matched on TMDB'), findsOneWidget);
    expect(
      tester.widget<DharaButton>(find.byKey(const Key('details-play'))).label,
      'Play',
    );
    expect(
      tester.widget<DharaButton>(find.byKey(const Key('details-copies'))).label,
      '2 copies',
    );
  });

  testWidgets('names who made it and who is in it, once that was read', (
    tester,
  ) async {
    final db = _library();
    await _open(tester, db);
    expect(find.text('DIRECTOR'), findsOneWidget);
    expect(find.text('CAST'), findsOneWidget);

    db.db.execute(
      "UPDATE titles SET director = 'Lorcan Finnegan', "
      "actors = 'Imogen Poots, Jesse Eisenberg' WHERE id = 1",
    );
    db.db.execute(
      "UPDATE titles SET director = 'Daragh Carville' WHERE id = 9",
    );
    await _open(tester, db);
    expect(find.text('Lorcan Finnegan'), findsOneWidget);
    expect(find.text('Imogen Poots, Jesse Eisenberg'), findsOneWidget);

    await _open(tester, db, id: 9);
    expect(find.text('CREATED BY'), findsOneWidget);
    expect(find.text('Daragh Carville'), findsOneWidget);
  });

  testWidgets('lists the copies, the sharpest first, trailers last', (
    tester,
  ) async {
    await _open(tester, _library());

    expect(_listed(tester), [
      'vivarium.2160p.mkv',
      'vivarium.720p.mkv',
      'vivarium.trailer.mkv',
    ]);
    expect(
      _text(tester, 'details-copies-count'),
      '2 found; none of their servers has answered a test yet',
    );
    expect(find.text('Server b'), findsNWidgets(2));
    expect(find.text('h5ai · ISP b'), findsNWidgets(2));
    expect(find.text('4K'), findsWidgets);
    expect(find.text('HEVC'), findsNWidgets(3));
    expect(find.text('9.0 GB'), findsOneWidget);
    expect(find.text('800 MB'), findsOneWidget);
    expect(find.text('TRAILER'), findsOneWidget);
    expect(find.text('Not tested'), findsNWidgets(3));
    expect(find.text('BEST'), findsNothing);
  });

  testWidgets('a server that answered its test comes first and is marked', (
    tester,
  ) async {
    await _open(
      tester,
      _library(),
      tested: {'a': (true, 12), 'b': (false, null)},
    );

    expect(_listed(tester).take(2), [
      'vivarium.720p.mkv',
      'vivarium.2160p.mkv',
    ]);
    expect(find.text('BEST'), findsOneWidget);
    expect(find.text('12 ms'), findsOneWidget);
    expect(find.text('Offline'), findsNWidgets(2));
    expect(
      _text(tester, 'details-copies-count'),
      '2 found, on 1 server that answered the last test',
    );
    // The best one has the lit button.
    expect(
      tester.widget<DharaButton>(find.byKey(const Key('play-copy-1'))).style,
      DharaButtonStyle.primary,
    );
    expect(
      tester.widget<DharaButton>(find.byKey(const Key('play-copy-2'))).style,
      DharaButtonStyle.glass,
    );
  });

  testWidgets('follows a server test that ends while the page is open', (
    tester,
  ) async {
    final sources = await _open(tester, _library());
    expect(_listed(tester).first, 'vivarium.2160p.mkv');

    await sources.recordHealth({
      'a': SourceHealth(
        checkedAt: DateTime(2026, 11, 15),
        reachable: true,
        readable: true,
        ping: const Duration(milliseconds: 250),
      ),
    });
    await tester.pumpAndSettle();

    expect(_listed(tester).first, 'vivarium.720p.mkv');
    expect(find.text('250 ms'), findsOneWidget);
  });

  testWidgets('a film left unfinished offers to resume it', (tester) async {
    final db = _library();
    db.db
      ..execute(
        'INSERT INTO watch_history (url, watched_at, position_ms, '
        "duration_ms) VALUES ('http://10.0.0.1/f/vivarium.720p.mkv', 5, "
        '1000, 4000)',
      )
      ..execute(
        'INSERT INTO playback (url, position_ms, duration_ms, updated_at) '
        "VALUES ('http://10.0.0.1/f/vivarium.720p.mkv', 1000, 4000, 5)",
      );
    await _open(tester, db);

    expect(
      tester.widget<DharaButton>(find.byKey(const Key('details-play'))).label,
      'Resume',
    );
    expect(
      tester.widget<DharaButton>(find.byKey(const Key('play-copy-1'))).label,
      'Resume',
    );
    expect(
      tester.widget<DharaButton>(find.byKey(const Key('play-copy-2'))).label,
      'Play',
    );
  });

  testWidgets('My List is kept in the library', (tester) async {
    final db = _library();
    await _open(tester, db);

    await tester.tap(find.byKey(const Key('my-list-button')));
    await tester.pumpAndSettle();

    expect(find.text('In My List'), findsOneWidget);
    expect(db.db.select('SELECT title FROM my_list').single.values, [1]);
  });

  testWidgets('offers more like it, and each opens its own page', (
    tester,
  ) async {
    await _open(tester, _library(), window: const Size(1440, 1600));

    final more = find.descendant(
      of: find.byKey(const Key('details-similar')),
      matching: find.byType(PosterCard),
    );
    expect(
      [for (final card in tester.widgetList<PosterCard>(more)) card.title.name],
      ['Loud Thriller', 'Quiet Thriller'],
    );

    await tester.tap(more.first);
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('details-title')).last).data,
      'Loud Thriller',
    );

    await tester.tap(find.byKey(const Key('shell-back')));
    await tester.pumpAndSettle();
    expect(_text(tester, 'details-title'), 'Vivarium');
  });

  testWidgets('Play says so when no copy can be played', (tester) async {
    await _open(tester, _library(scheme: 'ftp'));

    expect(find.text('Needs sign-in'), findsNothing);
    expect(find.text('Cannot be played'), findsNWidgets(3));
    await tester.tap(find.byKey(const Key('details-play')));
    await tester.pump();

    expect(
      find.textContaining('has no copy that can be played from here.'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('Fix match asks which film it is', (tester) async {
    await _open(tester, _library());

    await tester.tap(find.byKey(const Key('details-fix-match')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('review-name')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const Key('review-name')),
              matching: find.byType(TextField),
            ),
          )
          .controller!
          .text,
      'Vivarium',
    );
    await tester.tap(find.byKey(const Key('review-close')));
    await tester.pumpAndSettle();
    expect(_text(tester, 'details-title'), 'Vivarium');
  });

  testWidgets('says so when a title is not in the library any more', (
    tester,
  ) async {
    await _open(tester, _library(), id: 404);

    expect(find.byKey(const Key('details-gone')), findsOneWidget);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(DetailsScreen), findsNothing);
  });

  testWidgets('says so when no enabled server holds it any more', (
    tester,
  ) async {
    final db = _library();
    db.db.execute('DELETE FROM files WHERE id IN (1, 2, 3)');
    db.db.execute('INSERT INTO my_list (title, added_at) VALUES (1, 0)');
    await _open(tester, db);

    expect(_text(tester, 'details-title'), 'Vivarium');
    expect(find.byKey(const Key('details-no-copies')), findsOneWidget);
    expect(find.byType(CopiesTable), findsNothing);
    expect(find.text('In My List'), findsOneWidget);
  });

  testWidgets('fits a narrow window without its poster', (tester) async {
    await _open(tester, _library(), window: const Size(940, 600));

    expect(tester.takeException(), isNull);
    expect(_text(tester, 'details-title'), 'Vivarium');
  });

  group('a show', () {
    /// Adds a video of "The Bay" on the server with the row [server].
    void video(
      LibraryDb db,
      int id,
      String name, {
      int? season,
      int? episode,
      int server = 1,
      int height = 720,
      int? extra,
    }) => db.db
      ..execute(
        'INSERT INTO files (id, folder, name, url, added_at) '
        'VALUES (?, ?, ?, ?, 0)',
        [id, server, name, 'http://10.0.0.1/f/$name'],
      )
      ..execute(
        'INSERT INTO file_meta (file, parser, kind, title, season, episode, '
        'extra, height) VALUES (?, 1, 1, 9, ?, ?, ?, ?)',
        [id, season, episode, extra, height],
      );

    void watched(LibraryDb db, String name, {required int at, int? left}) {
      db.db.execute(
        'INSERT INTO watch_history '
        '(url, watched_at, position_ms, duration_ms, finished) '
        'VALUES (?, ?, ?, 4000, ?)',
        ['http://10.0.0.1/f/$name', at, left ?? 4000, left == null ? 1 : 0],
      );
      if (left != null) {
        db.db.execute(
          'INSERT INTO playback (url, position_ms, duration_ms, updated_at) '
          'VALUES (?, ?, 4000, ?)',
          ['http://10.0.0.1/f/$name', left, at],
        );
      }
    }

    List<String> lines(WidgetTester tester) => [
      for (final line
          in find
              .byWidgetPredicate(
                (widget) =>
                    widget.key is ValueKey<String> &&
                    (widget.key! as ValueKey<String>).value.startsWith(
                      'episode-',
                    ) &&
                    !(widget.key! as ValueKey<String>).value.startsWith(
                      'episode-co',
                    ),
              )
              .evaluate())
        (line.widget.key! as ValueKey<String>).value,
    ];

    testWidgets('lists its episodes, with what TMDB says of them', (
      tester,
    ) async {
      final db = _library();
      db.db.execute(
        'INSERT INTO episodes (title, season, episode, name, overview, '
        "runtime) VALUES (9, 1, 2, 'Second One', 'More happens.', 44)",
      );
      await _open(tester, db, id: 9);

      expect(_text(tester, 'details-title'), 'The Bay');
      expect(find.text('SERIES'), findsOneWidget);
      expect(lines(tester), ['episode-1-1', 'episode-1-2']);
      expect(_text(tester, 'episode-count'), '2 episodes');
      expect(find.text('Episode 1'), findsOneWidget);
      expect(find.text('Second One'), findsOneWidget);
      expect(find.text('More happens.'), findsOneWidget);
      expect(find.text('44 min · S1 · E2'), findsOneWidget);
      expect(find.text('S1 · E1'), findsOneWidget);
      // One season: nothing to choose between.
      expect(find.byKey(const Key('season-1')), findsNothing);
      expect(find.byType(CopiesTable), findsNothing);
      expect(
        tester.widget<DharaButton>(find.byKey(const Key('details-play'))).label,
        'Play S1 · E1',
      );
      expect(find.text('UP NEXT'), findsOneWidget);
    });

    testWidgets('has a chip for every season, and shows the one picked', (
      tester,
    ) async {
      final db = _library();
      video(db, 20, 'bay.s02e01.mkv', season: 2, episode: 1);
      video(db, 21, 'bay.s02e02.mkv', season: 2, episode: 2);
      video(db, 22, 'bay.s02e03.mkv', season: 2, episode: 3);
      video(db, 23, 'bay.special.mkv', season: 0, episode: 1);
      db.db.execute(
        "INSERT INTO seasons (title, season, name) VALUES (9, 2, 'The Tide')",
      );
      await _open(tester, db, id: 9);

      expect(find.text('Specials'), findsOneWidget);
      expect(find.text('Season 1'), findsOneWidget);
      expect(find.text('The Tide'), findsOneWidget);
      expect(lines(tester), ['episode-1-1', 'episode-1-2']);

      await tester.tap(find.byKey(const Key('season-2')));
      await tester.pumpAndSettle();

      expect(lines(tester), ['episode-2-1', 'episode-2-2', 'episode-2-3']);
      expect(_text(tester, 'episode-count'), '3 episodes');
    });

    testWidgets('opens on the season that is being watched, and marks '
        'what was', (tester) async {
      final db = _library();
      video(db, 20, 'bay.s02e01.mkv', season: 2, episode: 1);
      video(db, 21, 'bay.s02e02.mkv', season: 2, episode: 2);
      watched(db, 'bay.s02e01.mkv', at: 100);
      watched(db, 'bay.s02e02.mkv', at: 200, left: 1000);
      await _open(tester, db, id: 9);

      expect(lines(tester), ['episode-2-1', 'episode-2-2']);
      expect(find.text('WATCHED'), findsOneWidget);
      expect(find.text('CONTINUE'), findsOneWidget);
      expect(
        tester.widget<DharaButton>(find.byKey(const Key('details-play'))).label,
        'Resume S2 · E2',
      );
      expect(
        tester
            .widget<DharaButton>(find.byKey(const Key('details-copies')))
            .label,
        'Copies for S2 · E2',
      );
    });

    testWidgets('an episode lists its copies in a side sheet, the best '
        'first', (tester) async {
      final db = _library();
      video(
        db,
        20,
        'bay.s01e02.1080p.mkv',
        season: 1,
        episode: 2,
        server: 2,
        height: 1080,
      );
      await _open(tester, db, id: 9);
      expect(find.text('2 copies'), findsOneWidget);

      await tester.tap(find.byKey(const Key('episode-copies-1-2')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('copies-sheet')), findsOneWidget);
      expect(
        _text(tester, 'copies-sheet-subtitle'),
        'S1 · E2 · the best copy first',
      );
      expect(_listed(tester), ['bay.s01e02.1080p.mkv', 'bay.s01e02.mkv']);
      expect(find.byKey(const Key('play-copy-20')), findsOneWidget);

      await tester.tap(find.byKey(const Key('copies-sheet-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('copies-sheet')), findsNothing);
      expect(_text(tester, 'details-title'), 'The Bay');
    });

    testWidgets('the button at the top lists the copies of the episode '
        'that is next', (tester) async {
      await _open(tester, _library(), id: 9);

      await tester.tap(find.byKey(const Key('details-copies')));
      await tester.pumpAndSettle();

      expect(
        _text(tester, 'copies-sheet-subtitle'),
        'S1 · E1 · the best copy first',
      );
      // Esc closes it, like any dialog.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('copies-sheet')), findsNothing);
    });

    testWidgets('what is not an episode is listed apart', (tester) async {
      final db = _library();
      video(db, 20, 'bay.behind.the.scenes.mkv');
      video(db, 21, 'bay.trailer.mkv', extra: 1);
      await _open(tester, db, id: 9, window: const Size(1440, 1600));

      expect(lines(tester), ['episode-1-1', 'episode-1-2']);
      expect(find.text('Other videos'), findsOneWidget);
      expect(_listed(tester), ['bay.behind.the.scenes.mkv', 'bay.trailer.mkv']);
    });

    testWidgets('an episode that cannot be played says so', (tester) async {
      await _open(tester, _library(scheme: 'ftp'), id: 9);

      expect(find.text('S1 · E1 · cannot be played from here'), findsOneWidget);
      await tester.tap(find.byKey(const Key('episode-1-1')));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    test('a season goes by its name, or its number', () {
      expect(seasonLabel(2, const {}), 'Season 2');
      expect(seasonLabel(2, const {2: 'The Tide'}), 'The Tide');
      expect(seasonLabel(0, const {}), 'Specials');
      expect(seasonLabel(null, const {}), 'Episodes');
    });
  });

  group('labels', () {
    test('a size is told the way people say it', () {
      expect(sizeLabel(1717986918), '1.6 GB');
      expect(sizeLabel(700 * 1024 * 1024), '700 MB');
      expect(sizeLabel(900), '1 KB');
    });

    test('a language code is given its name, if it has one here', () {
      expect(languageName('bn'), 'Bangla');
      expect(languageName('xx'), 'XX');
    });

    test('a server answers fast, slowly, or not at all', () {
      expect(CopyReach.values, [
        CopyReach.offline,
        CopyReach.unknown,
        CopyReach.online,
      ]);
    });
  });
}
