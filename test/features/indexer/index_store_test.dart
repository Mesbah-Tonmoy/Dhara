import 'dart:math';

import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/features/indexer/index_store.dart';
import 'package:dhara/features/sources/adapters/source_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

final _base = Uri.parse('http://a.test/media/');

RemoteEntry _folder(Uri parent, String name, {DateTime? modified}) =>
    RemoteEntry(
      name: name,
      url: parent.resolve('${Uri.encodeComponent(name)}/'),
      isFolder: true,
      modified: modified,
    );

RemoteEntry _file(Uri parent, String name, {int? size, DateTime? modified}) =>
    RemoteEntry(
      name: name,
      url: parent.resolve(Uri.encodeComponent(name)),
      isFolder: false,
      size: size,
      modified: modified,
    );

void main() {
  late LibraryDb library;
  late IndexStore store;
  late DateTime now;

  setUp(() {
    library = LibraryDb.inMemory();
    now = DateTime(2026, 11, 13, 10);
    store = IndexStore(library, now: () => now);
  });

  tearDown(() => library.close());

  List<Object?> column(String sql, [List<Object?> parameters = const []]) => [
    for (final row in library.db.select(sql, parameters)) row.values.first,
  ];

  List<String> fileNames() =>
      column('SELECT name FROM files ORDER BY name').cast<String>();

  List<String> found(String text, {List<String> sources = const ['a']}) => [
    for (final hit in store.search(text, sourceIds: sources)) hit.name,
  ];

  ListingChanges save(
    PendingFolder folder, {
    List<RemoteEntry> folders = const [],
    List<IndexedVideo> videos = const [],
    int maxDepth = 12,
    int folderBudget = 1000,
  }) => store.saveListing(
    folder,
    FolderListing(folders: folders, videos: videos),
    maxDepth: maxDepth,
    folderBudget: folderBudget,
  );

  /// Starts a crawl of source "a" and returns its base folder.
  PendingFolder begin({bool full = false}) {
    final source = store.beginCrawl('a', [_base], full: full);
    return store.pendingFolders(source).first;
  }

  // Source "a" is always the first one, so its key is 1.
  PendingFolder pending(String path) =>
      store.pendingFolders(1).singleWhere((folder) => folder.path == path);

  List<String> pendingPaths() => [
    for (final folder in store.pendingFolders(1)) folder.path,
  ];

  group('beginCrawl', () {
    test('queues the base URLs of a new source', () {
      final other = Uri.parse('http://a.test/more/');

      final source = store.beginCrawl('a', [_base, other]);

      final folders = store.pendingFolders(source);
      expect([for (final folder in folders) folder.url], [_base, other]);
      expect(folders.every((f) => f.path.isEmpty && f.depth == 0), isTrue);
      expect(store.stats().single.crawlStartedAt, now);
    });

    test('gives a source the same key every time', () {
      final first = store.beginCrawl('a', [_base]);
      final other = store.beginCrawl('b', [Uri.parse('http://b.test/')]);

      expect(store.beginCrawl('a', [_base]), first);
      expect(other, isNot(first));
    });

    test('carries on a crawl that was cut short', () {
      final root = begin();
      save(root, folders: [_folder(_base, 'Movies'), _folder(_base, 'Series')]);
      save(pending('Movies'));
      final started = now;
      now = now.add(const Duration(hours: 1));

      store.beginCrawl('a', [_base]);

      expect(pendingPaths(), ['Series']);
      expect(store.stats().single.crawlStartedAt, started);
    });

    test('starts at the base URLs again once a crawl is complete', () {
      final root = begin();
      save(root, folders: [_folder(_base, 'Movies')]);
      save(pending('Movies'));
      store.finishCrawl(1);
      now = now.add(const Duration(days: 1));

      store.beginCrawl('a', [_base]);

      expect(pendingPaths(), ['']);
      expect(store.stats().single.crawlStartedAt, now);
    });

    test('gives folders that failed a new chance', () {
      final root = begin();
      save(root, folders: [_folder(_base, 'Movies')]);
      store.markFailed(pending('Movies').id);
      store.finishCrawl(1);
      expect(store.stats().single.failedFolders, 1);

      store.beginCrawl('a', [_base]);

      expect(pendingPaths(), ['', 'Movies']);
      expect(store.stats().single.failedFolders, 0);
    });

    test('removes what was below a base URL the source no longer has', () {
      final other = Uri.parse('http://a.test/more/');
      final source = store.beginCrawl('a', [_base, other]);
      for (final root in store.pendingFolders(source)) {
        save(root, videos: [IndexedVideo(_file(root.url, 'x.mkv'))]);
      }
      expect(fileNames(), hasLength(2));

      store.beginCrawl('a', [other]);

      expect(column('SELECT url FROM files'), ['http://a.test/more/x.mkv']);
    });

    test('with full, also reads folders that have not changed', () {
      final date = DateTime(2025, 3, 1);
      final movies = _folder(_base, 'Movies', modified: date);
      save(begin(), folders: [movies]);
      save(pending('Movies'));
      store.finishCrawl(1);

      save(begin(), folders: [movies]);
      expect(pendingPaths(), isEmpty);
      store.finishCrawl(1);

      save(begin(full: true), folders: [movies]);
      expect(pendingPaths(), ['Movies']);
    });
  });

  group('saveListing', () {
    test('adds the videos, their subtitles and the folders inside', () {
      final root = begin();
      final video = _file(
        _base,
        'Tenet.2020.mkv',
        size: 5000,
        modified: DateTime(2024, 5, 1),
      );

      final changes = save(
        root,
        folders: [_folder(_base, 'Series')],
        videos: [
          IndexedVideo(video, [_file(_base, 'Tenet.2020.en.srt')]),
          IndexedVideo(_file(_base, 'Inception.2010.mp4')),
        ],
      );

      expect(changes.filesAdded, 2);
      expect(changes.filesRemoved, 0);
      expect(changes.foldersAdded, 1);
      expect(fileNames(), ['Inception.2010.mp4', 'Tenet.2020.mkv']);
      expect(column('SELECT name FROM subtitles'), ['Tenet.2020.en.srt']);

      final next = store.pendingFolders(1).single;
      expect(next.path, 'Series');
      expect(next.depth, 1);
      expect(next.url, Uri.parse('http://a.test/media/Series/'));

      final hit = store.search('tenet', sourceIds: ['a']).single;
      expect(hit.url, video.url);
      expect(hit.size, 5000);
      expect(hit.modified, DateTime(2024, 5, 1));
      expect(hit.sourceId, 'a');
      expect(hit.path, '');
    });

    test('builds the path of a folder from the names above it', () {
      save(begin(), folders: [_folder(_base, 'TV Series')]);
      final series = pending('TV Series');
      save(series, folders: [_folder(series.url, 'Breaking Bad')]);
      final show = pending('TV Series/Breaking Bad');
      save(show, videos: [IndexedVideo(_file(show.url, 'S01E01.mkv'))]);

      expect(show.depth, 2);
      expect(found('breaking bad'), ['S01E01.mkv']);
      expect(
        store.search('s01e01', sourceIds: ['a']).single.path,
        'TV Series/Breaking Bad',
      );
    });

    test('reading the same listing again changes nothing', () {
      final videos = [
        IndexedVideo(_file(_base, 'a.mkv', size: 1), [_file(_base, 'a.srt')]),
      ];
      save(begin(), videos: videos);
      final ids = column(
        'SELECT id FROM files UNION ALL '
        'SELECT id FROM subtitles',
      );
      store.finishCrawl(1);

      final changes = save(begin(), videos: videos);

      expect(changes.filesAdded, 0);
      expect(changes.filesRemoved, 0);
      expect(
        column('SELECT id FROM files UNION ALL SELECT id FROM subtitles'),
        ids,
      );
    });

    test('removes a video that is no longer listed', () {
      final kept = IndexedVideo(_file(_base, 'Tenet.2020.mkv'));
      save(
        begin(),
        videos: [
          kept,
          IndexedVideo(_file(_base, 'Tenet.2020.CAM.mkv'), [
            _file(_base, 'Tenet.2020.CAM.srt'),
          ]),
        ],
      );
      store.finishCrawl(1);

      final changes = save(begin(), videos: [kept]);

      expect(changes.filesRemoved, 1);
      expect(found('tenet'), ['Tenet.2020.mkv']);
      expect(column('SELECT count(*) FROM subtitles'), [0]);
    });

    test('keeps the first-seen time and updates size and date', () {
      save(begin(), videos: [IndexedVideo(_file(_base, 'a.mkv', size: 1))]);
      store.finishCrawl(1);
      final firstSeen = now;
      now = now.add(const Duration(days: 3));

      save(
        begin(),
        videos: [
          IndexedVideo(
            _file(_base, 'a.mkv', size: 2, modified: DateTime(2026, 1, 1)),
          ),
          IndexedVideo(_file(_base, 'b.mkv')),
        ],
      );

      expect(
        library.db
            .select(
              'SELECT name, size, modified, added_at FROM files ORDER BY name',
            )
            .map((row) => row.values),
        [
          [
            'a.mkv',
            2,
            DateTime(2026, 1, 1).millisecondsSinceEpoch,
            firstSeen.millisecondsSinceEpoch,
          ],
          ['b.mkv', null, null, now.millisecondsSinceEpoch],
        ],
      );
    });

    test('replaces the subtitles of a video when they change', () {
      final video = _file(_base, 'a.mkv');
      save(
        begin(),
        videos: [
          IndexedVideo(video, [_file(_base, 'a.en.srt')]),
        ],
      );
      store.finishCrawl(1);

      save(
        begin(),
        videos: [
          IndexedVideo(video, [
            _file(_base, 'a.en.srt'),
            _file(_base, 'a.bn.srt'),
          ]),
        ],
      );

      expect(column('SELECT name FROM subtitles ORDER BY id'), [
        'a.en.srt',
        'a.bn.srt',
      ]);
    });

    test('a file renamed at the same address is found by its new name', () {
      final url = Uri.parse('http://a.test/media/stream?id=7');
      RemoteEntry named(String name) =>
          RemoteEntry(name: name, url: url, isFolder: false);
      save(begin(), videos: [IndexedVideo(named('Old Title.mkv'))]);
      store.finishCrawl(1);
      final firstSeen = now;
      now = now.add(const Duration(days: 1));

      final changes = save(begin(), videos: [IndexedVideo(named('New.mkv'))]);

      expect(changes.filesAdded, 0);
      expect(found('old'), isEmpty);
      expect(found('new'), ['New.mkv']);
      expect(column('SELECT added_at FROM files'), [
        firstSeen.millisecondsSinceEpoch,
      ]);
    });

    test('removes a folder that is no longer listed, with its content', () {
      save(begin(), folders: [_folder(_base, 'Movies'), _folder(_base, 'Old')]);
      final old = pending('Old');
      save(
        old,
        folders: [_folder(old.url, 'Deeper')],
        videos: [IndexedVideo(_file(old.url, 'x.mkv'))],
      );
      final deeper = pending('Old/Deeper');
      save(deeper, videos: [IndexedVideo(_file(deeper.url, 'y.mkv'))]);
      save(pending('Movies'));
      store.finishCrawl(1);
      expect(fileNames(), ['x.mkv', 'y.mkv']);

      save(begin(), folders: [_folder(_base, 'Movies')]);

      expect(fileNames(), isEmpty);
      expect(column('SELECT path FROM folders ORDER BY id'), ['', 'Movies']);
      expect(found('x'), isEmpty);
    });

    test('a folder renamed at the same address starts over', () {
      final url = Uri.parse('http://a.test/media/Items?ParentId=5');
      RemoteEntry named(String name) =>
          RemoteEntry(name: name, url: url, isFolder: true);
      save(begin(), folders: [named('Old Show')]);
      final show = pending('Old Show');
      save(show, videos: [IndexedVideo(_file(_base, 'S01E01.mkv'))]);
      store.finishCrawl(1);

      save(begin(), folders: [named('New Show')]);

      expect(pendingPaths(), ['New Show']);
      expect(fileNames(), isEmpty);
    });

    test('ignores entries listed twice', () {
      final changes = save(
        begin(),
        folders: [_folder(_base, 'Movies'), _folder(_base, 'Movies')],
        videos: [
          IndexedVideo(_file(_base, 'a.mkv')),
          IndexedVideo(_file(_base, 'a.mkv')),
        ],
      );

      expect(changes.filesAdded, 1);
      expect(changes.foldersAdded, 1);
    });

    test('does not take over a folder that is reached another way', () {
      final shared = Uri.parse('http://a.test/media/Items?ParentId=9');
      RemoteEntry link() =>
          RemoteEntry(name: 'Shared', url: shared, isFolder: true);
      save(begin(), folders: [_folder(_base, 'A'), _folder(_base, 'B')]);
      save(pending('A'), folders: [link()]);

      final changes = save(pending('B'), folders: [link()]);

      expect(changes.foldersAdded, 0);
      expect(column('SELECT path FROM folders WHERE url = ?', ['$shared']), [
        'A/Shared',
      ]);
    });

    test('leaves out folders below the depth limit', () {
      save(begin(), folders: [_folder(_base, 'One')], maxDepth: 1);
      final one = pending('One');

      final changes = save(
        one,
        folders: [_folder(one.url, 'Two')],
        videos: [IndexedVideo(_file(one.url, 'a.mkv'))],
        maxDepth: 1,
      );

      expect(changes.foldersAdded, 0);
      expect(changes.filesAdded, 1);
      expect(pendingPaths(), isEmpty);
    });

    test('adds no more new folders than the budget allows', () {
      final changes = save(
        begin(),
        folders: [for (var i = 0; i < 5; i++) _folder(_base, 'F$i')],
        folderBudget: 2,
      );

      expect(changes.foldersAdded, 2);
      expect(pendingPaths(), ['F0', 'F1']);
      expect(store.folderCount(1), 3);
    });

    test('does nothing for a folder that is gone meanwhile', () {
      save(begin(), folders: [_folder(_base, 'Movies')]);
      final movies = pending('Movies');
      store.removeSourcesExcept(const []);

      final changes = save(
        movies,
        videos: [IndexedVideo(_file(movies.url, 'a.mkv'))],
      );

      expect(changes.filesAdded, 0);
      expect(fileNames(), isEmpty);
    });
  });

  group('folders that can be skipped', () {
    final date = DateTime(2025, 3, 1);

    /// Crawls base > Movies (> Sub if [withSubfolder]) to the end, then
    /// reads the base again with [second] as the entry for Movies.
    void crawlTwice(
      RemoteEntry first,
      RemoteEntry second, {
      bool nested = false,
    }) {
      save(begin(), folders: [first]);
      final movies = pending('Movies');
      save(movies, folders: [if (nested) _folder(movies.url, 'Sub')]);
      if (nested) save(pending('Movies/Sub'));
      store.finishCrawl(1);

      save(begin(), folders: [second]);
    }

    test('a folder without folders and with the same date is not read', () {
      final movies = _folder(_base, 'Movies', modified: date);
      crawlTwice(movies, movies);

      expect(pendingPaths(), isEmpty);
    });

    test('a folder with a new date is read again', () {
      crawlTwice(
        _folder(_base, 'Movies', modified: date),
        _folder(_base, 'Movies', modified: date.add(const Duration(days: 1))),
      );

      expect(pendingPaths(), ['Movies']);
    });

    test('a folder is read again if the server gives no dates', () {
      crawlTwice(_folder(_base, 'Movies'), _folder(_base, 'Movies'));

      expect(pendingPaths(), ['Movies']);
    });

    test('a folder that holds folders is always read again', () {
      final movies = _folder(_base, 'Movies', modified: date);
      crawlTwice(movies, movies, nested: true);

      expect(pendingPaths(), ['Movies']);
    });

    test('a folder that failed is read again', () {
      final movies = _folder(_base, 'Movies', modified: date);
      save(begin(), folders: [movies]);
      store.markFailed(pending('Movies').id);
      store.finishCrawl(1);

      save(begin(), folders: [movies]);

      expect(pendingPaths(), ['Movies']);
    });
  });

  group('markFailed and finishCrawl', () {
    test('a failed folder keeps what the index has of it', () {
      final root = begin();
      save(root, videos: [IndexedVideo(_file(_base, 'a.mkv'))]);
      store.finishCrawl(1);

      store.markFailed(begin().id);

      expect(fileNames(), ['a.mkv']);
      expect(store.stats().single.failedFolders, 1);
    });

    test('a crawl is complete when no folder is left waiting', () {
      final root = begin();
      save(root, folders: [_folder(_base, 'Movies')]);

      store.finishCrawl(1, error: 'The server stopped answering.');
      var stats = store.stats().single;
      expect(stats.crawlFinishedAt, isNull);
      expect(stats.pendingFolders, 1);
      expect(stats.lastError, 'The server stopped answering.');

      save(pending('Movies'));
      now = now.add(const Duration(minutes: 5));
      store.finishCrawl(1);
      stats = store.stats().single;
      expect(stats.crawlFinishedAt, now);
      expect(stats.pendingFolders, 0);
      expect(stats.lastError, isNull);
    });
  });

  group('removeSourcesExcept', () {
    test('removes the other sources with everything found on them', () {
      final other = Uri.parse('http://b.test/');
      save(begin(), videos: [IndexedVideo(_file(_base, 'a.mkv'))]);
      final b = store.pendingFolders(store.beginCrawl('b', [other])).single;
      save(b, videos: [IndexedVideo(_file(other, 'b.mkv'))]);

      store.removeSourcesExcept(['b', 'never-crawled']);

      expect([for (final stats in store.stats()) stats.sourceId], ['b']);
      expect(fileNames(), ['b.mkv']);
      expect(found('a', sources: ['a', 'b']), isEmpty);

      store.removeSourcesExcept(const []);
      expect(store.stats(), isEmpty);
      expect(fileNames(), isEmpty);
    });
  });

  group('stats', () {
    test('counts files and folders of each source', () {
      save(
        begin(),
        folders: [_folder(_base, 'Movies'), _folder(_base, 'Series')],
        videos: [IndexedVideo(_file(_base, 'a.mkv'))],
      );
      final movies = pending('Movies');
      save(
        movies,
        videos: [
          IndexedVideo(_file(movies.url, 'b.mkv')),
          IndexedVideo(_file(movies.url, 'c.mkv')),
        ],
      );
      store.beginCrawl('b', [Uri.parse('http://b.test/')]);

      final [a, b] = store.stats();

      expect(a.sourceId, 'a');
      expect(a.files, 3);
      expect(a.folders, 3);
      expect(a.pendingFolders, 1);
      expect(a.failedFolders, 0);
      expect(b.sourceId, 'b');
      expect(b.files, 0);
      expect(b.folders, 1);
    });
  });

  group('search', () {
    setUp(() {
      save(
        begin(),
        videos: [
          for (final name in [
            'The.Dark.Knight.2008.1080p.mkv',
            'The.Dark.Knight.Rises.2012.720p.mkv',
            'Dark.City.1998.mkv',
            'Inception.2010.mkv',
          ])
            IndexedVideo(_file(_base, name)),
        ],
      );
    });

    test('needs every word, in any order', () {
      expect(found('knight dark'), hasLength(2));
      expect(found('dark 1998'), ['Dark.City.1998.mkv']);
      expect(found('dark inception'), isEmpty);
    });

    test('takes the last word as the start of a word', () {
      expect(found('dark kni'), hasLength(2));
      expect(found('incep'), ['Inception.2010.mkv']);
      // Only the last word may be unfinished.
      expect(found('kni dark'), isEmpty);
    });

    test('takes a pasted file name', () {
      expect(found('The.Dark.Knight.2008'), ['The.Dark.Knight.2008.1080p.mkv']);
    });

    test('only returns files of the sources asked for', () {
      expect(found('dark', sources: ['b']), isEmpty);
      expect(found('dark', sources: const []), isEmpty);
      expect(found('dark', sources: ['b', 'a']), hasLength(3));
    });

    test('returns no more than the limit', () {
      expect(store.search('dark', sourceIds: ['a'], limit: 2), hasLength(2));
    });

    test('nothing typed finds nothing, and nothing typed breaks it', () {
      for (final text in [
        '',
        '   ',
        '"',
        '""',
        '*',
        '-',
        '(',
        'dark AND',
        'NOT dark',
        'dark OR',
        'name:dark',
        'dark"knight',
        "dark' OR 1=1 --",
        'NEAR(dark knight)',
        '^dark',
        'dark + knight',
        '🎬',
        'ডার্ক',
      ]) {
        expect(() => found(text), returnsNormally, reason: text);
      }
      expect(found(''), isEmpty);
      expect(found(' - * " '), isEmpty);
      expect(found('NOT dark'), isEmpty);
    });
  });

  group('ftsWordsQueryFor', () {
    test('names every word by itself, cut where the index cuts names', () {
      expect(ftsWordsQueryFor('dark'), '"dark"*');
      expect(
        ftsWordsQueryFor('Breaking.Bad s01e02'),
        '"Breaking" "Bad" "s01e02"*',
      );
      expect(ftsWordsQueryFor('say "hi" (2019)'), '"say" "hi" "2019"*');
      // The index cuts at Bangla vowel signs too: they are no letters.
      expect(ftsWordsQueryFor('ফিল্ম amélie'), '"ফ" "ল" "ম" "amélie"*');
      expect(ftsWordsQueryFor(' -. '), isNull);
      expect(ftsWordsQueryFor(''), isNull);
    });
  });

  group('ftsQueryFor', () {
    test('quotes every word and leaves the last one open', () {
      expect(ftsQueryFor('dark'), '"dark"*');
      expect(ftsQueryFor('  The  dark kni '), '"The" "dark" "kni"*');
      expect(ftsQueryFor('say "hi"'), '"say" """hi"""*');
    });

    test('drops what holds no letter or digit', () {
      expect(ftsQueryFor('dark - knight'), '"dark" "knight"*');
      expect(ftsQueryFor(' - '), isNull);
      expect(ftsQueryFor(''), isNull);
    });

    test('keeps a very long text short', () {
      final query = ftsQueryFor(List.filled(100, 'word').join(' '))!;

      expect('"word"'.allMatches(query), hasLength(12));
    });
  });

  group('with 100,000 files', () {
    test('search answers within 100 ms', () {
      final random = Random(7);
      final words = [
        for (var i = 0; i < 4000; i++)
          String.fromCharCodes([
            for (var c = 0; c < 3 + random.nextInt(6); c++)
              0x61 + random.nextInt(26),
          ]),
      ];
      String word() => words[random.nextInt(words.length)];
      const qualities = ['480p', '720p', '1080p', '2160p'];

      final source = store.beginCrawl('big', [Uri.parse('http://big.test/')]);
      final root = store.pendingFolders(source).single;
      save(
        root,
        folders: [for (var i = 0; i < 2000; i++) _folder(root.url, 'F$i')],
        folderBudget: 5000,
      );
      final writing = Stopwatch()..start();
      for (final folder in store.pendingFolders(source, limit: 5000)) {
        save(
          folder,
          videos: [
            for (var i = 0; i < 50; i++)
              IndexedVideo(
                _file(
                  folder.url,
                  '${word()}.${word()}.${word()}.${1950 + random.nextInt(76)}.'
                  '${qualities[random.nextInt(4)]}.BluRay.x264-$i.mkv',
                  size: random.nextInt(1 << 32),
                ),
              ),
          ],
        );
      }
      writing.stop();
      expect(column('SELECT count(*) FROM files'), [100000]);

      final timings = <String, int>{};
      for (final text in [
        '${words[10]} ${words[20].substring(0, 2)}',
        words[30],
        words[40].substring(0, 2),
        'th',
        '1080p',
        'bluray x264 1080p 2010',
        'F1999 ${words[50].substring(0, 1)}',
      ]) {
        final watch = Stopwatch()..start();
        store.search(text, sourceIds: ['big']);
        timings[text] = watch.elapsedMilliseconds;
      }
      // Shown with `flutter test --reporter expanded`.
      printOnFailure('writing 100k files: ${writing.elapsedMilliseconds} ms');

      expect(timings.values.reduce(max), lessThan(100), reason: '$timings');
    });
  });
}
