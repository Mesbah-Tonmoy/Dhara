import 'dart:io';
import 'dart:isolate';

import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/features/indexer/index_store.dart';
import 'package:dhara/features/snapshot/snapshot_format.dart';
import 'package:dhara/features/snapshot/snapshot_reader.dart';
import 'package:dhara/features/snapshot/snapshot_writer.dart';
import 'package:dhara/features/sources/source.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/snapshot_library.dart';

/// The first line of a snapshot, as this version writes it.
const _head = {'format': snapshotFormat, 'version': snapshotVersion};

/// The lines of one table: its head, then [rows], each by column.
List<Object?> _table(String name, List<Map<String, Object?>> rows) {
  final columns = snapshotTables.firstWhere((t) => t.name == name).columns;
  return [
    {'table': name, 'columns': columns},
    for (final row in rows) [for (final column in columns) row[column]],
  ];
}

/// A snapshot of the server "alpha" with its base folder, then [more],
/// ended as it should be.
List<Object?> _snapshot(List<Object?> more) {
  final lines = [
    _head,
    ..._table('sources', [
      {'id': 1, 'source_id': 'alpha', 'crawl_finished_at': 5},
    ]),
    ..._table('folders', [
      {'id': 1, 'source': 1, 'url': 'http://10.0.0.1/alpha/', 'path': ''},
    ]),
    ...more,
  ];
  return [
    ...lines,
    {'end': true, 'rows': lines.whereType<List<Object?>>().length},
  ];
}

Map<String, Object?> _file(int id, String url, {int folder = 1}) => {
  'id': id,
  'folder': folder,
  'name': 'Film $id.mkv',
  'url': url,
  'added_at': 1,
};

void main() {
  late Directory folder;
  late LibraryDb library;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('dhara-snapshot-');
    library = LibraryDb.inMemory();
  });

  tearDown(() {
    library.close();
    folder.deleteSync(recursive: true);
  });

  String at(String name) => '${folder.path}${Platform.pathSeparator}$name';

  /// Reads the snapshot made of [lines] into the library.
  Future<SnapshotRead> read(List<Object?> lines, {List<Source>? sources}) {
    writeSnapshotLines(at('snapshot.gz'), lines);
    return readSnapshot(library, (
      at('snapshot.gz'),
      sources ?? snapshotSources,
      null,
    ));
  }

  List<Object?> column(String sql) => [
    for (final row in library.db.select(sql)) row.values.first,
  ];

  /// The addresses of the videos in the library, whole.
  List<Object?> videoUrls() =>
      column('SELECT $fileUrlAloneSql FROM files ORDER BY id');

  void expectEmptyLibrary() {
    for (final table in snapshotTables) {
      expect(
        library.db.select(table.count).single.values.single,
        0,
        reason: table.name,
      );
    }
    expect(column('SELECT count(*) FROM files_fts'), [0]);
    expect(column('SELECT count(*) FROM titles_fts'), [0]);
  }

  group('a snapshot the app wrote', () {
    test('fills an empty library with what the other one held', () async {
      final written = LibraryDb.inMemory();
      addTearDown(written.close);
      fillSnapshotLibrary(written);
      await writeSnapshot(written, (at('snapshot.gz'), null));

      final result = await readSnapshot(library, (
        at('snapshot.gz'),
        snapshotSources,
        null,
      ));

      expect(result.ok, isTrue);
      expect(result.rows, 21);
      expect(result.skipped, 0);
      expect(result.videos, 4);
      expect(result.titles, 2);
      expect(result.madeAt, isNotNull);
      for (final table in snapshotTables) {
        // Every row as the other library has it, depth and all.
        final sql =
            'SELECT * FROM ${table.name} '
            'ORDER BY ${table.columns.take(table.keys).join(', ')}';
        final theirs = written.db.select(sql);
        final ours = library.db.select(sql);
        expect(
          [for (final row in ours) row.values],
          [
            for (final row in theirs)
              [
                for (final (index, value) in row.values.indexed)
                  // What only the other PC should know.
                  theirs.columnNames[index] == 'last_error' ? null : value,
              ],
          ],
          reason: table.name,
        );
      }
      expect(videoUrls(), [
        'http://10.0.0.1/alpha/Films/Vivarium.2019.1080p.mkv',
        'http://beta.test:8080/Vivarium%20(2019)%20720p.mp4',
        'http://beta.test:8080/The.Bay.S01E01.mkv',
        'http://beta.test:8080/The.Bay.S01E02.mkv',
      ]);
      // Search finds them, by file and by title.
      expect(
        IndexStore(
          library,
        ).search('vivarium', sourceIds: ['alpha', 'beta']).map((h) => h.name),
        unorderedEquals([
          'Vivarium.2019.1080p.mkv',
          'Vivarium (2019) 720p.mp4',
        ]),
      );
      expect(
        column("SELECT rowid FROM titles_fts WHERE titles_fts MATCH 'bay'"),
        [2],
      );
      // Nothing of what the other PC watched or listed.
      for (final table in const [
        'playback',
        'watch_history',
        'my_list',
        'metadata_cache',
      ]) {
        expect(column('SELECT count(*) FROM $table'), [0], reason: table);
      }
    });

    test('is read whole however the file is cut into pieces', () async {
      // Names that do not pack well, so the file is several pieces long,
      // and more rows than are written at once.
      final written = LibraryDb.inMemory();
      addTearDown(written.close);
      written.db
        ..execute("INSERT INTO sources (source_id) VALUES ('alpha')")
        ..execute(
          'INSERT INTO folders (source, url, path, depth) '
          "VALUES (1, 'http://10.0.0.1/alpha/', '', 0)",
        )
        ..execute('BEGIN');
      var seed = 7;
      for (var i = 0; i < 20000; i++) {
        final name = StringBuffer();
        for (var letter = 0; letter < 40; letter++) {
          seed = (seed * 1103515245 + 12345) & 0x7fffffff;
          name.writeCharCode(97 + (seed >> 8) % 26);
        }
        written.db.execute(
          'INSERT INTO files (folder, name, url, added_at) '
          'VALUES (1, ?, ?, 0)',
          ['$name.mkv', 'http://10.0.0.1/alpha/$name.mkv'],
        );
      }
      written.db.execute('COMMIT');
      await writeSnapshot(written, (at('snapshot.gz'), null));
      expect(File(at('snapshot.gz')).lengthSync(), greaterThan(3 * 64 * 1024));
      final events = ReceivePort();
      final progress = <Object?>[];
      events.listen(progress.add);

      final result = await readSnapshot(library, (
        at('snapshot.gz'),
        snapshotSources,
        events.sendPort,
      ));
      await pumpEventQueue();
      events.close();

      expect(result.ok, isTrue);
      expect(result.rows, 20002);
      expect(result.skipped, 0);
      expect(
        videoUrls(),
        written.db
            .select('SELECT $fileUrlAloneSql AS url FROM files ORDER BY id')
            .map((row) => row['url']),
      );
      expect(progress.last, (20002, 20002));
    });
  });

  group('only what lies on a server of the source list is taken:', () {
    test(
      'a source the list does not have is left out with all of it',
      () async {
        final written = LibraryDb.inMemory();
        addTearDown(written.close);
        fillSnapshotLibrary(written);
        await writeSnapshot(written, (at('snapshot.gz'), null));

        final result = await readSnapshot(library, (
          at('snapshot.gz'),
          [snapshotSources.first],
          null,
        ));

        expect(result.ok, isTrue);
        expect(column('SELECT source_id FROM sources'), ['alpha']);
        expect(videoUrls(), [
          'http://10.0.0.1/alpha/Films/Vivarium.2019.1080p.mkv',
        ]);
        expect(column('SELECT count(*) FROM file_meta'), [1]);
        // The server, its folder, three videos and what their names say.
        expect(result.skipped, 1 + 1 + 3 + 3);
      },
    );

    test('a source whose address the list has otherwise is not read from '
        'the snapshot', () async {
      final moved = Source(
        id: 'alpha',
        name: 'Alpha',
        type: SourceType.h5ai,
        category: SourceCategory.movies,
        baseUrls: [Uri.parse('http://10.0.0.9/alpha/')],
      );

      final result = await read(
        _snapshot(_table('files', [_file(1, 'a.mkv')])),
        sources: [moved],
      );

      expect(result.ok, isTrue);
      expect(column('SELECT count(*) FROM folders'), [0]);
      expect(videoUrls(), isEmpty);
    });

    test(
      'a folder a crawl starts from must be a base URL of its source',
      () async {
        final result = await read([
          _head,
          ..._table('sources', [
            {'id': 1, 'source_id': 'alpha'},
            {'id': 2, 'source_id': 'beta'},
          ]),
          ..._table('folders', [
            // Of the same server, but not where the source starts.
            {'id': 1, 'source': 1, 'url': 'http://10.0.0.1/other/', 'path': ''},
            // The base URL of another source.
            {'id': 2, 'source': 1, 'url': 'http://beta.test:8080/', 'path': ''},
            // Of no source at all.
            {'id': 3, 'source': 7, 'url': 'http://10.0.0.1/alpha/', 'path': ''},
            {'id': 4, 'source': 2, 'url': 'http://beta.test:8080/', 'path': ''},
          ]),
          {'end': true, 'rows': 6},
        ]);

        expect(result.ok, isTrue);
        expect(column('SELECT id FROM folders'), [4]);
      },
    );

    test('a folder elsewhere, or below one that was left out, is left '
        'out', () async {
      final result = await read(
        _snapshot(
          _table('folders', [
            {
              'id': 2,
              'source': 1,
              'parent': 1,
              'url': 'http://10.0.0.1/alpha/Films/',
              'path': 'Films',
            },
            {
              'id': 3,
              'source': 1,
              'parent': 1,
              'url': 'http://evil.test/alpha/Films/',
              'path': 'Films',
            },
            // Another port is another server.
            {
              'id': 4,
              'source': 1,
              'parent': 1,
              'url': 'http://10.0.0.1:8080/alpha/',
              'path': 'x',
            },
            {
              'id': 5,
              'source': 1,
              'parent': 3,
              'url': 'http://10.0.0.1/alpha/Films/2020/',
              'path': 'Films/2020',
            },
            // Its parent comes after it.
            {
              'id': 6,
              'source': 1,
              'parent': 7,
              'url': 'http://10.0.0.1/alpha/Shows/A/',
              'path': 'Shows/A',
            },
            {
              'id': 7,
              'source': 1,
              'parent': 1,
              'url': 'http://10.0.0.1/alpha/Shows/',
              'path': 'Shows',
            },
          ]),
        ),
      );

      expect(result.ok, isTrue);
      expect(column('SELECT id FROM folders ORDER BY id'), [1, 2, 7]);
      expect(column('SELECT depth FROM folders ORDER BY id'), [0, 1, 1]);
      expect(result.skipped, 4);
    });

    test('a video elsewhere is left out, however its address is '
        'written', () async {
      final result = await read(
        _snapshot([
          ..._table('folders', [
            // A folder's address that does not end where a name begins.
            {
              'id': 2,
              'source': 1,
              'parent': 1,
              'url': 'http://10.0.0.1',
              'path': 'x',
            },
          ]),
          ..._table('files', [
            _file(1, 'Good.mkv'),
            _file(2, 'http://10.0.0.1/elsewhere/on/the/server.mkv'),
            _file(3, 'http://evil.test/alpha/Bad.mkv'),
            _file(4, 'https://10.0.0.1/alpha/Bad.mkv'),
            _file(5, 'ftp://10.0.0.1/alpha/Bad.mkv'),
            _file(6, 'file:///C:/Windows/win.ini'),
            _file(7, 'http://user:pass@10.0.0.1/alpha/Bad.mkv'),
            // What follows the folder's address makes another host of it.
            _file(8, '@evil.test/Bad.mkv', folder: 2),
            _file(9, '.evil.test/Bad.mkv', folder: 2),
            _file(10, ':8080/Bad.mkv', folder: 2),
            // Not written the way an address is.
            _file(11, 'HTTP://10.0.0.1/alpha/Bad.mkv'),
            _file(12, ' http://10.0.0.1/alpha/Bad.mkv'),
            _file(13, 'Bad.mkv#fragment'),
            // Of a folder that is not there.
            _file(14, 'Bad.mkv', folder: 9),
          ]),
          ..._table('subtitles', [
            {
              'id': 1,
              'file': 1,
              'name': 'a.srt',
              'url': 'http://10.0.0.1/a.srt',
            },
            {
              'id': 2,
              'file': 1,
              'name': 'b.srt',
              'url': 'http://evil.test/b.srt',
            },
            {
              'id': 3,
              'file': 3,
              'name': 'c.srt',
              'url': 'http://10.0.0.1/c.srt',
            },
          ]),
        ]),
      );

      expect(result.ok, isTrue);
      expect(videoUrls(), [
        'http://10.0.0.1/alpha/Good.mkv',
        'http://10.0.0.1/elsewhere/on/the/server.mkv',
      ]);
      expect(column('SELECT url FROM subtitles'), ['http://10.0.0.1/a.srt']);
      expect(result.skipped, 12 + 2);
    });
  });

  group('a row that is not as it should be is left out:', () {
    test('values of the wrong kind, size or range', () async {
      Map<String, Object?> title(
        int id, [
        Map<String, Object?> more = const {},
      ]) => {'id': id, 'kind': 0, 'name': 'Film $id', 'added_at': 1, ...more};

      final result = await read(
        _snapshot([
          ..._table('files', [
            _file(1, 'a.mkv'),
            {..._file(2, 'b.mkv'), 'name': 7},
            {..._file(3, 'c.mkv'), 'name': 'x' * 2000},
            {..._file(4, 'd.mkv'), 'name': 'bell\u0007.mkv'},
            {..._file(5, 'e.mkv'), 'id': 'five'},
            {..._file(6, 'f.mkv'), 'id': -6},
            {..._file(7, 'g.mkv'), 'added_at': null},
            // The same number twice: the first stays.
            _file(1, 'h.mkv'),
          ]),
          ..._table('titles', [
            title(1),
            title(2, {'kind': 7}),
            title(3, {'name': ''}),
            title(4, {'match_state': 9}),
            // What only decorates is dropped, and the title kept.
            title(5, {
              'year': 12,
              'rating': 99,
              'votes': 'many',
              'poster_path': '/../../secret.jpg',
              'backdrop_path': 'http://evil.test/a.jpg',
              'overview': 'x' * 9000,
              'tmdb_id': 0,
            }),
            title(6, {'tmdb_id': 9, 'poster_path': '/abc_DEF-1.jpg'}),
            // The same film of TMDB twice: the first stays.
            title(7, {'tmdb_id': 9}),
          ]),
          ..._table('title_keys', [
            {'key': 'm|film 1', 'title': 1, 'name': 'Film 1'},
            {'key': 'm|gone', 'title': 2, 'name': 'Gone'},
            {'key': 'm|film 1', 'title': 5, 'name': 'Twice'},
          ]),
          ..._table('seasons', [
            {'title': 1, 'season': 1, 'air_date': '2020-01-02'},
            {'title': 1, 'season': 2, 'air_date': 'soon', 'poster_path': 'x'},
            {'title': 1, 'season': -1},
            {'title': 99, 'season': 1},
          ]),
          ..._table('episodes', [
            {'title': 1, 'season': 1, 'episode': 1, 'still_path': '/s.png'},
            {'title': 1, 'season': 1, 'episode': 'two'},
            {'title': 99, 'season': 1, 'episode': 1},
          ]),
          ..._table('file_meta', [
            {'file': 1, 'parser': 7, 'kind': 0, 'title': 1, 'height': 1080},
            {'file': 2, 'parser': 7, 'kind': 0, 'title': 1},
            {'file': 1, 'parser': 7, 'kind': 0, 'title': 1},
          ]),
        ]),
      );

      expect(result.ok, isTrue);
      expect(column('SELECT name FROM files'), ['Film 1.mkv']);
      expect(column('SELECT id FROM titles ORDER BY id'), [1, 4, 5, 6]);
      // A state that is none: not looked up yet.
      expect(column('SELECT match_state FROM titles WHERE id = 4'), [0]);
      expect(
        library.db.select('SELECT * FROM titles WHERE id = 5').single,
        allOf(
          containsPair('year', null),
          containsPair('rating', null),
          containsPair('votes', null),
          containsPair('poster_path', null),
          containsPair('backdrop_path', null),
          containsPair('overview', null),
          containsPair('tmdb_id', null),
        ),
      );
      expect(column('SELECT poster_path FROM titles WHERE id = 6'), [
        '/abc_DEF-1.jpg',
      ]);
      expect(column('SELECT name FROM title_keys'), ['Film 1']);
      expect(column('SELECT season FROM seasons ORDER BY season'), [1, 2]);
      expect(column('SELECT air_date FROM seasons ORDER BY season'), [
        '2020-01-02',
        null,
      ]);
      expect(column('SELECT poster_path FROM seasons WHERE season = 2'), [
        null,
      ]);
      expect(column('SELECT still_path FROM episodes'), ['/s.png']);
      expect(column('SELECT height FROM file_meta'), [1080]);
      expect(result.rows, 2 + 1 + 4 + 1 + 2 + 1 + 1);
      expect(result.skipped, 7 + 3 + 2 + 2 + 2 + 2);
    });

    test('one with more or fewer values than its table has columns', () async {
      final result = await read([
        _head,
        {
          'table': 'sources',
          'columns': ['id', 'source_id'],
        },
        [1, 'alpha'],
        [2],
        [2, 'beta', 'more'],
        {'end': true, 'rows': 3},
      ]);

      expect(result.ok, isTrue);
      expect(column('SELECT source_id FROM sources'), ['alpha']);
      expect(result.skipped, 2);
    });

    test('a table or a column this version does not know is passed over, '
        'and a column it can do without may be missing', () async {
      final result = await read([
        _head,
        {
          'table': 'sources',
          'columns': ['new_column', 'source_id', 'id'],
        },
        ['x', 'alpha', 1],
        {
          'table': 'a_new_table',
          'columns': ['id'],
        },
        [1],
        [2],
        // Without the column it cannot do without: every row passed over.
        {
          'table': 'folders',
          'columns': ['id', 'source', 'parent', 'path'],
        },
        [1, 1, null, ''],
        {'end': true, 'rows': 4},
      ]);

      expect(result.ok, isTrue);
      expect(column('SELECT source_id FROM sources'), ['alpha']);
      expect(column('SELECT crawl_finished_at FROM sources'), [null]);
      expect(column('SELECT count(*) FROM folders'), [0]);
      expect(result.rows, 1);
      expect(result.skipped, 3);
    });
  });

  group('a file that does not hold together is refused as a whole:', () {
    final rows = _table('files', [_file(1, 'a.mkv')]);

    Future<void> expectRefused(
      List<Object?> lines,
      SnapshotProblem problem,
    ) async {
      final result = await read(lines);
      expect(result.problem, problem);
      expect(result.ok, isFalse);
      expectEmptyLibrary();
    }

    test('what is not gzip', () async {
      File(at('snapshot.gz')).writeAsStringSync('not gzip at all');

      final result = await readSnapshot(library, (
        at('snapshot.gz'),
        snapshotSources,
        null,
      ));

      expect(result.problem, SnapshotProblem.notASnapshot);
      expectEmptyLibrary();
    });

    test('what is no file', () async {
      final result = await readSnapshot(library, (
        at('missing.gz'),
        snapshotSources,
        null,
      ));

      expect(result.problem, SnapshotProblem.unreadable);
    });

    test('an empty file, text, another format', () async {
      await expectRefused([], SnapshotProblem.cutShort);
      await expectRefused(['hello'], SnapshotProblem.notASnapshot);
      await expectRefused([
        {'format': 'something-else', 'version': 1},
      ], SnapshotProblem.notASnapshot);
      await expectRefused([
        {'format': snapshotFormat},
      ], SnapshotProblem.notASnapshot);
    });

    test('one a later version wrote in its own way', () async {
      await expectRefused([
        {'format': snapshotFormat, 'version': snapshotVersion + 1},
        {'end': true, 'rows': 0},
      ], SnapshotProblem.newerVersion);
    });

    test('one without its last line, or with another number of rows than '
        'that line says', () async {
      final whole = _snapshot(rows);
      await expectRefused(
        whole.sublist(0, whole.length - 1),
        SnapshotProblem.cutShort,
      );
      await expectRefused([
        ...whole.sublist(0, whole.length - 1),
        {'end': true, 'rows': 99},
      ], SnapshotProblem.cutShort);
    });

    test('one that breaks off in the middle', () async {
      final written = LibraryDb.inMemory();
      addTearDown(written.close);
      fillSnapshotLibrary(written);
      await writeSnapshot(written, (at('whole.gz'), null));
      final bytes = File(at('whole.gz')).readAsBytesSync();
      File(
        at('snapshot.gz'),
      ).writeAsBytesSync(bytes.sublist(0, bytes.length * 2 ~/ 3));

      final result = await readSnapshot(library, (
        at('snapshot.gz'),
        snapshotSources,
        null,
      ));

      expect(result.problem, SnapshotProblem.cutShort);
      expectEmptyLibrary();
    });

    test('one with something after its end, a row before any table, or a '
        'line that is neither', () async {
      await expectRefused([
        ..._snapshot(rows),
        ...rows,
      ], SnapshotProblem.notASnapshot);
      await expectRefused([
        _head,
        [1, 'alpha'],
        {'end': true, 'rows': 1},
      ], SnapshotProblem.notASnapshot);
      await expectRefused([
        ..._snapshot(rows).take(5),
        7,
      ], SnapshotProblem.notASnapshot);
      await expectRefused([
        ..._snapshot(rows).take(5),
        '{"table": "files", "columns": [1]}',
      ], SnapshotProblem.notASnapshot);
      await expectRefused([
        ..._snapshot(rows).take(5),
        '[1, 2',
      ], SnapshotProblem.notASnapshot);
    });

    test('one with a line longer than any line of a snapshot', () async {
      await expectRefused(
        _snapshot(
          _table('files', [
            _file(1, 'a.mkv'),
            {..._file(2, 'b.mkv'), 'name': 'x' * 70000},
          ]),
        ),
        SnapshotProblem.notASnapshot,
      );
    });
  });

  test('a library that holds something already is left as it is', () async {
    fillSnapshotLibrary(library);

    final result = await read(_snapshot(const []));

    expect(result.problem, SnapshotProblem.libraryNotEmpty);
    expect(column('SELECT count(*) FROM files'), [4]);
    expect(column('SELECT count(*) FROM titles'), [2]);
  });

  test('what a snapshot put in can be taken out again', () async {
    expect(removeSnapshotRows(library, null), isFalse);
    await read(
      _snapshot([
        ..._table('files', [_file(1, 'a.mkv')]),
        ..._table('titles', [
          {'id': 1, 'kind': 0, 'name': 'Film', 'added_at': 1},
        ]),
      ]),
    );
    expect(column('SELECT count(*) FROM files'), [1]);

    expect(removeSnapshotRows(library, null), isTrue);

    expectEmptyLibrary();
  });
}
