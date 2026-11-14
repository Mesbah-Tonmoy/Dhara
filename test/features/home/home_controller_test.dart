import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/core/secrets/secret_store.dart';
import 'package:dhara/features/home/home_controller.dart';
import 'package:dhara/features/home/home_store.dart';
import 'package:dhara/features/indexer/index_controller.dart';
import 'package:dhara/features/metadata/match_controller.dart';
import 'package:dhara/features/metadata/titles_controller.dart';
import 'package:dhara/features/metadata/tmdb_key.dart';
import 'package:dhara/features/sources/source.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:flutter_test/flutter_test.dart';

Source _source(String id) => Source(
  id: id,
  name: 'Server $id',
  type: SourceType.directoryListing,
  category: SourceCategory.mixed,
  baseUrls: [Uri.parse('http://10.0.0.1/$id/')],
);

var _urls = 0;

/// Puts videos called [names] into the index, in the folder [path] of the
/// source [sourceId], as a finished crawl would.
void _put(LibraryDb library, String sourceId, String path, List<String> names) {
  final db = library.db;
  db.execute(
    'INSERT INTO sources (source_id, crawl_started_at, crawl_finished_at) '
    'VALUES (?, 1, 2) ON CONFLICT (source_id) DO NOTHING',
    [sourceId],
  );
  db.execute(
    'INSERT INTO folders (source, url, path, depth, state) '
    'SELECT id, ?, ?, 1, 1 FROM sources WHERE source_id = ?',
    ['http://$sourceId.test/${_urls++}/', path, sourceId],
  );
  final folder = db.lastInsertRowId;
  for (final name in names) {
    db.execute(
      'INSERT INTO files (folder, name, url, added_at) VALUES (?, ?, ?, 0)',
      [folder, name, 'http://$sourceId.test/$name'],
    );
  }
}

void main() {
  late LibraryDb db;
  late SourceStore sources;
  late IndexController index;
  late TitlesController titles;
  late MatchController match;
  late HomeController home;
  var reads = 0;

  /// The controllers over [library], for the sources "flix" and "icc",
  /// both switched on.
  Future<void> open(LibraryWorker library) async {
    sources = SourceStore(starter: [_source('flix'), _source('icc')]);
    await sources.setEnabled(['flix', 'icc'], enabled: true);
    index = IndexController(
      library: library,
      sources: sources,
      deviceId: 'dhara-test',
    );
    titles = TitlesController(library: library, index: index);
    match = MatchController(
      library: library,
      titles: titles,
      tmdbKey: TmdbKeyController(MemorySecretStore()),
    );
    home = HomeController(library: library, titles: titles, match: match);
    reads = 0;
    home.addListener(() {
      // Told twice per read: when it starts and when it is done.
      if (!home.isLoading) reads++;
    });
    addTearDown(() {
      home.dispose();
      match.dispose();
      titles.dispose();
      index.dispose();
    });
  }

  setUp(() {
    db = LibraryDb.inMemory();
    addTearDown(db.close);
  });

  /// Lets the index be read again, as after a crawl, waits for the names
  /// to be read, and for what that sets off.
  Future<void> reload() async {
    await index.load();
    await titles.refresh();
    await pumpEventQueue();
  }

  List<String> movies() => [
    for (final card in home.content?.movies ?? const <TitleCard>[]) card.name,
  ];

  test('has nothing until it is read, then all of Home', () async {
    _put(db, 'icc', 'Movies', ['Vivarium (2019) 1080p.mkv']);
    await open(LocalLibrary(db));
    await reload();
    expect(home.content, isNotNull, reason: 'read by itself');

    final again = home.refresh();
    expect(home.isLoading, isTrue);
    await again;

    expect(home.isLoading, isFalse);
    expect(home.failed, isFalse);
    expect(movies(), ['Vivarium']);
    expect(home.content!.recentlyAdded.single.videos, 1);
    expect(home.content!.hasNoTitles, isFalse);
  });

  test('reads again by itself when new names were read', () async {
    _put(db, 'icc', 'Movies', ['Vivarium (2019) 1080p.mkv']);
    await open(LocalLibrary(db));
    await reload();
    expect(movies(), ['Vivarium']);

    _put(db, 'flix', 'Movies', ['Tenet (2020) 1080p.mkv']);
    await reload();

    expect(movies(), ['Tenet', 'Vivarium']);
  });

  test('reads again by itself when a source is switched off or on', () async {
    _put(db, 'icc', 'Movies', ['Vivarium (2019) 1080p.mkv']);
    _put(db, 'flix', 'Movies', ['Tenet (2020) 1080p.mkv']);
    await open(LocalLibrary(db));
    await reload();
    expect(movies(), ['Tenet', 'Vivarium']);

    await sources.setEnabled(['flix'], enabled: false);
    await pumpEventQueue();
    expect(movies(), ['Vivarium']);

    await sources.setEnabled(['flix'], enabled: true);
    await pumpEventQueue();
    expect(movies(), ['Tenet', 'Vivarium']);
  });

  test('does not read again when nothing it shows has changed', () async {
    _put(db, 'icc', 'Movies', ['Vivarium (2019) 1080p.mkv']);
    await open(LocalLibrary(db));
    await reload();
    final before = reads;

    // A server test notes its result on the source list.
    await sources.recordHealth({
      'icc': SourceHealth(
        checkedAt: DateTime(2026, 11, 15),
        reachable: true,
        readable: true,
        ping: const Duration(milliseconds: 12),
      ),
    });
    await index.load();
    await pumpEventQueue();

    expect(reads, before);
  });

  test('several calls while it reads are one read', () async {
    await open(LocalLibrary(db));
    await reload();
    final before = reads;

    await Future.wait([home.refresh(), home.refresh(), home.refresh()]);

    expect(reads, before + 1);
  });

  test('says so when the library does not answer, and never throws', () async {
    await open(const NoLibrary());

    await home.refresh();

    expect(home.failed, isTrue);
    expect(home.content, isNull);
    await home.refreshContinueWatching();
    expect(home.content, isNull);
  });

  test('reads Continue Watching alone after something was played', () async {
    _put(db, 'icc', 'Movies', ['Vivarium (2019) 1080p.mkv']);
    await open(LocalLibrary(db));
    await reload();
    expect(home.content!.continueWatching, isEmpty);
    final rows = home.content!.movies;

    const url = 'http://icc.test/Vivarium (2019) 1080p.mkv';
    db.db
      ..execute(
        'INSERT INTO watch_history '
        '(url, watched_at, position_ms, duration_ms) VALUES (?, 9, 1500, 6000)',
        [url],
      )
      ..execute(
        'INSERT INTO playback (url, position_ms, duration_ms, updated_at) '
        'VALUES (?, 1500, 6000, 9)',
        [url],
      );
    await home.refreshContinueWatching();

    final item = home.content!.continueWatching.single;
    expect(item.title?.name, 'Vivarium');
    expect(item.position, const Duration(milliseconds: 1500));
    expect(home.content!.movies, same(rows), reason: 'the rest is kept');
  });

  test('a change after it was disposed does nothing', () async {
    await open(LocalLibrary(db));
    await reload();
    final before = reads;
    home.dispose();

    await sources.setEnabled(['flix'], enabled: false);
    await pumpEventQueue();

    expect(reads, before);
    // For tearDown, which disposes of it again.
    home = HomeController(
      library: LocalLibrary(db),
      titles: titles,
      match: match,
    );
  });
}
