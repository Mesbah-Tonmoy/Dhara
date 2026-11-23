import 'dart:io';

import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/core/secrets/secret_store.dart';
import 'package:dhara/core/settings/key_value_store.dart';
import 'package:dhara/features/home/home_controller.dart';
import 'package:dhara/features/indexer/index_controller.dart';
import 'package:dhara/features/indexer/index_store.dart';
import 'package:dhara/features/metadata/match_controller.dart';
import 'package:dhara/features/metadata/titles_controller.dart';
import 'package:dhara/features/metadata/tmdb_key.dart';
import 'package:dhara/features/snapshot/first_start_controller.dart';
import 'package:dhara/features/snapshot/snapshot_fetcher.dart';
import 'package:dhara/features/snapshot/snapshot_reader.dart';
import 'package:dhara/features/snapshot/snapshot_writer.dart';
import 'package:dhara/features/sources/adapters/source_adapter.dart';
import 'package:dhara/features/sources/source.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:dhara/features/sources/source_test_controller.dart';
import 'package:dhara/features/sources/source_tester.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/local_server.dart';

void main() {
  late LocalServer server;
  late Directory folder;
  late LibraryDb db;
  late MemoryKeyValueStore settings;
  late SourceStore store;
  late IndexController index;
  late HomeController home;
  late List<Source> sources;

  /// The requests the server got for [path].
  int asked(String path) =>
      server.requests.where((request) => request.uri.path == path).length;

  String at(String name) => '${folder.path}${Platform.pathSeparator}$name';

  /// The snapshot of a development build that has read the server
  /// "alpha": one film there, with its title.
  Future<List<int>> snapshot() async {
    final written = LibraryDb.inMemory();
    final alpha = sources.first;
    final crawl = IndexStore(written);
    final key = crawl.beginCrawl(alpha.id, alpha.baseUrls);
    crawl
      ..saveListing(
        crawl.pendingFolders(key).single,
        FolderListing(
          videos: [
            IndexedVideo(
              RemoteEntry(
                name: 'Vivarium.2019.mkv',
                url: alpha.baseUrls.single.resolve('Vivarium.2019.mkv'),
                isFolder: false,
              ),
            ),
          ],
        ),
        maxDepth: 12,
        folderBudget: 100,
      )
      ..finishCrawl(key);
    written.db
      ..execute(
        'INSERT INTO titles (id, kind, name, year, match_state, added_at) '
        "VALUES (1, 0, 'Vivarium', 2019, 1, 1)",
      )
      ..execute(
        'INSERT INTO title_keys (key, title, name, year) '
        "VALUES ('m|vivarium|2019', 1, 'Vivarium', 2019)",
      )
      ..execute(
        'INSERT INTO file_meta (file, parser, kind, title) '
        'SELECT id, 999, 0, 1 FROM files',
      );
    await writeSnapshot(written, (at('written.gz'), null));
    written.close();
    final file = File(at('written.gz'));
    final bytes = file.readAsBytesSync();
    file.deleteSync();
    return bytes;
  }

  void serveSnapshot(List<int> bytes) {
    server.routes['/library.gz'] = (request) async {
      request.response
        ..headers.set(HttpHeaders.contentTypeHeader, 'application/octet-stream')
        ..contentLength = bytes.length
        ..add(bytes);
      await request.response.close();
    };
  }

  setUp(() async {
    server = await LocalServer.start();
    // "alpha" is a folder listing the app can read; nothing else answers.
    server.serve(
      '/alpha/',
      '<title>Index of /alpha/</title><a href="Vivarium.2019.mkv">v</a>',
    );
    final gone = await LocalServer.start();
    final goneUrl = gone.url('/files/');
    await gone.close();
    sources = [
      Source(
        id: 'alpha',
        name: 'Alpha',
        type: SourceType.directoryListing,
        category: SourceCategory.movies,
        baseUrls: [server.url('/alpha/')],
      ),
      Source(
        id: 'dead',
        name: 'Dead',
        type: SourceType.directoryListing,
        category: SourceCategory.movies,
        baseUrls: [goneUrl],
      ),
      // Not checked by hand: a first start does not ask it.
      Source(
        id: 'bdix-candidate',
        name: 'Candidate',
        type: SourceType.directoryListing,
        category: SourceCategory.mixed,
        baseUrls: [server.url('/candidate/')],
        notes: candidateSourceNote,
      ),
      // Nothing the app can read, whatever it answers.
      Source(
        id: 'site',
        name: 'Site',
        type: SourceType.customSite,
        category: SourceCategory.mixed,
        baseUrls: [server.url('/site/')],
      ),
    ];
    folder = Directory.systemTemp.createTempSync('dhara-first-start-');
    db = LibraryDb.inMemory();
    settings = MemoryKeyValueStore();
    store = SourceStore(starter: sources);
  });

  tearDown(() async {
    await server.close();
    db.close();
    folder.deleteSync(recursive: true);
  });

  /// A production build's first start, fetching from [path] of the server
  /// (from nowhere without one).
  FirstStartController firstStart({
    String? path = '/library.gz',
    File? bundled,
  }) {
    final library = LocalLibrary(db);
    final tests = SourceTestController(
      store: store,
      tester: SourceTester(
        deviceId: 'dhara-test',
        timeout: const Duration(seconds: 5),
      ),
    );
    index = IndexController(
      library: library,
      sources: store,
      deviceId: 'dhara-test',
    );
    final titles = TitlesController(library: library, index: index);
    home = HomeController(
      library: library,
      titles: titles,
      match: MatchController(
        library: library,
        titles: titles,
        tmdbKey: TmdbKeyController(MemorySecretStore()),
      ),
    );
    final controller = FirstStartController(
      library: library,
      settings: settings,
      sources: tests,
      index: index,
      titles: titles,
      home: home,
      fetcher: path == null
          ? null
          : SnapshotFetcher(server.url(path), client: server.client()),
      folder: folder,
      bundled: bundled,
      clock: () => DateTime.utc(2026, 11, 24),
    );
    addTearDown(controller.dispose);
    addTearDown(tests.dispose);
    return controller;
  }

  List<Object?> videos() => [
    for (final row in db.db.select('SELECT name FROM files')) row['name'],
  ];

  test('on a new installation it fetches the library and switches on the '
      'servers that answer, with nothing to do for the user', () async {
    serveSnapshot(await snapshot());
    final start = firstStart();
    final steps = <FirstStartStep?>{};
    bool? heldAsReadingBegan;
    start.addListener(() {
      steps.add(start.step);
      if (start.step == FirstStartStep.reading) {
        heldAsReadingBegan ??= index.isHeld;
      }
    });

    final run = start.start();
    expect(start.isWorking, isTrue);
    await run;

    expect(start.isWorking, isFalse);
    expect(start.problem, isNull);
    expect(start.step, isNull);
    expect(steps, containsAll(FirstStartStep.values));
    // No crawl could start while the snapshot went in.
    expect(heldAsReadingBegan, isTrue);
    expect(index.isHeld, isFalse);
    // The library is the snapshot's.
    expect(videos(), ['Vivarium.2019.mkv']);
    expect(index.statsOf('alpha')!.files, 1);
    // Only the server that answered is on, and only the servers checked
    // by hand were asked.
    expect(store.isEnabled('alpha'), isTrue);
    expect(store.isEnabled('dead'), isFalse);
    expect(store.isEnabled('bdix-candidate'), isFalse);
    expect(store.isEnabled('site'), isFalse);
    expect(start.serversFound, 1);
    expect(asked('/candidate/'), 0);
    expect(asked('/site/'), 0);
    // Home has the film to show.
    expect(home.content!.hasNoTitles, isFalse);
    expect(home.content!.movies.single.name, 'Vivarium');
    // The file that was fetched is gone, and it is noted that one was read.
    expect(folder.listSync(), isEmpty);
    expect(
      settings.getInt(FirstStartController.readAtKey),
      DateTime.utc(2026, 11, 24).millisecondsSinceEpoch,
    );

    // The next start has nothing to do, and asks nobody.
    final requests = server.requests.length;
    await firstStart().start();
    expect(server.requests, hasLength(requests));
  });

  test('a library that holds something is left alone, and so are its '
      'servers', () async {
    serveSnapshot(await snapshot());
    IndexStore(db).beginCrawl('alpha', sources.first.baseUrls);
    final start = firstStart();

    await start.start();

    expect(start.problem, isNull);
    expect(server.requests, isEmpty);
    expect(store.isEnabled('alpha'), isFalse);
    expect(videos(), isEmpty);
    expect(settings.getInt(FirstStartController.readAtKey), isNull);
  });

  test('with a server switched on already the servers are not tested, '
      'but an empty library is still filled', () async {
    serveSnapshot(await snapshot());
    await store.setEnabled(['dead'], enabled: true);
    final start = firstStart();

    await start.start();

    expect(start.problem, isNull);
    expect(start.serversFound, isNull);
    expect(asked('/alpha/'), 0);
    expect(store.isEnabled('alpha'), isFalse);
    expect(videos(), ['Vivarium.2019.mkv']);
  });

  test('a snapshot that cannot be fetched is said, the servers are found '
      'all the same, and trying again fills the library', () async {
    final start = firstStart();

    await start.start();

    expect(start.problem, FirstStartProblem.notFetched);
    expect(start.fetchProblem, SnapshotFetchProblem.notThere);
    expect(start.isWorking, isFalse);
    expect(store.isEnabled('alpha'), isTrue);
    expect(videos(), isEmpty);
    expect(settings.getInt(FirstStartController.readAtKey), isNull);
    expect(folder.listSync(), isEmpty);

    serveSnapshot(await snapshot());
    final tested = asked('/alpha/');
    await start.retry();

    expect(start.problem, isNull);
    expect(start.fetchProblem, isNull);
    expect(videos(), ['Vivarium.2019.mkv']);
    // A server is on by now: they are not tested again.
    expect(asked('/alpha/'), tested);
  });

  test('what is fetched but is no snapshot is refused, and nothing of it '
      'stays', () async {
    serveSnapshot(gzip.encode('{"format": "something else"}\n'.codeUnits));
    final start = firstStart();

    await start.start();

    expect(start.problem, FirstStartProblem.notRead);
    expect(start.readProblem, SnapshotProblem.notASnapshot);
    expect(videos(), isEmpty);
    expect(folder.listSync(), isEmpty);
    expect(settings.getInt(FirstStartController.readAtKey), isNull);
  });

  test('a build without an address fetches nothing and still finds the '
      'servers', () async {
    final start = firstStart(path: null);

    await start.start();

    expect(start.problem, FirstStartProblem.nothingToFetch);
    expect(store.isEnabled('alpha'), isTrue);
    expect(asked('/library.gz'), 0);
  });

  test('a build without an address still reads a snapshot that lies in '
      'its folder', () async {
    File(at('library.snapshot.gz')).writeAsBytesSync(await snapshot());
    final start = firstStart(path: null);

    await start.start();

    expect(start.problem, isNull);
    expect(videos(), ['Vivarium.2019.mkv']);
    expect(folder.listSync(), isEmpty);
  });

  test('a snapshot fetched whole before the app was closed is read '
      'without asking for it again', () async {
    File(at('library.snapshot.gz')).writeAsBytesSync(await snapshot());
    final start = firstStart();

    await start.start();

    expect(start.problem, isNull);
    expect(asked('/library.gz'), 0);
    expect(videos(), ['Vivarium.2019.mkv']);
    expect(folder.listSync(), isEmpty);
  });

  group('a snapshot that came with the installer', () {
    late Directory program;
    late File bundled;

    setUp(() {
      program = Directory.systemTemp.createTempSync('dhara-program-');
      bundled = File(
        '${program.path}${Platform.pathSeparator}library.snapshot.gz',
      );
    });

    tearDown(() => program.deleteSync(recursive: true));

    test('is read without fetching, and left where it lies', () async {
      bundled.writeAsBytesSync(await snapshot());
      serveSnapshot(await snapshot());
      final start = firstStart(bundled: bundled);

      await start.start();

      expect(start.problem, isNull);
      expect(asked('/library.gz'), 0);
      expect(videos(), ['Vivarium.2019.mkv']);
      expect(bundled.existsSync(), isTrue);
      expect(settings.getInt(FirstStartController.readAtKey), isNotNull);
    });

    test('fills the library of a build that has no address', () async {
      bundled.writeAsBytesSync(await snapshot());
      final start = firstStart(path: null, bundled: bundled);

      await start.start();

      expect(start.problem, isNull);
      expect(videos(), ['Vivarium.2019.mkv']);
      expect(store.isEnabled('alpha'), isTrue);
    });

    test('that is no snapshot is passed over for one that is fetched, and '
        'said if there is none to fetch', () async {
      bundled.writeAsStringSync('something else');
      serveSnapshot(await snapshot());
      final start = firstStart(bundled: bundled);

      await start.start();

      expect(start.problem, isNull);
      expect(asked('/library.gz'), 1);
      expect(videos(), ['Vivarium.2019.mkv']);
      expect(bundled.existsSync(), isTrue);

      db.db
        ..execute('DELETE FROM sources')
        ..execute('DELETE FROM titles');
      settings.values.clear();
      final alone = firstStart(path: null, bundled: bundled);

      await alone.start();

      expect(alone.problem, FirstStartProblem.notRead);
      expect(alone.readProblem, SnapshotProblem.notASnapshot);
    });

    test('waits behind one that was fetched and lies in the data '
        'folder', () async {
      bundled.writeAsStringSync('something else');
      File(at('library.snapshot.gz')).writeAsBytesSync(await snapshot());
      final start = firstStart(path: null, bundled: bundled);

      await start.start();

      expect(start.problem, isNull);
      expect(videos(), ['Vivarium.2019.mkv']);
    });
  });

  test('a file left there that is no snapshot is fetched anew', () async {
    File(at('library.snapshot.gz')).writeAsStringSync('half of something');
    serveSnapshot(await snapshot());
    final start = firstStart();

    await start.start();

    expect(start.problem, isNull);
    expect(start.readProblem, isNull);
    expect(asked('/library.gz'), 1);
    expect(videos(), ['Vivarium.2019.mkv']);
  });

  test('once a snapshot was read none is fetched by itself again, only '
      'when asked', () async {
    serveSnapshot(await snapshot());
    await settings.setInt(FirstStartController.readAtKey, 1);
    await store.setEnabled(['alpha'], enabled: true);
    final start = firstStart();

    await start.start();

    expect(server.requests, isEmpty);
    expect(videos(), isEmpty);

    await start.retry();

    expect(asked('/library.gz'), 1);
    expect(videos(), ['Vivarium.2019.mkv']);
  });
}
