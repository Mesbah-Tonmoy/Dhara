import 'dart:io';

import 'package:dhara/core/db/library_db.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late LibraryDb library;
  late Database db;

  setUp(() {
    library = LibraryDb.inMemory();
    db = library.db;
  });

  tearDown(() => library.close());

  /// Adds a source with one base folder and returns the folder's id.
  int addFolder({String path = '', String url = 'http://a.test/'}) {
    db.execute(
      'INSERT OR IGNORE INTO sources (id, source_id) VALUES (1, ?)',
      ['a'],
    );
    db.execute(
      'INSERT INTO folders (source, url, path, depth) VALUES (1, ?, ?, 0)',
      [url, path],
    );
    return db.lastInsertRowId;
  }

  int addFile(int folder, String name) {
    db.execute(
      'INSERT INTO files (folder, name, url, added_at) VALUES (?, ?, ?, 0)',
      [folder, name, 'http://a.test/$name'],
    );
    return db.lastInsertRowId;
  }

  List<int> search(String query) => [
        for (final row in db.select(
          'SELECT rowid FROM files_fts WHERE files_fts MATCH ? ORDER BY rowid',
          [query],
        ))
          row['rowid'] as int,
      ];

  int count(String table) =>
      db.select('SELECT count(*) AS n FROM $table').first['n'] as int;

  group('bundled SQLite', () {
    test('has FTS5 and is new enough for the search index', () {
      final options = [
        for (final row in db.select('PRAGMA compile_options'))
          row.values.first,
      ];
      expect(options, contains('ENABLE_FTS5'));
      // `contentless_delete` needs SQLite 3.43.
      expect(sqlite3.version.versionNumber, greaterThanOrEqualTo(3043000));
    });
  });

  group('schema', () {
    test('a new database is at the current version with every table', () {
      expect(db.userVersion, LibraryDb.schemaVersion);
      final tables = [
        for (final row in db.select(
          "SELECT name FROM sqlite_schema WHERE type = 'table' "
          "AND name NOT LIKE 'files_fts_%' ORDER BY name",
        ))
          row['name'],
      ];
      expect(
        tables,
        ['files', 'files_fts', 'folders', 'playback', 'sources', 'subtitles'],
      );
    });

    test('a file must belong to a known folder', () {
      expect(() => addFile(99, 'a.mkv'), throwsA(isA<SqliteException>()));
    });

    test('columns only take their own type', () {
      final folder = addFolder();
      expect(
        () => db.execute(
          'INSERT INTO files (folder, name, url, size, added_at) '
          'VALUES (?, ?, ?, ?, 0)',
          [folder, 'a.mkv', 'http://a.test/a.mkv', 'big'],
        ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('removing a source removes everything found on it', () {
      final folder = addFolder();
      db.execute(
        'INSERT INTO folders (source, parent, url, path, depth) '
        'VALUES (1, ?, ?, ?, 1)',
        [folder, 'http://a.test/Tenet/', 'Tenet'],
      );
      final file = addFile(db.lastInsertRowId, 'Tenet.2020.mkv');
      db.execute(
        'INSERT INTO subtitles (file, name, url) VALUES (?, ?, ?)',
        [file, 'Tenet.2020.srt', 'http://a.test/Tenet/Tenet.2020.srt'],
      );
      expect(search('tenet'), [file]);

      db.execute('DELETE FROM sources WHERE id = 1');

      expect(count('folders'), 0);
      expect(count('files'), 0);
      expect(count('subtitles'), 0);
      expect(search('tenet'), isEmpty);
    });
  });

  group('search index', () {
    test('finds a file by words of its name, whatever separates them', () {
      final folder = addFolder();
      final dots = addFile(folder, 'The.Dark.Knight.2008.1080p.BluRay.mkv');
      final underscores = addFile(folder, 'the_dark_knight_rises_(2012).mp4');
      addFile(folder, 'Inception.2010.mkv');

      expect(search('dark knight'), [dots, underscores]);
      expect(search('KNIGHT 2008'), [dots]);
      expect(search('interstellar'), isEmpty);
    });

    test('finds a file by the folders it is in', () {
      final folder = addFolder(
        path: 'TV Series/Breaking Bad/Season 1',
        url: 'http://a.test/s/',
      );
      final episode = addFile(folder, 'S01E02.mkv');

      expect(search('breaking bad'), [episode]);
      expect(search('breaking s01e02'), [episode]);
      expect(search('name : breaking'), isEmpty);
    });

    test('finds a file by the start of a word', () {
      final folder = addFolder();
      final file = addFile(folder, 'Interstellar.2014.mkv');

      expect(search('in*'), [file]);
      expect(search('inter*'), [file]);
      expect(search('stellar*'), isEmpty);
    });

    test('ignores accents', () {
      final folder = addFolder();
      final file = addFile(folder, 'Amélie.2001.mkv');

      expect(search('amelie'), [file]);
    });

    test('forgets a file when it is removed', () {
      final folder = addFolder();
      final gone = addFile(folder, 'Tenet.2020.mkv');
      final kept = addFile(folder, 'Tenet.2020.2160p.mkv');

      db.execute('DELETE FROM files WHERE id = ?', [gone]);

      expect(search('tenet'), [kept]);
    });

    test('forgets the files of a removed folder', () {
      final folder = addFolder();
      addFile(folder, 'Tenet.2020.mkv');

      db.execute('DELETE FROM folders WHERE id = ?', [folder]);

      expect(count('files'), 0);
      expect(search('tenet'), isEmpty);
    });
  });

  group('transaction', () {
    test('keeps every change and returns the result', () {
      final id = library.transaction(() {
        final folder = addFolder();
        return addFile(folder, 'a.mkv');
      });

      expect(id, 1);
      expect(count('files'), 1);
    });

    test('keeps nothing if the body throws', () {
      expect(
        () => library.transaction(() {
          addFolder();
          throw StateError('stop');
        }),
        throwsStateError,
      );

      expect(count('folders'), 0);
      expect(db.autocommit, isTrue);
    });
  });

  group('a database file', () {
    late Directory folder;
    late String path;

    setUp(() {
      folder = Directory.systemTemp.createTempSync('dhara_db_test');
      path = '${folder.path}${Platform.pathSeparator}library.db';
    });

    tearDown(() => folder.deleteSync(recursive: true));

    test('keeps its content between runs', () {
      final first = LibraryDb.open(path);
      first.db.execute(
        'INSERT INTO playback (url, position_ms, duration_ms, updated_at) '
        'VALUES (?, 1000, 5000, 0)',
        ['http://a.test/a.mkv'],
      );
      first.close();

      final second = LibraryDb.open(path);
      addTearDown(second.close);

      expect(second.db.userVersion, LibraryDb.schemaVersion);
      expect(
        second.db.select('SELECT position_ms FROM playback').single.values,
        [1000],
      );
      expect(
        second.db.select('PRAGMA journal_mode').single.values,
        ['wal'],
      );
      expect(second.db.select('PRAGMA foreign_keys').single.values, [1]);
    });

    test('made by a newer app is refused and left alone', () {
      final newer = sqlite3.open(path)
        ..execute('CREATE TABLE future (x)')
        ..userVersion = LibraryDb.schemaVersion + 1;
      newer.close();

      expect(
        () => LibraryDb.open(path),
        throwsA(
          isA<LibraryDbException>().having(
            (e) => e.problem,
            'problem',
            LibraryDbProblem.newerVersion,
          ),
        ),
      );

      final check = sqlite3.open(path);
      addTearDown(check.close);
      expect(check.userVersion, LibraryDb.schemaVersion + 1);
      expect(check.select('SELECT name FROM sqlite_schema').single.values, [
        'future',
      ]);
    });

    test('that is not a database is reported as damaged', () {
      File(path).writeAsStringSync('not a database, just some text ' * 200);

      expect(
        () => LibraryDb.open(path),
        throwsA(
          isA<LibraryDbException>().having(
            (e) => e.problem,
            'problem',
            LibraryDbProblem.damaged,
          ),
        ),
      );
      // Closed again, so the caller can set the file aside.
      File(path).renameSync('$path.bad');
    });
  });
}
