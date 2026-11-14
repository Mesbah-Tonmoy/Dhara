import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/core/secrets/secret_store.dart';
import 'package:dhara/features/indexer/index_controller.dart';
import 'package:dhara/features/metadata/episodes_controller.dart';
import 'package:dhara/features/metadata/match_controller.dart';
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

List<String> _episodeNames(LibraryDb library, Object? _) => [
  for (final row in library.db.select(
    'SELECT season, episode, name FROM episodes ORDER BY season, episode',
  ))
    'S${row['season']}E${row['episode']} ${row['name']}',
];

void main() {
  late LocalServer server;
  late FakeTmdb tmdb;
  late LibraryWorker library;
  late IndexController index;
  late TitlesController titles;
  late TmdbKeyController tmdbKey;
  late MatchController match;
  late EpisodesController episodes;

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
    tmdbKey = TmdbKeyController(secrets);
    await tmdbKey.load();
    match = MatchController(
      library: library,
      titles: titles,
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
      match.dispose();
      titles.dispose();
      index.dispose();
    });
  }

  Future<void> put(String path, List<String> names) =>
      library.run(_put, (path, names));

  /// Reads the names, matches the titles and lets the episodes follow.
  Future<void> matchAll() async {
    await index.load();
    await titles.refresh();
    await pumpEventQueue();
    await match.start();
    await pumpEventQueue();
    await episodes.refresh();
  }

  Future<List<String>> names() => library.run(_episodeNames, null);

  setUp(() async {
    server = await LocalServer.start();
    tmdb = FakeTmdb(server)
      ..addShow(
        70001,
        'The Quiet Signal',
        2017,
        seasons: {
          0: ['A Special'],
          1: ['Static', 'Carrier Wave'],
          2: ['Dead Air'],
        },
      )
      ..addFilm(1, 'Stillwater', 2018);
  });

  tearDown(() => server.close());

  test(
    'fetches the seasons the library has, once titles are matched',
    () async {
      await open(LocalLibrary(LibraryDb.inMemory()));
      await put('Tv/The Quiet Signal Season 1', [
        'The Quiet Signal S01E01.mkv',
        'The Quiet Signal S01E02.mkv',
      ]);
      await put('Movies', ['Stillwater (2018).mkv']);

      await matchAll();

      expect(episodes.isFetching, isFalse);
      expect(episodes.failed, isFalse);
      expect((episodes.showsDone, episodes.showsToDo), (1, 1));
      expect(await names(), ['S1E1 Static', 'S1E2 Carrier Wave']);
      final asked = tmdb.asked.where((request) => request.startsWith('tv/'));
      expect(asked, ['tv/70001', 'tv/70001/season/1']);

      final show = (await titles.search('quiet signal')).single;
      final copies = await titles.copiesOf(show.id);
      expect(
        [for (final copy in copies) copy.episodeName],
        ['Static', 'Carrier Wave'],
      );
    },
  );

  test('asks nothing again until it is due or a season is new', () async {
    await open(LocalLibrary(LibraryDb.inMemory()));
    await put('Tv/The Quiet Signal Season 1', ['The Quiet Signal S01E01.mkv']);
    await matchAll();
    final asked = tmdb.asked.length;

    await episodes.refresh();
    expect(tmdb.asked, hasLength(asked));
    expect((episodes.showsDone, episodes.showsToDo), (0, 0));

    // A crawl finds the second season.
    await put('Tv/The Quiet Signal Season 2', ['The Quiet Signal S02E01.mkv']);
    await index.load();
    await titles.refresh();
    await pumpEventQueue();
    await episodes.refresh();

    expect(await names(), [
      'S1E1 Static',
      'S1E2 Carrier Wave',
      'S2E1 Dead Air',
    ]);
  });

  test('skips a season TMDB does not list', () async {
    await open(LocalLibrary(LibraryDb.inMemory()));
    await put('Tv/The Quiet Signal Season 9', ['The Quiet Signal S09E01.mkv']);

    await matchAll();

    expect(episodes.failed, isFalse);
    expect(await names(), isEmpty);
    expect(tmdb.asked.where((request) => request.startsWith('tv/')), [
      'tv/70001',
    ]);
  });

  test('does nothing without a key', () async {
    await open(LocalLibrary(LibraryDb.inMemory()), key: null);
    await put('Tv/The Quiet Signal Season 1', ['The Quiet Signal S01E01.mkv']);

    await matchAll();

    expect(tmdb.asked, isEmpty);
    expect(episodes.failed, isFalse);
  });

  test('says so when TMDB cannot be asked, and tries again later', () async {
    await open(LocalLibrary(LibraryDb.inMemory()));
    await put('Tv/The Quiet Signal Season 1', ['The Quiet Signal S01E01.mkv']);
    await index.load();
    await titles.refresh();
    await pumpEventQueue();
    await match.start();
    await pumpEventQueue();
    await episodes.refresh();
    expect(await names(), isNotEmpty);

    // Two weeks on, TMDB is out of order.
    await library.run(_forgetFetches, null);
    tmdb.failWith = 500;
    await episodes.refresh();
    expect(episodes.failed, isTrue);
    expect(await names(), isNotEmpty, reason: 'what it had is kept');

    tmdb.failWith = null;
    await episodes.refresh();
    expect(episodes.failed, isFalse);
    expect((episodes.showsDone, episodes.showsToDo), (1, 1));
  });

  test('works with the library in its own isolate', () async {
    final isolate = await LibraryIsolate.spawn();
    addTearDown(isolate.close);
    await open(isolate);
    await put('Tv/The Quiet Signal Season 2', ['The Quiet Signal S02E01.mkv']);

    await matchAll();
    // The answers of an isolate take more than a turn of the event loop.
    await episodes.refresh();

    expect(await names(), ['S2E1 Dead Air']);
  });
}

void _forgetFetches(LibraryDb library, Object? _) =>
    library.db.execute("DELETE FROM metadata_cache WHERE key LIKE 'show|%'");
