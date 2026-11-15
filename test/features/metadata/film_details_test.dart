import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/core/secrets/secret_store.dart';
import 'package:dhara/features/details/details_store.dart';
import 'package:dhara/features/indexer/index_controller.dart';
import 'package:dhara/features/metadata/episodes_controller.dart';
import 'package:dhara/features/metadata/film_details_controller.dart';
import 'package:dhara/features/metadata/film_details_store.dart';
import 'package:dhara/features/metadata/match_controller.dart';
import 'package:dhara/features/metadata/match_store.dart';
import 'package:dhara/features/metadata/titles_controller.dart';
import 'package:dhara/features/metadata/tmdb_client.dart';
import 'package:dhara/features/metadata/tmdb_key.dart';
import 'package:dhara/features/metadata/video_identity.dart';
import 'package:dhara/features/sources/source.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_tmdb.dart';
import '../../support/local_server.dart';

const _apiKey = '0123456789abcdef0123456789abcdef';

var _urls = 0;

/// Puts videos into the index, in the folder [path] of the source "icc".
void _put(LibraryDb library, (String, List<String>) files) {
  final (path, names) = files;
  final db = library.db;
  db.execute(
    'INSERT INTO sources (source_id, crawl_started_at, crawl_finished_at) '
    "VALUES ('icc', 1, 2) ON CONFLICT (source_id) DO NOTHING",
  );
  db.execute(
    'INSERT INTO folders (source, url, path, depth, state) '
    "SELECT id, ?, ?, 1, 1 FROM sources WHERE source_id = 'icc'",
    ['http://icc.test/${_urls++}/$path/', path],
  );
  final folder = db.lastInsertRowId;
  for (final name in names) {
    db.execute(
      'INSERT INTO files (folder, name, url, added_at) VALUES (?, ?, ?, 0)',
      [folder, name, 'http://icc.test/${_urls++}/$name'],
    );
  }
}

/// Each title by name: genres, length, director, cast, whether its page
/// was read.
Map<String, List<Object?>> _details(LibraryDb library, Object? _) => {
  for (final row in library.db.select(
    'SELECT name, genres, runtime, director, actors, details_at IS NOT NULL '
    'AS read FROM titles ORDER BY name',
  ))
    row['name'] as String: row.values.sublist(1),
};

void _execute(LibraryDb library, String sql) => library.db.execute(sql);

void main() {
  late LocalServer server;
  late FakeTmdb tmdb;
  late LibraryDb db;
  late LibraryWorker library;
  late IndexController index;
  late TitlesController titles;
  late MatchController match;
  late FilmDetailsController films;
  late EpisodesController episodes;

  Future<void> open({String? key = _apiKey}) async {
    db = LibraryDb.inMemory();
    library = LocalLibrary(db);
    final sources = SourceStore(
      starter: [
        Source(
          id: 'icc',
          name: 'ICC',
          type: SourceType.directoryListing,
          category: SourceCategory.mixed,
          baseUrls: [Uri.parse('http://10.0.0.1/icc/')],
        ),
      ],
    );
    await sources.setEnabled(['icc'], enabled: true);
    index = IndexController(
      library: library,
      sources: sources,
      deviceId: 'dhara-test',
    );
    titles = TitlesController(library: library, index: index);
    final secrets = MemorySecretStore();
    if (key != null) await secrets.write('tmdb', key);
    final tmdbKey = TmdbKeyController(secrets);
    await tmdbKey.load();
    match = MatchController(
      library: library,
      titles: titles,
      tmdbKey: tmdbKey,
      tmdbUrl: tmdb.url,
      tmdbRetries: 0,
    );
    films = FilmDetailsController(
      library: library,
      match: match,
      tmdbKey: tmdbKey,
      tmdbUrl: tmdb.url,
      tmdbRetries: 0,
    );
    episodes = EpisodesController(
      library: library,
      match: match,
      tmdbKey: tmdbKey,
      tmdbUrl: tmdb.url,
      tmdbRetries: 0,
    );
    addTearDown(() {
      episodes.dispose();
      films.dispose();
      match.dispose();
      titles.dispose();
      index.dispose();
      db.close();
    });
  }

  Future<void> put(String path, List<String> names) =>
      library.run(_put, (path, names));

  /// Reads the names, matches the titles and lets the details follow.
  Future<void> matchAll() async {
    await index.load();
    await titles.refresh();
    await pumpEventQueue();
    await match.start();
    await pumpEventQueue();
    await films.refresh();
    await episodes.refresh();
  }

  Future<Map<String, List<Object?>>> details() => library.run(_details, null);

  List<String> pagesAsked() => [
    for (final request in tmdb.asked)
      if (request.startsWith('movie/')) request,
  ];

  setUp(() async {
    server = await LocalServer.start();
    tmdb = FakeTmdb(server)
      ..addFilm(1, 'Stillwater', 2018)
      ..addFilm(2, 'The Glass Harbor', 2019)
      ..addShow(
        70001,
        'The Quiet Signal',
        2017,
        seasons: {
          1: ['Static'],
        },
      );
  });

  tearDown(() => server.close());

  test('reads the page of every matched film once', () async {
    await open();
    await put('Movies', [
      'Stillwater (2018).mkv',
      'The Glass Harbor (2019).mkv',
      'Nobody Knows This One (2001).mkv',
    ]);

    await matchAll();

    expect(films.isFetching, isFalse);
    expect(films.failed, isFalse);
    expect((films.filmsDone, films.filmsToDo), (2, 2));
    final found = await details();
    expect(found['Stillwater'], [
      'Thriller, Science Fiction',
      91,
      'Director of Stillwater',
      'Lead of Stillwater, Second  of Stillwater',
      1,
    ]);
    expect(found['The Glass Harbor']![1], 92);
    expect(found['Nobody Knows This One'], [null, null, null, null, 0]);
    expect(pagesAsked().toSet(), {'movie/1', 'movie/2'});

    // Nothing is asked twice.
    final asked = tmdb.asked.length;
    await films.refresh();
    expect(tmdb.asked, hasLength(asked));
    expect((films.filmsDone, films.filmsToDo), (0, 0));
  });

  test('a show gets its creators and cast with its episodes', () async {
    await open();
    await put('Tv/The Quiet Signal Season 1', ['The Quiet Signal S01E01.mkv']);

    await matchAll();

    expect((await details())['The Quiet Signal'], [
      'Drama, Mystery',
      null,
      'Creator of The Quiet Signal',
      'Star of The Quiet Signal',
      1,
    ]);
    expect(pagesAsked(), isEmpty, reason: 'a show is not a film');
  });

  test('a show read before the people were kept is read once more', () async {
    await open();
    await put('Tv/The Quiet Signal Season 1', ['The Quiet Signal S01E01.mkv']);
    await matchAll();
    // As an older build left it.
    await library.run(
      _execute,
      'UPDATE titles SET details_at = NULL, director = NULL, actors = NULL',
    );
    final asked = tmdb.asked.length;

    await episodes.refresh();

    expect(tmdb.asked.length, greaterThan(asked));
    expect(
      (await details())['The Quiet Signal']![2],
      'Creator of The Quiet Signal',
    );
    final again = tmdb.asked.length;
    await episodes.refresh();
    expect(tmdb.asked, hasLength(again));
  });

  test('does nothing without a key', () async {
    await open(key: null);
    await put('Movies', ['Stillwater (2018).mkv']);
    await index.load();
    await titles.refresh();
    await library.run(
      _execute,
      'UPDATE titles SET tmdb_id = 1, match_state = 1',
    );

    await films.refresh();

    expect(tmdb.asked, isEmpty);
    expect(films.failed, isFalse);
  });

  test('a film TMDB no longer has is noted, not asked for again', () async {
    await open();
    await put('Movies', ['Stillwater (2018).mkv']);
    await index.load();
    await titles.refresh();
    await library.run(
      _execute,
      'UPDATE titles SET tmdb_id = 999, match_state = 1',
    );

    await films.refresh();

    expect((await details())['Stillwater'], [null, null, null, null, 1]);
    expect(films.failed, isFalse);
  });

  test('says so when TMDB cannot be asked, and goes on next time', () async {
    await open();
    await put('Movies', [
      'Stillwater (2018).mkv',
      'The Glass Harbor (2019).mkv',
    ]);
    await index.load();
    await titles.refresh();
    await pumpEventQueue();
    await match.start();
    await pumpEventQueue();
    await films.refresh();
    await library.run(_execute, 'UPDATE titles SET details_at = NULL');
    tmdb.failWith = 500;

    await films.refresh();

    expect(films.failed, isTrue);
    expect((await details())['Stillwater']!.last, 0);

    tmdb.failWith = null;
    await films.refresh();
    expect(films.failed, isFalse);
    expect((await details())['Stillwater']!.last, 1);
  });

  test('a title matched to another film has its page read again', () async {
    await open();
    await put('Movies', ['Stillwater (2018).mkv']);
    await matchAll();
    final id = db.db.select('SELECT id FROM titles').single['id'] as int;
    expect((await details())['Stillwater']!.last, 1);

    // The same film again: nothing changes.
    MatchStore(db).apply(
      id,
      const TmdbCandidate(id: 1, kind: TitleKind.movie, title: 'Stillwater'),
      confidence: 100,
      byHand: true,
    );
    expect((await details())['Stillwater']!.last, 1);

    MatchStore(db).apply(
      id,
      const TmdbCandidate(
        id: 2,
        kind: TitleKind.movie,
        title: 'The Glass Harbor',
      ),
      confidence: 100,
      byHand: true,
    );
    expect((await details())['The Glass Harbor']!.last, 0);

    await films.refresh();
    expect(
      (await details())['The Glass Harbor']![2],
      'Director of The Glass Harbor',
    );
  });

  test('the page of a title carries who made it and who is in it', () async {
    await open();
    await put('Movies', ['Stillwater (2018).mkv']);
    await matchAll();
    final id = db.db.select('SELECT id FROM titles').single['id'] as int;

    final page = DetailsStore(db, sourceIds: ['icc']).page(id)!;

    expect(page.makers, ['Director of Stillwater']);
    expect(page.cast, ['Lead of Stillwater', 'Second  of Stillwater']);
    expect(page.title.runtime, 91);
    expect(page.title.genres, ['Thriller', 'Science Fiction']);
  });

  group('FilmDetailsStore', () {
    test('lists the matched films that are due, a page at a time', () async {
      await open();
      await put('Movies', [
        for (var i = 1; i <= 5; i++) 'Film Number $i (200$i).mkv',
      ]);
      await index.load();
      await titles.refresh();
      await library.run(
        _execute,
        'UPDATE titles SET tmdb_id = id + 100, match_state = 1 WHERE id != 3',
      );
      final store = FilmDetailsStore(db);

      expect(store.countToFetch(), 4);
      final first = store.filmsToFetch(limit: 3);
      expect([for (final film in first) film.title], [1, 2, 4]);
      expect(first.first.tmdbId, 101);
      expect([for (final f in store.filmsToFetch(after: 4)) f.title], [5]);

      store.saveFilm(first.first, null);
      expect(store.countToFetch(), 3);
    });
  });
}
