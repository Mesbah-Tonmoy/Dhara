import 'dart:convert';
import 'dart:io';

import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/core/secrets/secret_store.dart';
import 'package:dhara/features/indexer/index_controller.dart';
import 'package:dhara/features/indexer/index_store.dart';
import 'package:dhara/features/indexer/ui/index_screen.dart';
import 'package:dhara/features/metadata/match_controller.dart';
import 'package:dhara/features/metadata/titles_controller.dart';
import 'package:dhara/features/metadata/tmdb_key.dart';
import 'package:dhara/features/snapshot/snapshot_controller.dart';
import 'package:dhara/features/sources/adapters/source_adapter.dart';
import 'package:dhara/features/sources/source.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:dhara/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 11, 13, 12);

Source _source(String id, {SourceType type = SourceType.h5ai}) => Source(
  id: id,
  name: 'Server $id',
  type: type,
  category: SourceCategory.movies,
  baseUrls: [Uri.parse('http://10.0.0.1/$id/')],
);

/// Puts a finished crawl of [source] into the index, [age] ago, that
/// found [files] (name and size) in its base folder.
void _index(
  LibraryDb db,
  Source source, {
  Duration age = Duration.zero,
  Map<String, int> files = const {},
  String? error,
}) {
  final store = IndexStore(db, now: () => _now.subtract(age));
  final base = source.baseUrls.single;
  final key = store.beginCrawl(source.id, [base]);
  store.saveListing(
    store.pendingFolders(key).single,
    FolderListing(
      folders: [
        RemoteEntry(name: 'Films', url: base.resolve('Films/'), isFolder: true),
      ],
    ),
    maxDepth: 12,
    folderBudget: 100,
  );
  store.saveListing(
    store.pendingFolders(key).single,
    FolderListing(
      videos: [
        for (final MapEntry(key: name, value: size) in files.entries)
          IndexedVideo(
            RemoteEntry(
              name: name,
              url: base.resolve('Films/$name'),
              isFolder: false,
              size: size,
            ),
          ),
      ],
    ),
    maxDepth: 12,
    folderBudget: 100,
  );
  store.finishCrawl(key, error: error);
}

void main() {
  /// Shows the screen for [sources], of which [enabled] are switched on,
  /// over an index that [fill] has prepared.
  Future<IndexController> show(
    WidgetTester tester, {
    List<Source> sources = const [],
    List<String> enabled = const [],
    void Function(LibraryDb db)? fill,
    String? notice,
  }) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final db = LibraryDb.inMemory();
    addTearDown(db.close);
    fill?.call(db);
    final store = SourceStore(starter: sources);
    await store.setEnabled(enabled, enabled: true);
    final index = IndexController(
      library: LocalLibrary(db),
      sources: store,
      deviceId: 'dhara-test',
      startupNotice: notice,
      clock: () => _now,
    );
    addTearDown(index.dispose);
    await index.load();

    await tester.pumpWidget(
      IndexScope(
        controller: index,
        child: MaterialApp(theme: buildDharaTheme(), home: const IndexScreen()),
      ),
    );
    return index;
  }

  String status(WidgetTester tester, String id) =>
      tester.widget<Text>(find.byKey(Key('index-status-$id'))).data!;

  Future<void> search(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('index-search')), text);
    // The search waits until typing pauses.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
  }

  testWidgets('lists the enabled servers with what the index holds', (
    tester,
  ) async {
    final alpha = _source('alpha');
    await show(
      tester,
      sources: [
        alpha,
        _source('beta'),
        _source('gamma'),
        _source('site', type: SourceType.customSite),
      ],
      enabled: ['alpha', 'beta', 'site'],
      fill: (db) => _index(
        db,
        alpha,
        age: const Duration(hours: 3),
        files: {'Tenet.2020.mkv': 1717986918, 'Dune.2021.mkv': 734003200},
      ),
    );

    expect(find.text('Server alpha'), findsOneWidget);
    expect(status(tester, 'alpha'), 'Indexed 3 h ago');
    expect(find.text('2 videos'), findsOneWidget);
    expect(status(tester, 'beta'), 'Not indexed yet');
    expect(find.text('0 videos'), findsOneWidget);
    // Switched off: not part of the index.
    expect(find.text('Server gamma'), findsNothing);
    // Switched on, but a website without an adapter: listed, so that it
    // does not seem to be missing, and not counted.
    expect(find.text('Server site'), findsOneWidget);
    expect(status(tester, 'site'), contains('cannot read yet'));
    expect(find.text('not counted'), findsOneWidget);

    expect(find.text('2'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('3 h ago'), findsOneWidget);
    expect(find.byKey(const Key('index-start-stop')), findsOneWidget);
    expect(find.text('Update index'), findsOneWidget);
    expect(find.text('Full re-check'), findsOneWidget);
  });

  testWidgets('says what went wrong on a server', (tester) async {
    final alpha = _source('alpha');
    await show(
      tester,
      sources: [alpha],
      enabled: ['alpha'],
      fill: (db) => _index(
        db,
        alpha,
        error: '2 folders could not be read. Last problem: No answer.',
      ),
    );

    expect(
      status(tester, 'alpha'),
      '2 folders could not be read. Last problem: No answer.',
    );
  });

  testWidgets('says so when a crawl was cut short', (tester) async {
    final alpha = _source('alpha');
    await show(
      tester,
      sources: [alpha],
      enabled: ['alpha'],
      fill: (db) => IndexStore(db).beginCrawl('alpha', alpha.baseUrls),
    );

    expect(status(tester, 'alpha'), 'Unfinished · 1 folders still to read');
    expect(find.text('0 / 1'), findsOneWidget);
  });

  testWidgets('finds indexed files while typing', (tester) async {
    final alpha = _source('alpha');
    await show(
      tester,
      sources: [alpha],
      enabled: ['alpha'],
      fill: (db) => _index(
        db,
        alpha,
        files: {'Tenet.2020.mkv': 1717986918, 'Dune.2021.mkv': 734003200},
      ),
    );

    await search(tester, 'ten');

    expect(find.text('Tenet.2020.mkv'), findsOneWidget);
    expect(find.text('Server alpha  ·  Films  ·  1.6 GB'), findsOneWidget);
    expect(find.text('Dune.2021.mkv'), findsNothing);
    expect(find.text('1 FILE'), findsOneWidget);
    // The servers make room for the results.
    expect(find.byKey(const Key('index-status-alpha')), findsNothing);

    await search(tester, 'nothing like this');
    expect(find.text('NOTHING FOUND'), findsOneWidget);

    await search(tester, '2021');
    expect(find.text('Server alpha  ·  Films  ·  700 MB'), findsOneWidget);

    await search(tester, '');
    expect(find.byKey(const Key('index-status-alpha')), findsOneWidget);
    expect(find.text('ENABLED SERVERS'), findsOneWidget);
  });

  testWidgets('marks files of a media server as not playable yet', (
    tester,
  ) async {
    final emby = _source('emby', type: SourceType.emby);
    await show(
      tester,
      sources: [emby],
      enabled: ['emby'],
      fill: (db) => _index(db, emby, files: {'Tenet.2020.mkv': 1048576}),
    );

    await search(tester, 'tenet');

    expect(
      find.text('Server emby  ·  Films  ·  1 MB  ·  cannot be played yet'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
  });

  testWidgets('asks for servers when none is enabled', (tester) async {
    await show(tester, sources: [_source('alpha')]);

    expect(find.text('No servers to index'), findsOneWidget);
    expect(find.byKey(const Key('index-start-stop')), findsNothing);
  });

  testWidgets('with only a website switched on there is nothing to update', (
    tester,
  ) async {
    await show(
      tester,
      sources: [_source('site', type: SourceType.customSite)],
      enabled: ['site'],
    );

    expect(find.text('Server site'), findsOneWidget);
    expect(find.text('0 / 0'), findsOneWidget);
    expect(find.text('No servers to index'), findsNothing);
    expect(find.byKey(const Key('index-start-stop')), findsNothing);
  });

  testWidgets('shows what happened to the index file at start-up', (
    tester,
  ) async {
    await show(tester, notice: 'The index file was damaged.');

    expect(find.text('The index file was damaged.'), findsOneWidget);
  });

  testWidgets('follows the source list: a server switched on appears', (
    tester,
  ) async {
    final index = await show(tester, sources: [_source('alpha')]);

    await index.sources.setEnabled(['alpha'], enabled: true);
    await tester.pump();

    expect(find.text('Server alpha'), findsOneWidget);
    expect(find.byKey(const Key('index-start-stop')), findsOneWidget);
  });

  group('a snapshot of the library', () {
    late Directory folder;

    setUp(() => folder = Directory.systemTemp.createTempSync('dhara-index-'));
    tearDown(() => folder.deleteSync(recursive: true));

    /// Shows the screen of a development build, whose dialogs answer with
    /// [path]: where to save a snapshot, and which one to read.
    Future<LibrarySnapshotController> show(
      WidgetTester tester,
      String? path,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final db = LibraryDb.inMemory();
      addTearDown(db.close);
      final library = LocalLibrary(db);
      final index = IndexController(
        library: library,
        sources: SourceStore(starter: [_source('alpha')]),
        deviceId: 'dhara-test',
      );
      addTearDown(index.dispose);
      final titles = TitlesController(library: library, index: index);
      final snapshots = LibrarySnapshotController(
        library: library,
        index: index,
        titles: titles,
        match: MatchController(
          library: library,
          titles: titles,
          tmdbKey: TmdbKeyController(MemorySecretStore()),
        ),
      );
      addTearDown(snapshots.dispose);
      await tester.pumpWidget(
        IndexScope(
          controller: index,
          child: LibrarySnapshotScope(
            controller: snapshots,
            child: MaterialApp(
              theme: buildDharaTheme(),
              home: IndexScreen(
                pickSnapshotPath: () async => path,
                pickSnapshotFile: () async => path,
              ),
            ),
          ),
        ),
      );
      return snapshots;
    }

    testWidgets('is written where the user says, and the page says so', (
      tester,
    ) async {
      final path = '${folder.path}${Platform.pathSeparator}library.gz';
      await show(tester, path);
      expect(find.byKey(const Key('index-snapshot-status')), findsNothing);

      await tester.tap(find.byKey(const Key('index-snapshot')));
      await tester.pumpAndSettle();

      expect(File(path).existsSync(), isTrue);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('index-snapshot-status')))
            .data,
        allOf(
          startsWith('Snapshot written: 0 videos and 0 titles in 1 KB'),
          endsWith(path),
        ),
      );
      expect(find.text('Write snapshot'), findsOneWidget);
    });

    testWidgets('is not written when the user cancels', (tester) async {
      final snapshots = await show(tester, null);

      await tester.tap(find.byKey(const Key('index-snapshot')));
      await tester.pumpAndSettle();

      expect(snapshots.written, isNull);
      expect(folder.listSync(), isEmpty);
      expect(find.byKey(const Key('index-snapshot-status')), findsNothing);
    });

    testWidgets('that cannot be written is said to have failed', (
      tester,
    ) async {
      final separator = Platform.pathSeparator;
      await show(tester, '${folder.path}${separator}missing${separator}a.gz');

      await tester.tap(find.byKey(const Key('index-snapshot')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(find.byKey(const Key('index-snapshot-status')))
            .data,
        startsWith('The snapshot could not be written there.'),
      );
    });

    String? status(WidgetTester tester) => tester
        .widget<Text>(find.byKey(const Key('index-snapshot-status')))
        .data;

    /// Lets a reading that was started get through the file and tell the
    /// index, and the names of the videos be read after it.
    Future<void> settle(WidgetTester tester) async {
      for (var turn = 0; turn < 30; turn++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
    }

    testWidgets('is read into the empty library from the file the user '
        'picks', (tester) async {
      final path = '${folder.path}${Platform.pathSeparator}library.gz';
      File(path).writeAsBytesSync(
        gzip.encode(
          utf8.encode(
            [
              {'format': 'dhara-library-snapshot', 'version': 1},
              {
                'table': 'sources',
                'columns': ['id', 'source_id'],
              },
              [1, 'alpha'],
              {
                'table': 'folders',
                'columns': ['id', 'source', 'parent', 'url', 'path'],
              },
              [1, 1, null, 'http://10.0.0.1/alpha/', ''],
              {
                'table': 'files',
                'columns': ['id', 'folder', 'name', 'url', 'added_at'],
              },
              [1, 1, 'Tenet.2020.mkv', 'Tenet.2020.mkv', 1],
              [2, 1, 'Dune.2021.mkv', 'Dune.2021.mkv', 1],
              [3, 1, 'Elsewhere.mkv', 'http://evil.test/Elsewhere.mkv', 1],
              {'end': true, 'rows': 5},
            ].map((line) => '${jsonEncode(line)}\n').join(),
          ),
        ),
      );
      final snapshots = await show(tester, path);

      await tester.tap(find.byKey(const Key('index-snapshot-read')));
      await settle(tester);

      expect(snapshots.lastRead!.ok, isTrue);
      expect(
        status(tester),
        'Snapshot read: 2 videos and 0 titles are in the library. One row '
        'was left out.',
      );
      expect(find.text('Read snapshot'), findsOneWidget);
    });

    testWidgets('that is no snapshot is said not to be one', (tester) async {
      final path = '${folder.path}${Platform.pathSeparator}other.gz';
      File(path).writeAsStringSync('something else');
      await show(tester, path);

      await tester.tap(find.byKey(const Key('index-snapshot-read')));
      await settle(tester);

      expect(status(tester), 'That file is not a library snapshot.');
    });
  });

  testWidgets('a build without a snapshot writer has no button for one', (
    tester,
  ) async {
    await show(tester);

    expect(find.byKey(const Key('index-snapshot')), findsNothing);
  });
}
