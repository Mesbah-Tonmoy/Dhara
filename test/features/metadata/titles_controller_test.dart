import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/features/indexer/index_controller.dart';
import 'package:dhara/features/metadata/titles_controller.dart';
import 'package:dhara/features/metadata/video_identity.dart';
import 'package:dhara/features/sources/source.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/local_server.dart';

Source _source(String id, {Uri? base}) => Source(
  id: id,
  name: 'Server $id',
  type: SourceType.directoryListing,
  category: SourceCategory.mixed,
  baseUrls: [base ?? Uri.parse('http://10.0.0.1/$id/')],
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
      [folder, name, 'http://$sourceId.test/${_urls++}/$name'],
    );
  }
}

void main() {
  late LibraryDb db;
  late SourceStore sources;
  late IndexController index;
  late TitlesController titles;

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
    addTearDown(() {
      titles.dispose();
      index.dispose();
    });
  }

  setUp(() {
    db = LibraryDb.inMemory();
    addTearDown(db.close);
  });

  /// Lets the index be read again, as after a crawl, and waits for the
  /// names to be read.
  Future<void> reload() async {
    await index.load();
    await titles.refresh();
  }

  test('reads the names by itself once the index is loaded', () async {
    _put(db, 'flix', 'Movies/Vivarium (2019) 720p', ['vivarium.mkv']);
    _put(db, 'icc', 'Movies/English', [
      'Vivarium (2019) 1080p WEBRip.mkv',
      'Stillwater (2018) 1080p WEBDL.mkv',
    ]);
    _put(db, 'icc', 'Tv/Some Show Season 1', ['Some Show S01E01.mkv']);
    _put(db, 'icc', 'Fun Zone/Funny Vedio/WMV', ['Coins.wmv']);
    await open(LocalLibrary(db));
    expect(titles.counts, isNull);
    expect(titles.isReading, isFalse);

    await index.load();
    expect(titles.isReading, isTrue, reason: 'nobody asked for it');
    await titles.refresh();

    expect(titles.isReading, isFalse);
    expect(titles.failed, isFalse);
    final counts = titles.counts!;
    expect(
      (counts.movies, counts.shows, counts.otherVideos, counts.unreadFiles),
      (2, 1, 1, 0),
    );
    expect((titles.namesRead, titles.namesToRead), (5, 5));
  });

  test('says how far it is while it reads', () async {
    _put(db, 'icc', 'Movies/English', [
      for (var i = 0; i < 450; i++) 'Film Number $i (2001) 720p.mkv',
    ]);
    await open(LocalLibrary(db));
    final seen = <(int, int, bool)>{};
    titles.addListener(
      () => seen.add((titles.namesRead, titles.namesToRead, titles.isReading)),
    );

    await reload();

    expect(
      seen,
      containsAll([
        (0, 0, true),
        (200, 450, true),
        (400, 450, true),
        (450, 450, true),
        (450, 450, false),
      ]),
    );
    expect(titles.counts!.movies, 450);
  });

  test('reads the names of files a later crawl has added', () async {
    _put(db, 'icc', 'Movies/English', ['Stillwater (2018) 1080p WEBDL.mkv']);
    await open(LocalLibrary(db));
    await reload();
    expect(titles.counts!.movies, 1);

    _put(db, 'icc', 'Movies/Hindi', ['Dear Dad (2016) 1080p WEBDL.mkv']);
    await index.load();
    expect(titles.isReading, isTrue);
    await titles.refresh();

    expect(titles.counts!.movies, 2);
    expect((titles.namesRead, titles.namesToRead), (1, 1));
  });

  test('does nothing when the index has not changed', () async {
    _put(db, 'icc', 'Movies/English', ['Stillwater (2018) 1080p WEBDL.mkv']);
    await open(LocalLibrary(db));
    await reload();

    await index.load();

    expect(titles.isReading, isFalse);
  });

  test('drops the titles of a source that was removed', () async {
    _put(db, 'flix', 'Movies', ['Only Here (2001).mkv', 'On Both (2002).mkv']);
    _put(db, 'icc', 'Movies', ['On Both (2002).mkv']);
    await open(LocalLibrary(db));
    await reload();
    expect(titles.counts!.movies, 2);

    await sources.remove('flix');
    // The index forgets the source, then the names are gone through again.
    await pumpEventQueue();
    await titles.refresh();

    expect(titles.counts!.movies, 1);
    expect(await titles.search('only'), isEmpty);
    expect((await titles.search('both')).single.copies, 1);
  });

  test('searches the titles of enabled sources', () async {
    _put(db, 'flix', 'Movies', ['Only Here (2001).mkv', 'On Both (2002).mkv']);
    _put(db, 'icc', 'Movies', ['On Both (2002) 1080p.mkv']);
    await open(LocalLibrary(db));
    await reload();

    final both = (await titles.search('on bo')).single;
    expect(
      (both.name, both.year, both.kind),
      ('On Both', 2002, TitleKind.movie),
    );
    expect(both.copies, 2);
    final copies = await titles.copiesOf(both.id);
    expect([for (final copy in copies) copy.sourceId], ['icc', 'flix']);
    expect(await titles.search(''), isEmpty);
    expect(await titles.search('both', limit: 0), isEmpty);

    await sources.setEnabled(['flix'], enabled: false);

    expect(await titles.search('only'), isEmpty);
    expect((await titles.search('both')).single.copies, 1);
    expect(await titles.copiesOf(both.id), hasLength(1));
  });

  test('without a library it fails once and finds nothing', () async {
    await open(const NoLibrary());
    var passes = 0;
    titles.addListener(() {
      if (titles.isReading) passes++;
    });

    await index.load();
    await titles.refresh();
    await pumpEventQueue();

    expect(titles.failed, isTrue);
    expect(titles.counts, isNull);
    expect(titles.isReading, isFalse);
    expect(await titles.search('anything'), isEmpty);
    expect(await titles.copiesOf(1), isEmpty);
    // No going round in circles: one pass by itself, one asked for here.
    expect(passes, lessThanOrEqualTo(4));
  });

  test('stops listening to the index when disposed', () async {
    _put(db, 'icc', 'Movies/English', ['Stillwater (2018) 1080p WEBDL.mkv']);
    final store = SourceStore(starter: [_source('icc')]);
    final watched = IndexController(
      library: LocalLibrary(db),
      sources: store,
      deviceId: 'dhara-test',
    );
    addTearDown(watched.dispose);
    final gone = TitlesController(library: LocalLibrary(db), index: watched);
    gone.dispose();

    await watched.load();
    await pumpEventQueue();

    expect(gone.counts, isNull);
  });

  group('with the library in its own isolate', () {
    late LocalServer server;
    late LibraryIsolate library;

    String page(List<String> links) =>
        '<html><head><title>Index of /</title></head><body><pre>\n'
        '<a href="../">../</a>\n'
        '${[for (final link in links) '<a href="$link">$link</a>'].join('\n')}'
        '\n</pre></body></html>';

    setUp(() async {
      server = await LocalServer.start();
      server
        ..serve('/films/', page(['Vivarium%20(2019)%20720p/', 'Shows/']))
        ..serve('/films/Vivarium%20(2019)%20720p/', page(['vivarium.mkv']))
        ..serve(
          '/films/Shows/',
          page(['Some.Show.S01E01.mkv', 'Some.Show.S01E02.mkv']),
        );
      library = await LibraryIsolate.spawn();
      sources = SourceStore(
        starter: [_source('films', base: server.url('/films/'))],
      );
      await sources.setEnabled(['films'], enabled: true);
      index = IndexController(
        library: library,
        sources: sources,
        deviceId: 'dhara-test',
      );
      titles = TitlesController(library: library, index: index);
    });

    tearDown(() async {
      titles.dispose();
      index.dispose();
      await library.close();
      await server.close();
    });

    test('a crawl ends with its videos under their titles', () async {
      await index.load();
      await titles.refresh();
      expect(titles.counts!.movies, 0);

      final crawl = index.start();
      expect(titles.isReading, isFalse, reason: 'waits for the crawl to end');
      await crawl;
      expect(index.statsOf('films')!.files, 3);
      await titles.refresh();

      final counts = titles.counts!;
      expect((counts.movies, counts.shows, counts.unreadFiles), (1, 1, 0));
      final film = (await titles.search('viva')).single;
      expect((film.name, film.year, film.copies), ('Vivarium', 2019, 1));
      final show = (await titles.search('some show')).single;
      expect(show.kind, TitleKind.series);
      final episodes = await titles.copiesOf(show.id);
      expect(
        [for (final copy in episodes) (copy.season, copy.episode)],
        [(1, 1), (1, 2)],
      );
      expect(episodes.first.url.path, '/films/Shows/Some.Show.S01E01.mkv');
    });
  });
}
