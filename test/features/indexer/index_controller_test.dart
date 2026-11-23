import 'dart:async';
import 'dart:io';

import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/features/indexer/crawler.dart';
import 'package:dhara/features/indexer/index_controller.dart';
import 'package:dhara/features/sources/source.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/local_server.dart';

String _page(String path, List<String> links) =>
    '''
<html><head><title>Index of $path</title></head><body><pre>
<a href="../">../</a>
${[for (final link in links) '<a href="$link">$link</a>'].join('\n')}
</pre></body></html>''';

void main() {
  late LocalServer server;
  late LibraryIsolate library;
  late SourceStore sources;
  late IndexController index;
  var now = DateTime(2026, 11, 13, 9);

  Source source(String id, {SourceType type = SourceType.directoryListing}) =>
      Source(
        id: id,
        name: id,
        type: type,
        category: SourceCategory.mixed,
        baseUrls: [server.url('/$id/')],
      );

  setUp(() async {
    now = DateTime(2026, 11, 13, 9);
    server = await LocalServer.start();
    server
      ..serve('/films/', _page('/films/', ['Tenet%202020/', 'notes.txt']))
      ..serve(
        '/films/Tenet%202020/',
        _page('/films/Tenet 2020/', ['Tenet.2020.mkv', 'Tenet.2020.srt']),
      )
      ..serve('/shows/', _page('/shows/', ['Dark.S01E01.mkv']))
      ..serve('/site/', '<title>Some site</title>');
    library = await LibraryIsolate.spawn();
    sources = SourceStore(
      starter: [
        source('films'),
        source('shows'),
        source('site', type: SourceType.customSite),
      ],
    );
    index = IndexController(
      library: library,
      sources: sources,
      deviceId: 'dhara-test',
      clock: () => now,
    );
    await index.load();
  });

  tearDown(() async {
    index.dispose();
    await library.close();
    await server.close();
  });

  /// Waits until [condition] holds, checking after every change.
  Future<void> until(bool Function() condition) async {
    final reached = Completer<void>();
    void check() {
      if (!reached.isCompleted && condition()) reached.complete();
    }

    index.addListener(check);
    check();
    await reached.future.timeout(const Duration(seconds: 10));
    index.removeListener(check);
  }

  Future<List<String>> found(String text) async => [
    for (final hit in await index.search(text)) hit.name,
  ];

  test('crawls the enabled sources and makes them searchable', () async {
    await sources.setEnabled(['films', 'site'], enabled: true);
    expect(index.crawlableSources.map((source) => source.id), ['films']);
    expect(index.unreadableSources.map((source) => source.id), ['site']);

    final done = index.start();
    expect(index.isRunning, isTrue);
    await done;

    expect(index.isRunning, isFalse);
    expect(index.failedUnexpectedly, isFalse);
    final progress = index.progressOf('films')!;
    expect(progress.state, CrawlState.complete);
    expect(progress.foldersRead, 2);
    expect(progress.filesAdded, 1);
    final stats = index.statsOf('films')!;
    expect(stats.files, 1);
    expect(stats.crawlFinishedAt, isNotNull);

    // Sources that are off, or have no adapter, were not touched.
    expect(index.progressOf('shows'), isNull);
    expect(index.progressOf('site'), isNull);
    expect(index.statsOf('shows'), isNull);
    expect(
      server.requests.map((request) => request.uri.path),
      everyElement(startsWith('/films/')),
    );

    final hit = (await index.search('tenet')).single;
    expect(hit.name, 'Tenet.2020.mkv');
    expect(hit.sourceId, 'films');
    expect(hit.url, server.url('/films/Tenet%202020/Tenet.2020.mkv'));
  });

  test('starting twice runs one crawl', () async {
    await sources.setEnabled(['films'], enabled: true);

    final first = index.start();
    final second = index.start();
    await Future.wait([first, second]);

    expect(server.requests, hasLength(2));
  });

  test('with nothing enabled there is nothing to crawl', () async {
    await index.start();

    expect(index.isRunning, isFalse);
    expect(server.requests, isEmpty);
  });

  test(
    'while the library is held for something else no crawl starts',
    () async {
      await sources.setEnabled(['films'], enabled: true);
      var changes = 0;
      index.addListener(() => changes++);

      final release = index.hold();
      final again = index.hold();
      expect(index.isHeld, isTrue);
      expect(changes, 2);
      await index.start();

      expect(index.isRunning, isFalse);
      expect(server.requests, isEmpty);

      // Held until everyone who holds it has let go; letting go twice
      // counts once.
      release();
      release();
      expect(index.isHeld, isTrue);
      again();
      expect(index.isHeld, isFalse);
      await index.start();

      expect(server.requests, hasLength(2));
    },
  );

  test('search only looks in enabled sources', () async {
    await sources.setEnabled(['films', 'shows'], enabled: true);
    await index.start();
    expect(await found('dark'), ['Dark.S01E01.mkv']);

    await sources.setEnabled(['shows'], enabled: false);
    expect(await found('dark'), isEmpty);
    expect(await found('tenet'), ['Tenet.2020.mkv']);

    // Enabling it again needs no new crawl.
    final requests = server.requests.length;
    await sources.setEnabled(['shows'], enabled: true);
    expect(await found('dark'), ['Dark.S01E01.mkv']);
    expect(server.requests, hasLength(requests));
  });

  test('forgets what was found on a source that is removed', () async {
    await sources.setEnabled(['films', 'shows'], enabled: true);
    await index.start();
    expect(index.statsOf('shows')!.files, 1);

    await sources.remove('shows');
    await until(() => index.statsOf('shows') == null);

    expect(index.statsOf('films')!.files, 1);
    // Even if a source with that id comes back, its files are gone.
    await sources.add(source('shows'));
    await sources.setEnabled(['shows'], enabled: true);
    expect(await found('dark'), isEmpty);
  });

  test('stop ends a crawl that is waiting for a server', () async {
    // A server that takes the request and never answers.
    final asked = Completer<void>();
    server.routes['/shows/'] = (request) {
      if (!asked.isCompleted) asked.complete();
      return Completer<void>().future;
    };
    await sources.setEnabled(['shows'], enabled: true);

    final done = index.start();
    await asked.future;
    index.stop();
    expect(index.isStopping, isTrue);
    await done.timeout(const Duration(seconds: 10));

    expect(index.isRunning, isFalse);
    expect(index.isStopping, isFalse);
    expect(index.progressOf('shows')!.state, CrawlState.cancelled);
    final stats = index.statsOf('shows')!;
    expect(stats.pendingFolders, 1);
    expect(stats.failedFolders, 0);
    expect(stats.crawlFinishedAt, isNull);
  });

  test('reports a source whose folder cannot be read', () async {
    server.serve('/films/', 'gone', status: HttpStatus.notFound);
    await sources.setEnabled(['films'], enabled: true);

    await index.start();

    final progress = index.progressOf('films')!;
    expect(progress.state, CrawlState.incomplete);
    expect(progress.message, contains('The server answered 404.'));
    expect(index.statsOf('films')!.lastError, progress.message);
  });

  group('updateIfStale', () {
    setUp(() => sources.setEnabled(['films'], enabled: true));

    test('never starts the first crawl by itself', () async {
      await index.updateIfStale();

      expect(server.requests, isEmpty);
    });

    test('leaves an index alone that is less than a day old', () async {
      await index.start();
      final requests = server.requests.length;
      now = DateTime.now().add(const Duration(hours: 23));

      await index.updateIfStale();

      expect(server.requests, hasLength(requests));
    });

    test('brings an index up to date that is older than a day', () async {
      await index.start();
      final requests = server.requests.length;
      now = DateTime.now().add(const Duration(hours: 25));

      await index.updateIfStale();

      expect(server.requests.length, greaterThan(requests));
      expect(index.progressOf('films')!.state, CrawlState.complete);
    });

    test('also crawls a source that was enabled since', () async {
      await index.start();
      await sources.setEnabled(['shows'], enabled: true);

      await index.updateIfStale();

      expect(index.statsOf('shows')!.files, 1);
    });

    test('keepFresh looks now and again later, for as long as the '
        'controller lives', () async {
      await index.start();
      final requests = server.requests.length;

      // Not stale yet: looking now finds nothing to do.
      index.keepFresh(every: const Duration(milliseconds: 40));
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(server.requests, hasLength(requests));

      // A day later the next look starts a crawl, with nobody asking.
      now = DateTime.now().add(const Duration(hours: 25));
      await until(() => index.isRunning);
      await until(() => !index.isRunning);
      expect(server.requests.length, greaterThan(requests));
      expect(index.progressOf('films')!.state, CrawlState.complete);
    });
  });
}
