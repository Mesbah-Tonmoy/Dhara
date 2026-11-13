import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/core/net/safe_http_client.dart';
import 'package:dhara/features/indexer/crawler.dart';
import 'package:dhara/features/indexer/index_store.dart';
import 'package:dhara/features/sources/adapters/adapter_factory.dart';
import 'package:dhara/features/sources/adapters/source_adapter.dart';
import 'package:dhara/features/sources/source.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/local_server.dart';

/// A server made of a map from folder URL to what that folder holds.
class _FakeServer implements SourceAdapter {
  final _folders = <String, List<RemoteEntry>>{};

  /// Errors a folder answers with first, one per request.
  final errorsOnce = <Uri, List<Exception>>{};

  /// Folders that answer with this error every time.
  final broken = <Uri, Exception>{};

  /// While set, every request waits for it.
  Completer<void>? gate;

  /// Every folder asked for, in order.
  final requests = <Uri>[];
  var _running = 0;
  var mostAtOnce = 0;

  /// Says what [folder] holds: [folders] and [files] by name. A folder
  /// name may come with the change date its listing shows.
  void put(
    Uri folder, {
    List<String> folders = const [],
    List<String> files = const [],
    Map<String, DateTime> dates = const {},
  }) {
    _folders['$folder'] = [
      for (final name in folders)
        RemoteEntry(
          name: name,
          url: child(folder, name),
          isFolder: true,
          modified: dates[name],
        ),
      for (final name in files)
        RemoteEntry(
          name: name,
          url: folder.resolve(Uri.encodeComponent(name)),
          isFolder: false,
          size: 1000,
        ),
    ];
  }

  @override
  Future<List<RemoteEntry>> list(Uri folder) async {
    requests.add(folder);
    mostAtOnce = max(mostAtOnce, ++_running);
    try {
      await (gate?.future ?? Future<void>.delayed(Duration.zero));
      final once = errorsOnce[folder];
      if (once != null && once.isNotEmpty) throw once.removeAt(0);
      final always = broken[folder];
      if (always != null) throw always;
      return _folders['$folder'] ??
          (throw const SourceReadException(
            'The server answered 404.',
            statusCode: 404,
          ));
    } finally {
      _running--;
    }
  }
}

Uri child(Uri folder, String name) =>
    folder.resolve('${Uri.encodeComponent(name)}/');

Source _source(String id, List<Uri> baseUrls) => Source(
  id: id,
  name: id,
  type: SourceType.directoryListing,
  category: SourceCategory.mixed,
  baseUrls: baseUrls,
);

const _timeout = SafeHttpException(SafeHttpFailure.timeout, 'No answer.');
const _down = SafeHttpException(SafeHttpFailure.network, 'Not reachable.');

void main() {
  final base = Uri.parse('http://a.test/media/');
  late LibraryDb library;
  late IndexStore store;
  late _FakeServer server;
  late List<CrawlProgress> events;
  late List<Duration> waits;

  setUp(() {
    library = LibraryDb.inMemory();
    store = IndexStore(library);
    server = _FakeServer();
    events = [];
    waits = [];
  });

  tearDown(() => library.close());

  Crawler crawler({
    CrawlLimits limits = const CrawlLimits(),
    SourceAdapter? Function(Source source, Uri baseUrl)? adapterFor,
  }) => Crawler(
    store: store,
    adapterFor: adapterFor ?? (source, baseUrl) => server,
    limits: limits,
    onProgress: events.add,
    wait: (delay) async => waits.add(delay),
  );

  /// Crawls the one source "a" at [base].
  Future<void> crawl({
    CrawlLimits limits = const CrawlLimits(),
    bool full = false,
  }) => crawler(limits: limits).crawl([
    _source('a', [base]),
  ], full: full);

  List<Object?> column(String sql) => [
    for (final row in library.db.select(sql)) row.values.first,
  ];

  List<String> requested() => [
    for (final url in server.requests)
      Uri.decodeComponent('$url'.substring('$base'.length)),
  ];

  CrawlProgress last([String sourceId = 'a']) =>
      events.lastWhere((event) => event.sourceId == sourceId);

  group('a crawl', () {
    test('reads every folder and keeps the videos it finds', () async {
      final movies = child(base, 'Movies');
      final series = child(base, 'TV Series');
      final show = child(series, 'Dark');
      server
        ..put(base, folders: ['Movies', 'TV Series'], files: ['readme.txt'])
        ..put(movies, files: ['Tenet.2020.mkv', 'Inception.2010.mp4'])
        ..put(series, folders: ['Dark'])
        ..put(show, files: ['Dark.S01E01.mkv', 'Dark.S01E02.mkv']);

      await crawl();

      expect(requested(), ['', 'Movies/', 'TV Series/', 'TV Series/Dark/']);
      expect(column('SELECT name FROM files ORDER BY name'), [
        'Dark.S01E01.mkv',
        'Dark.S01E02.mkv',
        'Inception.2010.mp4',
        'Tenet.2020.mkv',
      ]);
      final hit = store.search('dark s01e02', sourceIds: ['a']).single;
      expect(hit.url, show.resolve('Dark.S01E02.mkv'));
      expect(hit.path, 'TV Series/Dark');

      final stats = store.stats().single;
      expect(stats.pendingFolders, 0);
      expect(stats.crawlFinishedAt, isNotNull);
      expect(stats.lastError, isNull);
    });

    test('reports how far it is, and how it ended', () async {
      server
        ..put(base, folders: ['Movies'])
        ..put(child(base, 'Movies'), files: ['a.mkv', 'b.mkv']);

      await crawl();

      expect(events.first.state, CrawlState.running);
      expect(events.first.foldersRead, 0);
      expect([for (final event in events) event.foldersRead], [0, 1, 2, 2]);
      expect(events[2].folder, 'Movies');
      expect(last().state, CrawlState.complete);
      expect(last().filesAdded, 2);
      expect(last().foldersFailed, 0);
      expect(last().message, isNull);
    });

    test('keeps videos and their subtitles, nothing else', () async {
      server.put(
        base,
        files: [
          'Tenet.2020.mkv',
          'Tenet.2020.en.srt',
          'Other.Film.srt',
          'Inception.2010.mkv',
          'poster.jpg',
          'setup.exe',
          'Tenet.2020.mkv.part',
        ],
      );

      await crawl();

      expect(column('SELECT name FROM files ORDER BY name'), [
        'Inception.2010.mkv',
        'Tenet.2020.mkv',
      ]);
      expect(
        column(
          'SELECT f.name FROM subtitles s JOIN files f ON f.id = s.file '
          "WHERE s.name = 'Tenet.2020.en.srt'",
        ),
        ['Tenet.2020.mkv'],
      );
      expect(column('SELECT count(*) FROM subtitles'), [1]);
    });

    test('skips a source that has no adapter', () async {
      await crawler(adapterFor: (source, baseUrl) => null).crawl([
        _source('a', [base]),
      ]);

      expect(last().state, CrawlState.skipped);
      expect(store.stats(), isEmpty);
    });

    test('uses one adapter per base URL of a source', () async {
      final other = Uri.parse('http://a.test/more/');
      final second = _FakeServer()..put(other, files: ['b.mkv']);
      server.put(base, files: ['a.mkv']);
      final asked = <Uri>[];

      await crawler(
        adapterFor: (source, baseUrl) {
          asked.add(baseUrl);
          return baseUrl == base ? server : second;
        },
      ).crawl([
        _source('a', [base, other]),
      ]);

      expect(asked, [base, other]);
      expect(server.requests, [base]);
      expect(second.requests, [other]);
      expect(column('SELECT name FROM files ORDER BY name'), [
        'a.mkv',
        'b.mkv',
      ]);
    });
  });

  group('a "Subs" folder', () {
    test('next to a video holds its subtitles and is not kept', () async {
      final film = child(base, 'Tenet (2020)');
      server
        ..put(base, folders: ['Tenet (2020)'])
        ..put(
          film,
          folders: ['Subs'],
          files: ['Tenet.2020.mkv', 'Tenet.2020.srt'],
        )
        ..put(
          child(film, 'Subs'),
          files: ['English.srt', '2_Bangla.ass', 'x.txt'],
        );

      await crawl();

      expect(requested(), ['', 'Tenet (2020)/', 'Tenet (2020)/Subs/']);
      expect(column('SELECT name FROM subtitles ORDER BY id'), [
        'Tenet.2020.srt',
        'English.srt',
        '2_Bangla.ass',
      ]);
      expect(column('SELECT path FROM folders ORDER BY id'), [
        '',
        'Tenet (2020)',
      ]);
      expect(last().state, CrawlState.complete);
    });

    test('without videos next to it is a folder like any other', () async {
      server
        ..put(base, folders: ['Dub', 'Sub'])
        ..put(child(base, 'Dub'), files: ['Naruto.E01.dub.mkv'])
        ..put(child(base, 'Sub'), files: ['Naruto.E01.sub.mkv']);

      await crawl();

      expect(column('SELECT name FROM files ORDER BY name'), [
        'Naruto.E01.dub.mkv',
        'Naruto.E01.sub.mkv',
      ]);
      expect(store.search('naruto', sourceIds: ['a']).last.path, 'Sub');
    });

    test('that holds videos itself is crawled as a folder', () async {
      server
        ..put(base, folders: ['Subs'], files: ['Film.mkv'])
        ..put(child(base, 'Subs'), files: ['Film.subbed.mkv', 'Film.srt']);

      await crawl();

      expect(column('SELECT name FROM files ORDER BY name'), [
        'Film.mkv',
        'Film.subbed.mkv',
      ]);
      expect(column('SELECT path FROM folders ORDER BY id'), ['', 'Subs']);
    });

    test('that cannot be read does not cost the videos', () async {
      server.put(base, folders: ['Subs'], files: ['Film.mkv']);

      await crawl();

      expect(column('SELECT name FROM files'), ['Film.mkv']);
      expect(last().state, CrawlState.complete);
      expect(last().foldersFailed, 0);
    });
  });

  group('when a folder cannot be read', () {
    test('a timeout is tried again after a wait', () async {
      server
        ..put(base, files: ['a.mkv'])
        ..errorsOnce[base] = [_timeout, _down];

      await crawl();

      expect(server.requests, [base, base, base]);
      expect(waits, const [Duration(seconds: 2), Duration(seconds: 8)]);
      expect(last().state, CrawlState.complete);
      expect(last().filesAdded, 1);
    });

    test('a busy server is tried again', () async {
      server
        ..put(base, files: ['a.mkv'])
        ..errorsOnce[base] = [
          const SourceReadException(
            'The server answered 503.',
            statusCode: 503,
          ),
        ];

      await crawl();

      expect(waits, const [Duration(seconds: 2)]);
      expect(last().state, CrawlState.complete);
    });

    test(
      'a folder that is gone is not tried again, the rest goes on',
      () async {
        server
          ..put(base, folders: ['Gone', 'Movies'])
          ..put(child(base, 'Movies'), files: ['a.mkv']);

        await crawl();

        expect(requested(), ['', 'Gone/', 'Movies/']);
        expect(waits, isEmpty);
        expect(last().state, CrawlState.incomplete);
        expect(last().foldersFailed, 1);
        expect(
          last().message,
          '1 folder could not be read. Last problem: The server answered 404.',
        );
        expect(store.stats().single.failedFolders, 1);
        expect(store.stats().single.lastError, last().message);
        expect(column('SELECT name FROM files'), ['a.mkv']);
      },
    );

    test('it keeps what the index held of it', () async {
      final movies = child(base, 'Movies');
      server
        ..put(base, folders: ['Movies'])
        ..put(movies, files: ['a.mkv']);
      await crawl();

      server.broken[movies] = const SourceReadException(
        'The page is not a folder listing.',
      );
      await crawl();

      expect(last().state, CrawlState.incomplete);
      expect(column('SELECT name FROM files'), ['a.mkv']);
    });

    test('a server that stops answering is left for the next run', () async {
      const names = ['A', 'B', 'C', 'D', 'E'];
      server.put(base, folders: names);
      for (final name in names) {
        server
          ..put(child(base, name), files: ['$name.mkv'])
          ..broken[child(base, name)] = _down;
      }

      await crawl(limits: const CrawlLimits(requestsPerSource: 1));

      // Three tries for the first folder, then one each, then no more.
      expect(requested(), ['', 'A/', 'A/', 'A/', 'B/', 'C/']);
      expect(last().state, CrawlState.stopped);
      expect(last().message, contains('stopped answering'));
      final stats = store.stats().single;
      expect(stats.failedFolders, 3);
      expect(stats.pendingFolders, 2);
      expect(stats.crawlFinishedAt, isNull);

      // The server is back: the next run reads what is left, nothing else.
      server
        ..broken.clear()
        ..requests.clear();
      await crawl(limits: const CrawlLimits(requestsPerSource: 1));

      expect(requested(), ['A/', 'B/', 'C/', 'D/', 'E/']);
      expect(last().state, CrawlState.complete);
      expect(column('SELECT count(*) FROM files'), [5]);
      expect(store.stats().single.crawlFinishedAt, isNotNull);
    });
  });

  group('crawling again', () {
    final movies = child(base, 'Movies');
    final series = child(base, 'Series');
    final show = child(series, 'Dark');
    final june = DateTime(2026, 6, 1);

    setUp(() async {
      server
        ..put(
          base,
          folders: ['Movies', 'Series'],
          dates: {'Movies': june, 'Series': june},
        )
        ..put(movies, files: ['Tenet.2020.mkv'])
        ..put(series, folders: ['Dark'], dates: {'Dark': june})
        ..put(show, files: ['Dark.S01E01.mkv', 'Dark.S01E02.mkv']);
      await crawl();
      server.requests.clear();
    });

    test('skips folders that have not changed', () async {
      await crawl();

      // "Series" holds a folder, so only reading it shows what changed.
      expect(requested(), ['', 'Series/']);
      expect(last().state, CrawlState.complete);
      expect(last().filesAdded, 0);
      expect(column('SELECT count(*) FROM files'), [3]);
    });

    test('reads a folder with a new date: adds and removes files', () async {
      server
        ..put(
          base,
          folders: ['Movies', 'Series'],
          dates: {'Movies': DateTime(2026, 7, 1), 'Series': june},
        )
        ..put(movies, files: ['Dune.2021.mkv']);

      await crawl();

      expect(requested(), ['', 'Movies/', 'Series/']);
      expect(last().filesAdded, 1);
      expect(last().filesRemoved, 1);
      expect(store.search('tenet', sourceIds: ['a']), isEmpty);
      expect(store.search('dune', sourceIds: ['a']), hasLength(1));
    });

    test('removes a folder that is gone from the server', () async {
      server.put(base, folders: ['Movies'], dates: {'Movies': june});

      await crawl();

      expect(requested(), ['']);
      expect(column('SELECT name FROM files'), ['Tenet.2020.mkv']);
      expect(column('SELECT path FROM folders ORDER BY id'), ['', 'Movies']);
    });

    test('a full crawl reads every folder again', () async {
      // Changed without a new date on the folder: only a full crawl sees it.
      server.put(show, files: ['Dark.S01E01.mkv']);
      await crawl();
      expect(column('SELECT count(*) FROM files'), [3]);
      server.requests.clear();

      await crawl(full: true);

      expect(requested(), ['', 'Movies/', 'Series/', 'Series/Dark/']);
      expect(column('SELECT count(*) FROM files'), [2]);
    });
  });

  group('limits', () {
    test('folders below the depth limit are not read', () async {
      final one = child(base, '1');
      final two = child(one, '2');
      server
        ..put(base, folders: ['1'], files: ['0.mkv'])
        ..put(one, folders: ['2'], files: ['1.mkv'])
        ..put(two, folders: ['3'], files: ['2.mkv'])
        ..put(child(two, '3'), files: ['3.mkv']);

      await crawl(limits: const CrawlLimits(maxDepth: 2));

      expect(requested(), ['', '1/', '1/2/']);
      expect(column('SELECT name FROM files ORDER BY name'), [
        '0.mkv',
        '1.mkv',
        '2.mkv',
      ]);
      expect(last().state, CrawlState.complete);
    });

    test('a source is cut off at the folder limit', () async {
      server.put(base, folders: [for (var i = 0; i < 10; i++) 'F$i']);
      for (var i = 0; i < 10; i++) {
        server.put(child(base, 'F$i'), files: ['$i.mkv']);
      }

      await crawl(limits: const CrawlLimits(maxFoldersPerSource: 4));

      expect(requested(), ['', 'F0/', 'F1/', 'F2/']);
      expect(last().state, CrawlState.complete);
      expect(last().message, contains('more than 4 folders'));
    });

    test('at most two folders of a source are read at a time', () async {
      server.put(base, folders: [for (var i = 0; i < 8; i++) 'F$i']);
      for (var i = 0; i < 8; i++) {
        server.put(child(base, 'F$i'));
      }

      await crawl();

      expect(server.requests, hasLength(9));
      expect(server.mostAtOnce, 2);
    });

    test('sources on one host take turns', () async {
      final other = Uri.parse('http://a.test/other/');
      server
        ..put(base, folders: ['A', 'B'])
        ..put(child(base, 'A'))
        ..put(child(base, 'B'))
        ..put(other, folders: ['C'])
        ..put(child(other, 'C'));

      await crawler().crawl([
        _source('a', [base]),
        _source('b', [other]),
      ]);

      final paths = [for (final url in server.requests) url.path];
      expect(paths.take(3), everyElement(startsWith('/media/')));
      expect(paths.skip(3), ['/other/', '/other/C/']);
      expect(server.mostAtOnce, 2);
      expect(last('b').state, CrawlState.complete);
    });

    test('different hosts are crawled side by side', () async {
      final other = Uri.parse('http://b.test/');
      server
        ..put(base)
        ..put(other)
        ..gate = Completer();

      final done = crawler().crawl([
        _source('a', [base]),
        _source('b', [other]),
      ]);
      await pumpEventQueue();
      expect(server.requests, [base, other]);

      server.gate!.complete();
      await done;
      expect(last('a').state, CrawlState.complete);
      expect(last('b').state, CrawlState.complete);
    });
  });

  group('cancel', () {
    test('starts no new folder and keeps what was found', () async {
      server
        ..put(base, folders: ['A', 'B'], files: ['root.mkv'])
        ..put(child(base, 'A'), files: ['a.mkv'])
        ..put(child(base, 'B'), files: ['b.mkv'])
        ..gate = Completer();
      final running = crawler();

      final done = running.crawl([
        _source('a', [base]),
      ]);
      await pumpEventQueue();
      running.cancel();
      server.gate!.complete();
      await done;

      expect(server.requests, [base]);
      expect(last().state, CrawlState.cancelled);
      expect(column('SELECT name FROM files'), ['root.mkv']);
      expect(store.stats().single.pendingFolders, 2);

      // The next run carries on with the two folders left.
      server
        ..gate = null
        ..requests.clear();
      await crawl();
      expect(requested(), ['A/', 'B/']);
      expect(last().state, CrawlState.complete);
    });

    test('a request it cut off does not count against the folder', () async {
      server
        ..put(base, files: ['a.mkv'])
        ..errorsOnce[base] = [_down]
        ..gate = Completer();
      final running = crawler();

      final done = running.crawl([
        _source('a', [base]),
      ]);
      await pumpEventQueue();
      running.cancel();
      server.gate!.complete();
      await done;

      expect(last().state, CrawlState.cancelled);
      expect(last().foldersFailed, 0);
      final stats = store.stats().single;
      expect(stats.failedFolders, 0);
      expect(stats.pendingFolders, 1);
    });

    test('sources not started yet are left alone', () async {
      final other = Uri.parse('http://a.test/other/');
      server
        ..put(base)
        ..put(other)
        ..gate = Completer();
      final running = crawler();

      final done = running.crawl([
        _source('a', [base]),
        _source('b', [other]),
      ]);
      await pumpEventQueue();
      running.cancel();
      server.gate!.complete();
      await done;

      expect(server.requests, [base]);
      expect(events.where((event) => event.sourceId == 'b'), isEmpty);
    });
  });

  group('over real HTTP', () {
    late LocalServer web;
    late SafeHttpClient client;

    String page(String path, List<String> links) =>
        '''
<html><head><title>Index of $path</title></head><body>
<h1>Index of $path</h1><hr><pre><a href="../">../</a>
${[for (final link in links) '<a href="$link">$link</a>'].join('\n')}
</pre><hr></body></html>''';

    setUp(() async {
      web = await LocalServer.start();
      client = web.client();
    });

    tearDown(() async {
      client.close();
      await web.close();
    });

    test('crawls folder pages through the real adapter', () async {
      web
        ..serve('/m/', page('/m/', ['Busy/', 'Tenet%202020/', 'notes.txt']))
        ..serve(
          '/m/Tenet%202020/',
          page('/m/Tenet 2020/', [
            'Tenet.2020.1080p.mkv',
            'Tenet.2020.1080p.srt',
            'cover.jpg',
          ]),
        );
      var busyAnswers = 0;
      web.routes['/m/Busy/'] = (request) async {
        final busy = busyAnswers++ == 0;
        request.response
          ..statusCode = busy ? HttpStatus.serviceUnavailable : HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..write(busy ? 'Busy' : page('/m/Busy/', ['Dune.2021.mkv']));
        await request.response.close();
      };
      final source = _source('web', [web.url('/m/')]);

      await crawler(
        adapterFor: (source, baseUrl) => adapterFor(
          source.type,
          client,
          baseUrl: baseUrl,
          deviceId: 'dhara-test',
        ),
      ).crawl([source]);

      expect(last('web').state, CrawlState.complete);
      expect(waits, const [Duration(seconds: 2)]);
      expect(column('SELECT name FROM files ORDER BY name'), [
        'Dune.2021.mkv',
        'Tenet.2020.1080p.mkv',
      ]);
      expect(column('SELECT name FROM subtitles'), ['Tenet.2020.1080p.srt']);
      final hit = store.search('tenet', sourceIds: ['web']).single;
      expect(hit.url, web.url('/m/Tenet%202020/Tenet.2020.1080p.mkv'));
      expect(hit.path, 'Tenet 2020');
    });
  });
}
