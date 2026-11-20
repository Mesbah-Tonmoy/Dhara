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

  group('the short number of an address', () {
    test('is the same for the same address, in Dart and in SQL, and never '
        'changes', () {
      const url = 'http://10.0.0.1/Films/Tenet%20(2020)/Tenet.2020.mkv';
      // Written down once: the index of every library is made with it.
      expect(urlKey(url), 8140996203917);
      expect(urlKey(''), 0x9ce484222325);
      expect(db.select('SELECT dhara_url_key(?)', [url]).single.values, [
        urlKey(url),
      ]);
      expect(urlKey('${url}x'), isNot(urlKey(url)));
      expect(urlKey('http://a.test/ফিল্ম.mkv'), lessThan(1 << 48));
      expect(db.select('SELECT dhara_url_key(NULL)').single.values, [null]);
    });

    test('is noted for every video as it is put in', () {
      final file = addFile(addFolder(), 'Heat.1995.mkv');

      expect(
        db
            .select(
              'SELECT id FROM files INDEXED BY files_url_key '
              'WHERE url_key = ?',
              [urlKey('http://a.test/Heat.1995.mkv')],
            )
            .single
            .values,
        [file],
      );
    });
  });

  group('the address of a video', () {
    List<Object?> stored(int id) => db
        .select(
          'SELECT url, $fileUrlAloneSql, url_key FROM files WHERE id = ?',
          [id],
        )
        .single
        .values;
    int add(int folder, String url) {
      db.execute(
        "INSERT INTO files (folder, name, url, added_at) VALUES (?, 'n', ?, 0)",
        [folder, url],
      );
      return db.lastInsertRowId;
    }

    test('is kept as what follows the address of its folder', () {
      final folder = addFolder(url: 'http://a.test/Films/Heat%20(1995)/');
      const url = 'http://a.test/Films/Heat%20(1995)/Heat.1995.1080p.mkv';

      expect(stored(add(folder, url)), ['Heat.1995.1080p.mkv', url, urlKey(url)]);
    });

    test('is kept whole where it does not follow from the folder', () {
      final folder = addFolder(url: 'http://a.test/emby/folder/12/');
      for (final url in [
        // Another place altogether, as on an Emby server.
        'http://a.test/emby/Videos/77/stream.mkv?static=true',
        // Under the folder, but what follows would pass for a whole address.
        'http://a.test/emby/folder/12/get?from=http://b.test/x.mkv',
        // The folder's own address.
        'http://a.test/emby/folder/12/',
      ]) {
        expect(stored(add(folder, url)), [url, url, urlKey(url)], reason: url);
      }
    });

    test('is one of many: a query puts it together with the folder', () {
      final folder = addFolder(url: 'http://a.test/s/');
      final file = add(folder, 'http://a.test/s/E01.mkv');

      expect(
        db
            .select(
              "SELECT ${fileUrlSql('f', 'd')} FROM files f "
              'JOIN folders d ON d.id = f.folder WHERE f.id = ?',
              [file],
            )
            .single
            .values,
        ['http://a.test/s/E01.mkv'],
      );
    });
  });

  test('an answer is packed and unpacked without loss', () {
    const text = '[{"id":1,"title":"ফিল্ম"},{"id":2,"title":"Amélie"}]';

    expect(unpackAnswer(packAnswer(text)), text);
    expect(
      db.select('SELECT dhara_unpack(dhara_pack(?))', [text]).single.values,
      [text],
    );
    expect(
      packAnswer(List.filled(40, text).join()).length,
      lessThan(text.length * 4),
    );
  });

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
          "AND name NOT LIKE 'files_fts_%' "
          "AND name NOT LIKE 'titles_fts_%' ORDER BY name",
        ))
          row['name'],
      ];
      expect(tables, [
        'episodes',
        'file_meta',
        'files',
        'files_fts',
        'folders',
        'metadata_cache',
        'my_list',
        'playback',
        'seasons',
        'sources',
        'subtitles',
        'title_keys',
        'titles',
        'titles_fts',
        'watch_history',
      ]);
    });

    test('a title is anime if AniList knows it or it is animation from '
        'Japan', () {
      void add(int id, {String? genres, String? language, int? anilist}) =>
          db.execute(
            'INSERT INTO titles (id, kind, name, genres, language, '
            "anilist_id, added_at) VALUES (?, 1, 'T', ?, ?, ?, 0)",
            [id, genres, language, anilist],
          );
      add(1, genres: 'Animation, Drama', language: 'ja');
      add(2, genres: 'Animation, Family', language: 'en');
      add(3, genres: 'Drama', language: 'ja');
      add(4, anilist: 21);
      add(5);

      expect(
        [
          for (final row in db.select(
            'SELECT id FROM titles WHERE is_anime = 1 ORDER BY id',
          ))
            row['id'],
        ],
        [1, 4],
      );
      expect(
        db.select('SELECT count(*) FROM titles WHERE is_anime = 0').single
            .values,
        [3],
        reason: 'never unknown',
      );

      // It follows what is known about the title.
      db.execute("UPDATE titles SET language = 'ja' WHERE id = 2");
      expect(
        db.select('SELECT is_anime FROM titles WHERE id = 2').single.values,
        [1],
      );
    });

    test('a title is on My List once, and leaves it when it is removed', () {
      db.execute(
        "INSERT INTO titles (id, kind, name, added_at) VALUES (1, 0, 'A', 0)",
      );
      db.execute('INSERT INTO my_list (title, added_at) VALUES (1, 5)');

      expect(
        () => db.execute('INSERT INTO my_list (title, added_at) VALUES (1, 6)'),
        throwsA(isA<SqliteException>()),
      );
      expect(
        () => db.execute('INSERT INTO my_list (title, added_at) VALUES (9, 6)'),
        throwsA(isA<SqliteException>()),
        reason: 'no such title',
      );

      db.execute('DELETE FROM titles WHERE id = 1');
      expect(count('my_list'), 0);
    });

    test('the newest videos are found through an index', () {
      final plan = db.select(
        'EXPLAIN QUERY PLAN SELECT id FROM files INDEXED BY files_recent '
        'ORDER BY min(ifnull(modified, added_at), added_at) DESC LIMIT 5',
      );
      expect('${plan.first['detail']}', contains('files_recent'));
      expect(
        [for (final row in plan) '${row['detail']}'],
        isNot(contains(contains('TEMP B-TREE'))),
        reason: 'no sorting',
      );
    });

    test('a video dated after the app first saw it counts from then', () {
      final folder = addFolder();
      void add(String name, {int? modified, required int addedAt}) =>
          db.execute(
            'INSERT INTO files (folder, name, url, modified, added_at) '
            'VALUES (?, ?, ?, ?, ?)',
            [folder, name, 'http://a.test/$name', modified, addedAt],
          );
      add('old.mkv', modified: 100, addedAt: 500);
      add('undated.mkv', addedAt: 300);
      add('from-the-future.mkv', modified: 9000, addedAt: 400);

      expect(
        [
          for (final row in db.select(
            'SELECT name FROM files '
            'ORDER BY min(ifnull(modified, added_at), added_at) DESC',
          ))
            row['name'],
        ],
        ['from-the-future.mkv', 'undated.mkv', 'old.mkv'],
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
    });

    test('keeps which words a name has, not their order', () {
      final folder = addFolder();
      final file = addFile(folder, 'The.Dark.Knight.2008.mkv');

      expect(search('knight dark'), [file]);
      // Words in a row, or in one column only, it cannot be asked for.
      expect(() => search('"dark knight"'), throwsA(isA<SqliteException>()));
      expect(() => search('name : dark'), throwsA(isA<SqliteException>()));
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
      // Room in memory for more of the file than SQLite takes by default.
      expect(second.db.select('PRAGMA cache_size').single.values, [
        -LibraryDb.pageCacheKb,
      ]);
    });

    test('made by version 1 is upgraded and keeps what it held', () {
      final old = LibraryDb.openAt(path, 1);
      old.db
        ..execute("INSERT INTO sources (id, source_id) VALUES (1, 'a')")
        ..execute(
          'INSERT INTO folders (id, source, url, path, depth, state) '
          "VALUES (1, 1, 'http://a.test/', 'Movies', 0, 1)",
        )
        ..execute(
          'INSERT INTO files (id, folder, name, url, size, added_at) '
          "VALUES (7, 1, 'Tenet.2020.mkv', 'http://a.test/Tenet.2020.mkv', "
          '5, 9)',
        )
        ..execute(
          'INSERT INTO subtitles (file, name, url) '
          "VALUES (7, 'Tenet.2020.srt', 'http://a.test/Tenet.2020.srt')",
        )
        ..execute(
          'INSERT INTO playback (url, position_ms, duration_ms, updated_at) '
          "VALUES ('http://a.test/Tenet.2020.mkv', 1000, 5000, 0)",
        );
      expect(old.db.userVersion, 1);
      expect(
        old.db.select(
          "SELECT 1 FROM sqlite_schema WHERE name = 'titles'",
        ),
        isEmpty,
      );
      old.close();

      final upgraded = LibraryDb.open(path);
      addTearDown(upgraded.close);
      final db = upgraded.db;

      expect(db.userVersion, LibraryDb.schemaVersion);
      expect(
        db.select('SELECT id, name, size, added_at FROM files').single.values,
        [7, 'Tenet.2020.mkv', 5, 9],
      );
      expect(db.select('SELECT name FROM subtitles').single.values, [
        'Tenet.2020.srt',
      ]);
      expect(db.select('SELECT position_ms FROM playback').single.values, [
        1000,
      ]);
      expect(
        db.select('SELECT state FROM folders').single.values,
        [1],
        reason: 'the crawl does not start over',
      );
      expect(
        db.select(
          "SELECT rowid FROM files_fts WHERE files_fts MATCH 'tenet'",
        ).single.values,
        [7],
      );
      for (final table in ['titles', 'title_keys', 'file_meta', 'episodes']) {
        expect(
          db.select('SELECT count(*) FROM $table').single.values,
          [0],
          reason: table,
        );
      }
    });

    test('made by version 2 is upgraded and keeps what it held', () {
      final old = LibraryDb.openAt(path, 2);
      old.db
        ..execute("INSERT INTO sources (id, source_id) VALUES (1, 'a')")
        ..execute(
          'INSERT INTO folders (id, source, url, path, depth, state) '
          "VALUES (1, 1, 'http://a.test/', 'Movies', 0, 1)",
        )
        ..execute(
          'INSERT INTO files (id, folder, name, url, modified, added_at) '
          "VALUES (7, 1, 'Tenet.2020.mkv', 'http://a.test/Tenet.2020.mkv', "
          '5, 9)',
        )
        ..execute(
          'INSERT INTO titles (id, kind, name, year, tmdb_id, match_state, '
          'rating, votes, genres, language, added_at) '
          "VALUES (3, 0, 'Tenet', 2020, 577922, 1, 7.2, 9000, "
          "'Action, Science Fiction', 'en', 9)",
        )
        ..execute(
          'INSERT INTO titles (id, kind, name, genres, language, added_at) '
          "VALUES (4, 1, 'Mushishi', 'Animation, Mystery', 'ja', 9)",
        )
        ..execute(
          'INSERT INTO file_meta (file, parser, kind, title, height) '
          'VALUES (7, 1, 0, 3, 1080)',
        )
        ..execute(
          'INSERT INTO playback (url, position_ms, duration_ms, updated_at) '
          "VALUES ('http://a.test/Tenet.2020.mkv', 1000, 5000, 77)",
        );
      expect(old.db.userVersion, 2);
      expect(
        old.db.select("SELECT 1 FROM sqlite_schema WHERE name = 'my_list'"),
        isEmpty,
      );
      old.close();

      final upgraded = LibraryDb.open(path);
      addTearDown(upgraded.close);
      final db = upgraded.db;

      expect(db.userVersion, LibraryDb.schemaVersion);
      expect(
        db
            .select(
              'SELECT name, year, tmdb_id, rating, votes, genres, runtime, '
              'set_aside, is_anime FROM titles WHERE id = 3',
            )
            .single
            .values,
        ['Tenet', 2020, 577922, 7.2, 9000, 'Action, Science Fiction', null, 0, 0],
      );
      expect(
        db.select('SELECT is_anime FROM titles WHERE id = 4').single.values,
        [1],
      );
      expect(db.select('SELECT title, height FROM file_meta').single.values, [
        3,
        1080,
      ]);
      expect(db.select('SELECT position_ms FROM playback').single.values, [
        1000,
      ]);
      expect(
        db.select('SELECT * FROM watch_history').single.values,
        ['http://a.test/Tenet.2020.mkv', 77, 1000, 5000, 0],
        reason: 'what was left unfinished starts the history',
      );
      expect(db.select('SELECT count(*) FROM my_list').single.values, [0]);
      expect(
        db.select("SELECT rowid FROM titles_fts WHERE titles_fts MATCH 'tenet'")
            .single
            .values,
        [3],
      );
      // The new indexes hold what was there before.
      expect(
        db
            .select(
              'SELECT id FROM files INDEXED BY files_url_key '
              'WHERE url_key = dhara_url_key(?1) AND $fileUrlAloneSql = ?1',
              ['http://a.test/Tenet.2020.mkv'],
            )
            .single
            .values,
        [7],
      );
      expect(
        db
            .select(
              'SELECT id FROM titles INDEXED BY titles_newest '
              'WHERE kind = 0 ORDER BY year DESC, votes DESC',
            )
            .single
            .values,
        [3],
      );
    });

    test('made by version 4 is upgraded: smaller, and with what it held', () {
      final old = LibraryDb.openAt(path, 4);
      old.db
        ..execute("INSERT INTO sources (id, source_id) VALUES (1, 'a')")
        ..execute(
          'INSERT INTO folders (id, source, url, path, depth) '
          "VALUES (1, 1, 'http://a.test/', 'Films/Nolan', 0)",
        )
        ..execute(
          'INSERT INTO metadata_cache (provider, key, body, fetched_at) '
          "VALUES ('tmdb', 'search|movie|tenet|2020', '[{\"id\":577922}]', 7)",
        )
        ..execute(
          'INSERT INTO watch_history (url, watched_at, position_ms, '
          "duration_ms) VALUES ('http://a.test/Tenet.2020.mkv', 7, 1, 5)",
        );
      final insert = old.db.prepare(
        'INSERT INTO files (id, folder, name, url, added_at) '
        'VALUES (?1, 1, ?2, ?3, 0)',
      );
      for (var id = 1; id <= 3000; id++) {
        final name = id == 7 ? 'Tenet.2020.mkv' : 'Film.Number.$id.mkv';
        insert.execute([id, name, 'http://a.test/$name']);
      }
      insert.close();
      // What a removed source leaves behind: free pages in the file.
      old.db.execute('DELETE FROM files WHERE id > 1500');
      expect(old.db.userVersion, 4);
      old.close();
      final sizeBefore = File(path).lengthSync();

      final upgraded = LibraryDb.open(path);
      addTearDown(upgraded.close);
      final db = upgraded.db;

      expect(db.userVersion, LibraryDb.schemaVersion);
      expect(File(path).lengthSync(), lessThan(sizeBefore));
      expect(db.select('PRAGMA freelist_count').single.values, [0]);
      expect(db.select('PRAGMA auto_vacuum').single.values, [2]);
      expect(db.select('SELECT count(*) FROM files').single.values, [1500]);
      // A video is found by its address through the short number.
      expect(
        db
            .select(
              'SELECT f.id FROM watch_history h JOIN files f '
              'INDEXED BY files_url_key ON f.url_key = dhara_url_key(h.url) '
              'JOIN folders d ON d.id = f.folder '
              "WHERE ${fileUrlSql('f', 'd')} = h.url",
            )
            .single
            .values,
        [7],
      );
      expect(
        db.select(
          "SELECT name FROM sqlite_schema WHERE name = 'files_url'",
        ),
        isEmpty,
      );
      // The search index was made anew from the names and folders.
      List<Object?> found(String words) => [
        for (final row in db.select(
          'SELECT rowid FROM files_fts WHERE files_fts MATCH ?',
          [words],
        ))
          row['rowid'],
      ];
      expect(found('tenet'), [7]);
      // Addresses are kept short, and read whole.
      expect(
        db.select('SELECT url, $fileUrlAloneSql FROM files WHERE id = 7')
            .single
            .values,
        ['Tenet.2020.mkv', 'http://a.test/Tenet.2020.mkv'],
      );
      expect(found('nolan number 1500'), [1500]);
      expect(found('number 1501'), isEmpty);
      // The kept answers are packed, and read as they were.
      expect(
        db
            .select(
              'SELECT provider, key, typeof(body), dhara_unpack(body), '
              'fetched_at FROM metadata_cache',
            )
            .single
            .values,
        ['tmdb', 'search|movie|tenet|2020', 'blob', '[{"id":577922}]', 7],
      );

      // Later, free pages go back to the disk when asked.
      db.execute('DELETE FROM files WHERE id > 100');
      expect(
        db.select('PRAGMA freelist_count').single.values.single,
        greaterThan(0),
      );
      upgraded.releaseFreeSpace();
      expect(db.select('PRAGMA freelist_count').single.values, [0]);
    });

    test('made by version 5 is upgraded: its addresses are cut short and '
        'still found', () {
      final old = LibraryDb.openAt(path, 5);
      old.db
        ..execute("INSERT INTO sources (id, source_id) VALUES (1, 'a')")
        ..execute(
          'INSERT INTO folders (id, source, url, path, depth) VALUES '
          "(1, 1, 'http://a.test/Films/', 'Films', 0), "
          "(2, 1, 'http://a.test/emby/9/', 'Emby', 0)",
        )
        ..execute(
          'INSERT INTO files (id, folder, name, url, added_at) VALUES '
          "(7, 1, 'Tenet.2020.mkv', 'http://a.test/Films/Tenet.2020.mkv', 0), "
          "(8, 2, 'Heat', 'http://a.test/emby/Videos/8/stream.mkv', 0)",
        );
      // As version 5 had it: a number computed from the row.
      expect(
        old.db.select('SELECT url_key FROM files WHERE id = 7').single.values,
        [urlKey('http://a.test/Films/Tenet.2020.mkv')],
      );
      old.close();

      final upgraded = LibraryDb.open(path);
      addTearDown(upgraded.close);
      final db = upgraded.db;

      expect(db.userVersion, LibraryDb.schemaVersion);
      expect(
        db.select('SELECT id, url, url_key FROM files ORDER BY id').map(
          (row) => row.values,
        ),
        [
          [7, 'Tenet.2020.mkv', urlKey('http://a.test/Films/Tenet.2020.mkv')],
          [
            8,
            'http://a.test/emby/Videos/8/stream.mkv',
            urlKey('http://a.test/emby/Videos/8/stream.mkv'),
          ],
        ],
      );
      for (final (id, url) in [
        (7, 'http://a.test/Films/Tenet.2020.mkv'),
        (8, 'http://a.test/emby/Videos/8/stream.mkv'),
      ]) {
        expect(
          db
              .select(
                'SELECT id FROM files INDEXED BY files_url_key '
                'WHERE url_key = dhara_url_key(?1) AND $fileUrlAloneSql = ?1',
                [url],
              )
              .single
              .values,
          [id],
        );
      }
      // And a video put in afterwards is treated the same.
      db.execute(
        'INSERT INTO files (id, folder, name, url, added_at) VALUES '
        "(9, 1, 'Dune.mkv', 'http://a.test/Films/Dune.mkv', 0)",
      );
      expect(db.select('SELECT url FROM files WHERE id = 9').single.values, [
        'Dune.mkv',
      ]);
    });

    test('a new file can give free space back from the start', () {
      final fresh = LibraryDb.open(path);
      addTearDown(fresh.close);

      expect(fresh.db.select('PRAGMA auto_vacuum').single.values, [2]);
    });

    test('made by version 3 is upgraded and keeps what it held', () {
      final old = LibraryDb.openAt(path, 3);
      old.db
        ..execute(
          'INSERT INTO titles (id, kind, name, year, tmdb_id, match_state, '
          'genres, runtime, added_at) '
          "VALUES (3, 0, 'Tenet', 2020, 577922, 1, 'Action', 150, 9)",
        )
        ..execute('INSERT INTO my_list (title, added_at) VALUES (3, 5)')
        ..execute(
          'INSERT INTO watch_history (url, watched_at, position_ms, '
          "duration_ms) VALUES ('http://a.test/t.mkv', 7, 1000, 5000)",
        );
      expect(old.db.userVersion, 3);
      old.close();

      final upgraded = LibraryDb.open(path);
      addTearDown(upgraded.close);
      final db = upgraded.db;

      expect(db.userVersion, LibraryDb.schemaVersion);
      expect(
        db
            .select(
              'SELECT name, genres, runtime, director, actors, details_at '
              'FROM titles',
            )
            .single
            .values,
        ['Tenet', 'Action', 150, null, null, null],
        reason: 'its page on TMDB is still to be read',
      );
      expect(db.select('SELECT title FROM my_list').single.values, [3]);
      expect(db.select('SELECT count(*) FROM watch_history').single.values, [
        1,
      ]);
      db.execute(
        "UPDATE titles SET director = 'Christopher Nolan', "
        "actors = 'John David Washington, Robert Pattinson', details_at = 11",
      );
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
