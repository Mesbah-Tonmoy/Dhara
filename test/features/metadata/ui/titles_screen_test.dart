import 'package:dhara/app.dart';
import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/core/images/remote_image.dart';
import 'package:dhara/core/secrets/secret_store.dart';
import 'package:dhara/core/settings/key_value_store.dart';
import 'package:dhara/core/settings/settings_controller.dart';
import 'package:dhara/features/browse/browse_controller.dart';
import 'package:dhara/features/home/home_controller.dart';
import 'package:dhara/features/indexer/index_controller.dart';
import 'package:dhara/features/metadata/anime_controller.dart';
import 'package:dhara/features/metadata/match_controller.dart';
import 'package:dhara/features/metadata/review_controller.dart';
import 'package:dhara/features/metadata/titles_controller.dart';
import 'package:dhara/features/metadata/tmdb_key.dart';
import 'package:dhara/features/metadata/ui/needs_review_screen.dart';
import 'package:dhara/features/metadata/ui/titles_screen.dart';
import 'package:dhara/features/my_list/my_list_controller.dart';
import 'package:dhara/features/player/resume_store.dart';
import 'package:dhara/features/sources/source.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:dhara/features/sources/source_test_controller.dart';
import 'package:dhara/features/sources/source_tester.dart';
import 'package:dhara/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Source _source(String id, {SourceType type = SourceType.h5ai}) => Source(
  id: id,
  name: 'Server $id',
  type: type,
  category: SourceCategory.mixed,
  baseUrls: [Uri.parse('http://10.0.0.1/$id/')],
);

/// Puts videos (name and size) into the index, in the folder [path] of the
/// source [sourceId], as a finished crawl would.
void _put(
  LibraryDb library,
  String sourceId,
  String path,
  Map<String, int?> files,
) {
  final db = library.db;
  db.execute(
    'INSERT INTO sources (source_id, crawl_started_at, crawl_finished_at) '
    'VALUES (?, 1, 2) ON CONFLICT (source_id) DO NOTHING',
    [sourceId],
  );
  db.execute(
    'INSERT INTO folders (source, url, path, depth, state) '
    'SELECT id, ?, ?, 1, 1 FROM sources WHERE source_id = ?',
    ['http://10.0.0.1/$sourceId/$path/', path, sourceId],
  );
  final folder = db.lastInsertRowId;
  for (final MapEntry(key: name, value: size) in files.entries) {
    db.execute(
      'INSERT INTO files (folder, name, url, size, added_at) '
      'VALUES (?, ?, ?, ?, 0)',
      [folder, name, 'http://10.0.0.1/$sourceId/$path/$name', size],
    );
  }
}

/// Shaped like TMDB's, made up.
final _token = 'eyJhbGciOiJIUzI1NiJ9.${'a' * 120}.${'b' * 43}';

/// The id of the title called [name].
Future<int> titleId(LibraryDb library, String name) async =>
    library.db.select('SELECT id FROM titles WHERE name = ?', [
          name,
        ]).single['id']
        as int;

void main() {
  late TmdbKeyController tmdbKey;
  late MatchController match;
  late ReviewController review;

  setUp(() {
    tmdbKey = TmdbKeyController(
      MemorySecretStore(),
      check: (key, kind) async => TmdbKeyCheck.accepted,
    );
    addTearDown(tmdbKey.dispose);
  });

  /// [home] with the controllers it looks for above it.
  Widget scoped(TitlesController titles, Widget home) => IndexScope(
    controller: titles.index,
    child: TitlesScope(
      controller: titles,
      child: TmdbKeyScope(
        controller: tmdbKey,
        child: MatchScope(
          controller: match,
          child: ReviewScope(
            controller: review,
            child: MaterialApp(theme: buildDharaTheme(), home: home),
          ),
        ),
      ),
    ),
  );

  /// The controllers that look titles up, over [library].
  void matching(LibraryWorker library, TitlesController titles) {
    match = MatchController(library: library, titles: titles, tmdbKey: tmdbKey);
    review = ReviewController(
      library: library,
      titles: titles,
      match: match,
      tmdbKey: tmdbKey,
    );
    addTearDown(() {
      review.dispose();
      match.dispose();
    });
  }

  /// The controllers over an index that [fill] has prepared, with the names
  /// already read. "flix" and "icc" are switched on; "media" is an Emby
  /// server.
  Future<TitlesController> prepare(
    WidgetTester tester,
    void Function(LibraryDb db) fill,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final db = LibraryDb.inMemory();
    addTearDown(db.close);
    fill(db);
    final store = SourceStore(
      starter: [
        _source('flix'),
        _source('icc'),
        _source('media', type: SourceType.emby),
      ],
    );
    final library = LocalLibrary(db);
    final index = IndexController(
      library: library,
      sources: store,
      deviceId: 'dhara-test',
    );
    final titles = TitlesController(library: library, index: index);
    addTearDown(() {
      titles.dispose();
      index.dispose();
    });
    // Reading the names takes real time, which a widget test does not have.
    await tester.runAsync(() async {
      await store.setEnabled(['flix', 'icc', 'media'], enabled: true);
      await index.load();
      await titles.refresh();
      matching(library, titles);
      await match.load();
    });
    return titles;
  }

  Future<TitlesController> show(
    WidgetTester tester,
    void Function(LibraryDb db) fill,
  ) async {
    final titles = await prepare(tester, fill);
    await tester.pumpWidget(scoped(titles, const TitlesScreen()));
    return titles;
  }

  Future<void> search(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('titles-search')), text);
    // The search waits until typing pauses.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
  }

  String card(WidgetTester tester, String key) => tester
      .widgetList<Text>(
        find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text)),
      )
      .map((text) => text.data)
      .join(' | ');

  void library(LibraryDb db) {
    _put(
      db,
      'flix',
      'English Movies/(2019)/Vivarium (2019) 720p [Dual Audio]',
      {
        'Vivarium (2019) 720p BluRay x264 ESub [Dual Audio]'
                '[Hindi 2.0+English 5.1] -mkvC.mkv':
            1086858240,
      },
    );
    _put(db, 'icc', 'Movies/English', {
      'Vivarium (2019) 1080p WEBRip.mkv': null,
      'Stillwater (2018) 1080p WEBDL.mkv': null,
    });
    _put(db, 'icc', 'Movies/Vivarium (2019)', {
      'Trailer - Vivarium (2019).mp4': null,
    });
    _put(db, 'icc', 'Tv Show/English/Some Show Season 01 (2019) Completed', {
      'Some Show S01E01_The Start.mkv': null,
      'Some Show S01E02.mkv': null,
    });
    _put(db, 'flix', 'TV/Some Show/Season 1', {
      'Some.Show.S01E02.720p.WEB.x264-GRP.mkv': 314629120,
      'Some.Show.S01E03.720p.WEB.x264-GRP.mkv': null,
    });
    _put(db, 'flix', 'TV/Some Show/Season 2', {
      'Some.Show.S02E01.720p.WEB.x264-GRP.mkv': null,
    });
    _put(db, 'icc', 'Fun Zone/Funny Vedio/WMV', {'Coins.wmv': null});
  }

  testWidgets('says how many films, shows and other videos there are', (
    tester,
  ) async {
    await show(tester, library);

    expect(card(tester, 'titles-films'), contains('| 2 |'));
    expect(card(tester, 'titles-shows'), contains('| 1 |'));
    expect(card(tester, 'titles-other'), contains('| 1 |'));
    expect(find.text('TYPE A TITLE TO SEARCH'), findsOneWidget);
  });

  testWidgets('shows a dash until the names have been read', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = SourceStore(starter: const []);
    final index = IndexController(
      library: const NoLibrary(),
      sources: store,
      deviceId: 'dhara-test',
    );
    final titles = TitlesController(library: const NoLibrary(), index: index);
    addTearDown(() {
      titles.dispose();
      index.dispose();
    });
    matching(const NoLibrary(), titles);
    await tester.pumpWidget(scoped(titles, const TitlesScreen()));
    expect(card(tester, 'titles-films'), contains('| – |'));

    await index.load();
    await tester.pump();

    expect(
      find.textContaining('could not be read because of an error'),
      findsOneWidget,
    );
  });

  testWidgets('finds titles while typing, with year and copies', (
    tester,
  ) async {
    await show(tester, library);

    await search(tester, 'viva');
    expect(find.text('Vivarium (2019)'), findsOneWidget);
    expect(find.text('2 copies'), findsOneWidget, reason: 'not the trailer');
    expect(find.text('1 TITLE'), findsOneWidget);

    await search(tester, 'some sh');
    expect(find.text('Some Show (2019)'), findsOneWidget);
    expect(find.text('5 videos'), findsOneWidget);

    await search(tester, 'coins');
    expect(find.text('NOTHING FOUND'), findsOneWidget);

    await search(tester, '');
    expect(find.text('TYPE A TITLE TO SEARCH'), findsOneWidget);
    expect(find.text('Some Show (2019)'), findsNothing);
  });

  testWidgets('searches again when names have been read meanwhile', (
    tester,
  ) async {
    late LibraryDb library;
    final titles = await show(tester, (db) {
      library = db;
      _put(db, 'icc', 'Movies/English', {'Vivarium (2019) 1080p.mkv': null});
    });
    await search(tester, 'viva');
    expect(find.text('1 copy'), findsOneWidget);

    _put(library, 'flix', 'Movies', {'Vivarium (2019) 720p.mkv': null});
    await tester.runAsync(() async {
      await titles.index.load();
      await titles.refresh();
    });
    await tester.pump();
    await tester.pump();

    expect(find.text('2 copies'), findsOneWidget);
  });

  testWidgets('opens from the rail and goes back to Home', (tester) async {
    final titles = await prepare(tester, library);
    final sources = titles.index.sources;
    final tests = SourceTestController(
      store: sources,
      tester: SourceTester(deviceId: 'dhara-test'),
    );
    addTearDown(tests.dispose);
    await tester.pumpWidget(
      DharaApp(
        settings: SettingsController(MemoryKeyValueStore()),
        resumeStore: ResumeStore(),
        sourceTests: tests,
        index: titles.index,
        titles: titles,
        tmdbKey: tmdbKey,
        match: match,
        review: review,
        anime: AnimeController(library: const NoLibrary()),
        home: HomeController(
          library: const NoLibrary(),
          titles: titles,
          match: match,
        ),
        myList: MyListController(library: const NoLibrary()),
        browse: BrowseController(library: const NoLibrary(), titles: titles),
      ),
    );

    await tester.tap(find.byKey(const Key('rail-titles')));
    await tester.pumpAndSettle();
    expect(find.text('Films and shows'), findsOneWidget);
    expect(card(tester, 'titles-films'), contains('| 2 |'));

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home')), findsOneWidget);
  });

  testWidgets('the TMDB key is added from here', (tester) async {
    await show(tester, library);
    await tester.runAsync(tmdbKey.load);
    await tester.pump();
    expect(find.text('Add TMDB key'), findsOneWidget);

    await tester.tap(find.byKey(const Key('titles-tmdb-key')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tmdb-key-field')), _token);
    await tester.tap(find.byKey(const Key('tmdb-key-save')));
    await tester.pumpAndSettle();
    expect(find.text('TMDB accepts this key.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tmdb-key-close')));
    await tester.pumpAndSettle();
    expect(find.text('TMDB key'), findsOneWidget);
    expect(find.text('Add TMDB key'), findsNothing);
    expect(tmdbKey.hasKey, isTrue);
  });

  testWidgets('shows how far matching is, and the poster of a match', (
    tester,
  ) async {
    late LibraryDb db;
    await show(tester, (made) {
      db = made;
      library(made);
    });
    expect(
      tester.widget<Text>(find.byKey(const Key('match-counts'))).data,
      endsWith('3 not looked up yet'),
    );
    expect(find.byKey(const Key('titles-review')), findsNothing);

    // As a run of matching leaves them.
    db.db
      ..execute(
        'UPDATE titles SET match_state = 1, tmdb_id = 9, poster_path = '
        "'/pViva.jpg' WHERE name = 'Vivarium'",
      )
      ..execute("UPDATE titles SET match_state = 3 WHERE name = 'Stillwater'")
      ..execute("UPDATE titles SET match_state = 2 WHERE name = 'Some Show'");
    await tester.runAsync(match.load);
    await tester.pump();

    expect(
      tester.widget<Text>(find.byKey(const Key('match-counts'))).data,
      '1 matched  ·  1 unsure  ·  1 not found  ·  0 not looked up yet',
    );
    await search(tester, 'viva');
    final poster = tester.widget<TmdbPicture>(
      find.descendant(
        of: find.byKey(Key('title-${(await titleId(db, 'Vivarium'))}')),
        matching: find.byType(TmdbPicture),
      ),
    );
    expect(poster.path, '/pViva.jpg');

    await tester.tap(find.text('Needs review (2)'));
    await tester.runAsync(review.load);
    await tester.pumpAndSettle();
    expect(find.byType(NeedsReviewScreen), findsOneWidget);
    expect(find.text('2 TITLES'), findsOneWidget);
  });
}
