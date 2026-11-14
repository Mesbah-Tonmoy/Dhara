import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/core/secrets/secret_store.dart';
import 'package:dhara/features/indexer/index_controller.dart';
import 'package:dhara/features/metadata/match_controller.dart';
import 'package:dhara/features/metadata/match_store.dart';
import 'package:dhara/features/metadata/titles_controller.dart';
import 'package:dhara/features/metadata/tmdb_key.dart';
import 'package:dhara/features/sources/source.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_tmdb.dart';
import '../../support/local_server.dart';

const _apiKey = '0123456789abcdef0123456789abcdef';

var _urls = 0;

/// Puts videos into the index, in the folder [path] of the source "icc".
/// A top-level function, so that it can run in the library isolate too.
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

void _execute(LibraryDb library, String sql) => library.db.execute(sql);

List<List<Object?>> _titles(LibraryDb library, Object? _) => [
  for (final row in library.db.select(
    'SELECT name, year, tmdb_id, match_state, confidence, poster_path, '
    '(SELECT count(*) FROM file_meta m WHERE m.title = titles.id) AS copies '
    'FROM titles ORDER BY name',
  ))
    row.values,
];

void main() {
  late LocalServer server;
  late FakeTmdb tmdb;
  late LibraryWorker library;
  late IndexController index;
  late TitlesController titles;
  late TmdbKeyController tmdbKey;
  late MatchController match;

  /// Opens the controllers over [worker]; [key] is the saved TMDB key.
  Future<void> open(LibraryWorker worker, {String? key = _apiKey}) async {
    library = worker;
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
    tmdbKey = TmdbKeyController(secrets, check: (_, _) async => throw 'unused');
    await tmdbKey.load();
    match = MatchController(
      library: library,
      titles: titles,
      tmdbKey: tmdbKey,
      tmdbUrl: tmdb.url,
      tmdbRetries: 0,
    );
    addTearDown(() {
      match.dispose();
      titles.dispose();
      index.dispose();
    });
  }

  Future<void> put(String path, List<String> names) =>
      library.run(_put, (path, names));

  /// Reads the index again, as after a crawl, and the names in it.
  Future<void> readNames() async {
    await index.load();
    await titles.refresh();
    // What the end of reading sets off.
    await pumpEventQueue();
  }

  /// The titles by name: year, TMDB id, state, confidence, poster, copies.
  Future<Map<String, List<Object?>>> stored() async => {
    for (final row in await library.run(_titles, null))
      row.first! as String: row.sublist(1),
  };

  setUp(() async {
    server = await LocalServer.start();
    tmdb = FakeTmdb(server);
  });

  tearDown(() => server.close());

  group('a run', () {
    setUp(() => open(LocalLibrary(LibraryDb.inMemory())));

    test('gives matched titles what TMDB knows about them', () async {
      tmdb.addFilm(90001, 'The Glass Harbor', 2019);
      await put('Movies/English', ['the.glass.harbor.2019.720p.BluRay.mkv']);
      await readNames();
      expect(match.counts!.pending, 1);
      expect(match.isRunning, isFalse, reason: 'the first run is asked for');

      final run = match.start();
      expect(match.isRunning, isTrue);
      await run;

      expect(match.isRunning, isFalse);
      expect(match.lastEnd, MatchEnd.finished);
      expect(await stored(), {
        'The Glass Harbor': [2019, 90001, 1, 100, '/poster90001.jpg', 1],
      });
      final progress = match.progress!;
      expect((progress.done, progress.total), (1, 1));
      expect((progress.matched, progress.unsure, progress.notFound), (1, 0, 0));
      final counts = match.counts!;
      expect((counts.matched, counts.pending), (1, 0));
      expect(tmdb.asked, ['movie|the glass harbor|2019']);
    });

    test('tells sure, unsure and not found apart', () async {
      tmdb
        ..addFilm(1, 'Stillwater', 2018)
        ..addFilm(2, 'Hell', 2011)
        ..addFilm(3, 'Hell', 2005)
        ..addShow(4, 'The Quiet Signal', 2017);
      await put('Movies/English', [
        'Stillwater (2018) 1080p WEBDL.mkv',
        'Hell.mkv',
        'Nothing Like This (2001) 720p.mkv',
      ]);
      await put('Tv/The Quiet Signal Season 02 (2019) Completed', [
        'The Quiet Signal S02E01.mkv',
      ]);
      await readNames();

      await match.start();

      final found = await stored();
      expect(found['Stillwater'], [2018, 1, 1, 100, '/poster1.jpg', 1]);
      expect(found['Hell']!.sublist(2, 4), [
        2,
        78,
      ], reason: 'two films of that name, no year to tell them apart');
      expect(found['Nothing Like This']!.sublist(1, 3), [null, 3]);
      expect(found['The Quiet Signal']!.take(3), [2017, 4, 1]);
      final progress = match.progress!;
      expect((progress.matched, progress.unsure, progress.notFound), (2, 1, 1));
      final counts = match.counts!;
      expect((counts.matched, counts.unsure, counts.notFound), (2, 1, 1));
      expect(counts.toReview, 2);
      expect(tmdb.asked, contains('tv|the quiet signal|2019'));
    });

    test('asks again without the year, and by the name of the file', () async {
      tmdb
        ..addFilm(1, 'Calcutta 71', 1972)
        ..addFilm(2, 'Silent Hill', 2006);
      await put('Movies/Calcutta 71 (1971) 1080p', ['calcutta.mkv']);
      await put('English Movies/(2006)/Silent Hills (2006) 720p', [
        'Silent.Hill.2006.BluRay.720p.x264.YIFY.mp4',
      ]);
      await readNames();

      await match.start();

      final found = await stored();
      expect(found['Calcutta 71']!.take(3), [1972, 1, 1]);
      expect(found['Silent Hill']!.take(3), [2006, 2, 1]);
      expect(
        tmdb.asked,
        containsAll([
          'movie|calcutta 71|1971',
          'movie|calcutta 71|',
          'movie|silent hills|2006',
          'movie|silent hills|',
          'movie|silent hill|2006',
        ]),
      );
    });

    test('makes two spellings of one film one title', () async {
      tmdb.addFilm(5, 'Boyka: Undisputed IV', 2016);
      await put('Movies/English', ['Boyka Undisputed (2016) 1080p.mkv']);
      await put('English Movies/(2016)/Boyka-Undisputed IV (2016) 720p', [
        'boyka.mkv',
      ]);
      await readNames();
      expect((await stored()).length, 2);

      await match.start();

      expect(await stored(), {
        'Boyka: Undisputed IV': [2016, 5, 1, isA<int>(), '/poster5.jpg', 2],
      });
      expect((await titles.search('boyka')).single.copies, 2);
    });

    test('does not ask twice for what it was told', () async {
      tmdb.addFilm(1, 'Stillwater', 2018);
      await put('Movies/English', ['Nothing Like This (2001) 720p.mkv']);
      await readNames();
      await match.start();
      final asked = tmdb.asked.length;

      // The same film turns up on another server under the same name.
      await put('Movies/Hindi', ['Nothing Like This (2001) 1080p.mkv']);
      await readNames();
      await match.start();

      expect(tmdb.asked, hasLength(asked));
    });
  });

  group('a run that cannot finish', () {
    test('without a key does nothing', () async {
      await open(LocalLibrary(LibraryDb.inMemory()), key: null);
      await put('Movies', ['Stillwater (2018).mkv']);
      await readNames();

      await match.start();

      expect(match.lastEnd, MatchEnd.noKey);
      expect(tmdb.asked, isEmpty);
      expect(match.counts!.pending, 1);
    });

    test('stops at a key TMDB refuses', () async {
      await open(LocalLibrary(LibraryDb.inMemory()));
      tmdb.failWith = 401;
      await put('Movies', ['A (2001).mkv', 'B (2002).mkv', 'C (2003).mkv']);
      await readNames();

      await match.start();

      expect(match.lastEnd, MatchEnd.keyRefused);
      expect(match.counts!.pending, 3);
      expect(match.progress!.done, 0);
    });

    test('gives up when TMDB keeps failing, and keeps what it has', () async {
      await open(LocalLibrary(LibraryDb.inMemory()));
      tmdb.addFilm(1, 'A', 2001);
      await put('Movies', [
        'A (2001).mkv',
        for (var i = 0; i < 60; i++) 'Film Number $i (2001).mkv',
      ]);
      await readNames();
      var seen = 0;
      match.addListener(() {
        // Out of order once a few titles have been looked up.
        if (match.progress!.done >= 5 && seen++ == 0) tmdb.failWith = 500;
      });

      await match.start();

      expect(match.lastEnd, MatchEnd.unreachable);
      final counts = match.counts!;
      expect(counts.matched, 1);
      expect(counts.notFound, greaterThanOrEqualTo(4));
      expect(counts.pending, inInclusiveRange(1, 55));

      // Next time it carries on with what is left.
      tmdb.failWith = null;
      await match.start();
      expect(match.lastEnd, MatchEnd.finished);
      expect(match.counts!.pending, 0);
    });

    test('can be stopped and carried on', () async {
      await open(LocalLibrary(LibraryDb.inMemory()));
      await put('Movies', [
        for (var i = 0; i < 80; i++) 'Film Number $i (2001).mkv',
      ]);
      await readNames();
      var stopped = false;
      match.addListener(() {
        if (stopped || !match.isRunning || match.progress!.done < 4) return;
        stopped = true;
        match.stop();
      });

      await match.start();

      expect(match.lastEnd, MatchEnd.stopped);
      expect(match.isStopping, isFalse);
      final left = match.counts!.pending;
      expect(left, inInclusiveRange(1, 76));

      await match.start();
      expect(match.lastEnd, MatchEnd.finished);
      expect(match.counts!.pending, 0);
      expect(match.counts!.notFound, 80);
    });
  });

  group('what was looked up before', () {
    setUp(() => open(LocalLibrary(LibraryDb.inMemory())));

    test('is judged again from the answers kept, without asking', () async {
      tmdb
        ..addFilm(1, 'Stillwater', 2018)
        ..addFilm(2, 'The 51st State', 2001);
      await put('Movies/English', [
        'Stillwater (2018) 1080p WEBDL.mkv',
        'Nothing Like This (2001) 720p.mkv',
      ]);
      await readNames();
      await match.start();
      // As older rules left them: one not found, one unsure.
      await library.run(
        _execute,
        'UPDATE titles SET match_state = 3, tmdb_id = NULL, '
        "poster_path = NULL WHERE name = 'Stillwater'",
      );
      await library.run(
        _execute,
        "UPDATE titles SET match_state = 2 WHERE name = 'Nothing Like This'",
      );
      final asked = tmdb.asked.length;

      await match.start();

      expect(tmdb.asked, hasLength(asked));
      final found = await stored();
      expect(found['Stillwater'], [2018, 1, 1, 100, '/poster1.jpg', 1]);
      // Still nothing that fits: left as it was.
      expect(found['Nothing Like This']!.sublist(1, 3), [null, 2]);
      expect(match.lastEnd, MatchEnd.finished);
    });

    test('says nothing about time left when no run is under way', () async {
      expect(match.timeLeft, isNull);
      await put('Movies', ['Stillwater (2018).mkv']);
      await readNames();
      await match.start();
      expect(match.timeLeft, isNull);
    });
  });

  group('by itself', () {
    test('new titles are looked up once the first run was made', () async {
      await open(LocalLibrary(LibraryDb.inMemory()));
      tmdb
        ..addFilm(1, 'Stillwater', 2018)
        ..addFilm(2, 'Dear Dad', 2016);
      await put('Movies/English', ['Stillwater (2018) 1080p WEBDL.mkv']);
      await readNames();
      expect(tmdb.asked, isEmpty, reason: 'the first run waits to be asked');
      await match.start();

      // A crawl finds another film.
      await put('Movies/Hindi', ['Dear Dad (2016) 1080p WEBDL.mkv']);
      await readNames();
      await match.start();

      expect(tmdb.asked, contains('movie|dear dad|2016'));
      expect((await stored())['Dear Dad']!.take(3), [2016, 2, 1]);
      expect(match.counts!.matched, 2);
    });

    test('nothing is looked up without a key', () async {
      await open(LocalLibrary(LibraryDb.inMemory()));
      tmdb.addFilm(1, 'Stillwater', 2018);
      await put('Movies/English', ['Stillwater (2018) 1080p WEBDL.mkv']);
      await readNames();
      await match.start();
      await tmdbKey.remove();
      final asked = tmdb.asked.length;

      await put('Movies/Hindi', ['Dear Dad (2016) 1080p WEBDL.mkv']);
      await readNames();

      expect(match.isRunning, isFalse);
      expect(tmdb.asked, hasLength(asked));
      expect(match.counts!.pending, 1);
    });
  });

  test('works with the library in its own isolate', () async {
    final isolate = await LibraryIsolate.spawn();
    addTearDown(isolate.close);
    await open(isolate);
    tmdb
      ..addFilm(1, 'Stillwater', 2018)
      ..addShow(4, 'The Quiet Signal', 2017);
    await put('Movies/English', ['Stillwater (2018) 1080p WEBDL.mkv']);
    await put('Tv/The Quiet Signal Season 1', ['The Quiet Signal S01E01.mkv']);
    await readNames();
    final seen = <int>{};
    match.addListener(() => seen.add(match.progress?.done ?? -1));

    await match.start();

    expect(match.lastEnd, MatchEnd.finished);
    final counts = match.counts!;
    expect((counts.matched, counts.pending), (2, 0));
    expect(seen, containsAll([0, 2]));
    expect((await stored())['Stillwater']!.take(3), [2018, 1, 1]);
  });

  test('a MatchCounts says what is left to review', () {
    const counts = MatchCounts(matched: 3, unsure: 2, notFound: 1, pending: 9);
    expect(counts.lookedUp, 6);
    expect(counts.toReview, 3);
  });
}
