import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/features/metadata/metadata_store.dart';
import 'package:dhara/features/metadata/release_name.dart';
import 'package:dhara/features/metadata/video_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late LibraryDb library;
  late Database db;
  late MetadataStore store;
  var urls = 0;

  setUp(() {
    library = LibraryDb.inMemory();
    db = library.db;
    store = MetadataStore(library, now: () => DateTime(2026, 11, 14));
  });

  tearDown(() => library.close());

  /// Adds a folder to the source called [sourceId] (made if need be).
  int addFolder(String sourceId, String path) {
    db.execute(
      'INSERT INTO sources (source_id) VALUES (?) '
      'ON CONFLICT (source_id) DO NOTHING',
      [sourceId],
    );
    db.execute(
      'INSERT INTO folders (source, url, path, depth) '
      'SELECT id, ?, ?, 1 FROM sources WHERE source_id = ?',
      ['http://$sourceId.test/${urls++}/', path, sourceId],
    );
    return db.lastInsertRowId;
  }

  int addFile(int folder, String name, {int? size}) {
    db.execute(
      'INSERT INTO files (folder, name, url, size, added_at) '
      'VALUES (?, ?, ?, ?, 0)',
      [folder, name, 'http://files.test/${urls++}/$name', size],
    );
    return db.lastInsertRowId;
  }

  /// A video in a folder of its own.
  int add(String sourceId, String path, String name) =>
      addFile(addFolder(sourceId, path), name);

  /// Reads every unread name, a few at a time, as the app does. Returns how
  /// many were read.
  int readNames([MetadataStore? using]) {
    final reader = using ?? store;
    var total = 0;
    while (true) {
      final files = reader.unreadFiles(limit: 3);
      if (files.isEmpty) return total;
      reader.saveIdentities({
        for (final file in files)
          file.id: identifyVideo(
            path: file.path,
            name: file.name,
            videosInFolder: file.videosInFolder,
            latestYear: 2027,
          ),
      });
      total += files.length;
    }
  }

  int count(String table) =>
      db.select('SELECT count(*) AS n FROM $table').single['n'] as int;

  int titleOf(int file) =>
      db.select('SELECT title FROM file_meta WHERE file = ?', [
            file,
          ]).single['title']
          as int;

  const all = ['flix', 'icc'];

  group('titles', () {
    test('copies of a film on two servers are one title', () {
      final first = add(
        'flix',
        'English Movies/(2019)/Vivarium (2019) 720p [Dual Audio]',
        'Vivarium (2019) 720p BluRay x264 ESub [Dual Audio]'
            '[Hindi 2.0+English 5.1] -mkvC.mkv',
      );
      final second = add(
        'icc',
        'Movies/English',
        'Vivarium (2019) 1080p WEBRip.mkv',
      );

      expect(readNames(), 2);

      expect(count('titles'), 1);
      expect(
        db
            .select(
              'SELECT kind, name, year, match_state, added_at FROM titles',
            )
            .single
            .values,
        [0, 'Vivarium', 2019, 0, DateTime(2026, 11, 14).millisecondsSinceEpoch],
      );
      expect(
        db
            .select('SELECT key, name, year, fixed FROM title_keys')
            .single
            .values,
        ['m|vivarium|2019', 'Vivarium', 2019, 0],
      );
      expect(titleOf(first), titleOf(second));
      final copies = store.copiesOf(titleOf(first), sourceIds: all);
      expect([for (final copy in copies) copy.sourceId], ['icc', 'flix']);
      expect([for (final copy in copies) copy.height], [1080, 720]);
    });

    test('a film of another year is another title', () {
      add('flix', 'Movies', 'The Ring (2002) 720p.mkv');
      add('flix', 'Movies', 'The Ring (1998) 720p.mkv');

      readNames();

      expect(count('titles'), 2);
    });

    test('a later copy can bring the name the file gives the film', () {
      add('icc', 'Movies/English', 'This Is Spinal Tap (1984) 1080p.mkv');
      readNames();
      expect(db.select('SELECT alt_name FROM title_keys').single.values, [
        null,
      ]);

      add(
        'flix',
        'English Movies/(1960-1994)/This Is Spinal Tap (1984) 720p',
        'Eto.Spinal.Tap.1984.720p.BRRip.700MB.MkvCage.com.mkv',
      );
      readNames();

      expect(count('titles'), 1);
      expect(db.select('SELECT alt_name FROM title_keys').single.values, [
        'Eto Spinal Tap',
      ]);
    });

    test('the episodes of a show are one title, with its earliest year', () {
      final later = add(
        'icc',
        'Tv Show/English/Some Show Season 02 (2020) Completed',
        'Some Show S02E01.mkv',
      );
      final earlier = add(
        'icc',
        'Tv Show/English/Some Show Season 01 (2019) Completed',
        'Some Show S01E03_The Name.mkv',
      );

      readNames();

      expect(count('titles'), 1);
      expect(db.select('SELECT kind, name, year FROM titles').single.values, [
        1,
        'Some Show',
        2019,
      ]);
      final copies = store.copiesOf(titleOf(later), sourceIds: all);
      expect(
        [for (final copy in copies) (copy.fileId, copy.season, copy.episode)],
        [(earlier, 1, 3), (later, 2, 1)],
      );
      expect(copies.first.episodeName, 'The Name');
    });

    test('the year of a show is left alone once it has been matched', () {
      add('icc', 'Tv/Show Season 02 (2020) Completed', 'Show S02E01.mkv');
      readNames();
      db.execute('UPDATE titles SET match_state = 1, year = 2018');

      add('icc', 'Tv/Show Season 01 (2015) Completed', 'Show S01E01.mkv');
      readNames();

      expect(db.select('SELECT year FROM titles').single.values, [2018]);
    });

    test('a video that is neither a film nor an episode has no title', () {
      final clip = add('icc', 'Fun Zone/Funny Vedio/WMV', 'Coins.wmv');

      expect(readNames(), 1);

      expect(count('titles'), 0);
      expect(
        db
            .select('SELECT kind, title FROM file_meta WHERE file = ?', [clip])
            .single
            .values,
        [2, null],
      );
      expect(store.unreadFiles(), isEmpty);
    });
  });

  group('unreadFiles', () {
    test('lists videos once, oldest first, with what their folder holds', () {
      final folder = addFolder('icc', 'Movies/English');
      final first = addFile(folder, 'A (2001).mkv');
      final second = addFile(folder, 'B (2002).mkv');
      final alone = add('flix', 'Movies/C (2003)', 'c.mkv');

      final unread = store.unreadFiles();
      expect([for (final file in unread) file.id], [first, second, alone]);
      expect([for (final file in unread) file.videosInFolder], [2, 2, 1]);
      expect(unread.last.path, 'Movies/C (2003)');
      expect(unread.last.name, 'c.mkv');
      expect(store.unreadFiles(limit: 2), hasLength(2));

      readNames();
      expect(store.unreadFiles(), isEmpty);

      final added = addFile(folder, 'D (2004).mkv');
      expect([for (final file in store.unreadFiles()) file.id], [added]);
    });

    test('lists every video again for a newer parser', () {
      add('icc', 'Movies', 'A (2001).mkv');
      add('icc', 'Movies', 'B (2002).mkv');
      readNames();

      final newer = MetadataStore(library, parserVersion: 2);
      expect(newer.unreadFiles(), hasLength(2));
      expect(newer.counts().unreadFiles, 2);

      expect(readNames(newer), 2);
      expect(newer.unreadFiles(), isEmpty);
      expect(count('titles'), 2);
      expect(db.select('SELECT DISTINCT parser FROM file_meta').single.values, [
        2,
      ]);
    });

    test('lists the videos of a title that was removed', () {
      final file = add('icc', 'Movies', 'A (2001).mkv');
      readNames();

      db.execute('DELETE FROM titles');

      expect([for (final unread in store.unreadFiles()) unread.id], [file]);
      readNames();
      expect(count('titles'), 1);
    });
  });

  group('saveIdentities', () {
    test('skips a file that is gone meanwhile', () {
      final file = add('icc', 'Movies', 'A (2001).mkv');
      final identity = identifyVideo(path: 'Movies', name: 'A (2001).mkv');
      db.execute('DELETE FROM files WHERE id = ?', [file]);

      store.saveIdentities({file: identity});

      expect(count('file_meta'), 0);
      expect(count('titles'), 0);
    });

    test('keeps nothing of a batch that fails', () {
      final file = add('icc', 'Movies', 'A (2001).mkv');
      db.execute(
        'CREATE TRIGGER refuse BEFORE INSERT ON file_meta '
        "BEGIN SELECT raise(ABORT, 'no'); END",
      );

      expect(
        () => store.saveIdentities({
          file: identifyVideo(path: 'Movies', name: 'A (2001).mkv'),
        }),
        throwsA(isA<SqliteException>()),
      );

      expect(count('titles'), 0);
      expect(count('title_keys'), 0);
    });

    test('moves a file to another title when it is read differently', () {
      final file = add('icc', 'Movies', 'A (2001).mkv');
      readNames();
      final before = titleOf(file);

      store.saveIdentities({
        file: identifyVideo(path: 'Movies', name: 'B (2002).mkv'),
      });

      expect(titleOf(file), isNot(before));
      expect(count('file_meta'), 1);
      expect(count('titles'), 2);
      expect(store.removeTitlesWithoutFiles(), 1);
      expect(db.select('SELECT name FROM titles').single.values, ['B']);
    });
  });

  group('removeTitlesWithoutFiles', () {
    test('removes the titles of files that are gone', () {
      final gone = add('flix', 'Movies', 'A (2001).mkv');
      add('icc', 'Movies', 'B (2002).mkv');
      readNames();

      db.execute('DELETE FROM files WHERE id = ?', [gone]);
      expect(count('file_meta'), 1, reason: 'goes with its file');

      expect(store.removeTitlesWithoutFiles(), 1);
      expect(db.select('SELECT name FROM titles').single.values, ['B']);
      expect(count('title_keys'), 1);
      expect(store.removeTitlesWithoutFiles(), 0);
    });

    test('removes the titles of a source that was removed', () {
      add('flix', 'Movies', 'A (2001).mkv');
      add('flix', 'Tv/Show Season 1', 'Show S01E01.mkv');
      readNames();

      db.execute("DELETE FROM sources WHERE source_id = 'flix'");

      expect(store.removeTitlesWithoutFiles(), 2);
      expect(count('titles'), 0);
    });

    test('keeps a title that is on My List', () {
      final file = add('flix', 'Movies', 'A (2001).mkv');
      add('flix', 'Movies', 'B (2002).mkv');
      readNames();
      db.execute(
        'INSERT INTO my_list (title, added_at) SELECT id, 0 FROM titles '
        "WHERE name = 'A'",
      );
      db.execute('DELETE FROM files');
      expect(file, isPositive);

      expect(store.removeTitlesWithoutFiles(), 1);
      expect(db.select('SELECT name FROM titles').single.values, ['A']);
      expect(count('my_list'), 1);
    });

    test('keeps a title that was tied to its name by hand', () {
      final file = add('flix', 'Movies', 'A (2001).mkv');
      readNames();
      db.execute('UPDATE title_keys SET fixed = 1');
      db.execute('DELETE FROM files WHERE id = ?', [file]);

      expect(store.removeTitlesWithoutFiles(), 0);
      expect(count('titles'), 1);
    });
  });

  group('searchTitles', () {
    List<String> names(String text, {List<String> sources = all}) => [
      for (final hit in store.searchTitles(text, sourceIds: sources)) hit.name,
    ];

    test('finds titles by words of their name, the last one unfinished', () {
      add('flix', 'Movies', 'The Dark Knight (2008) 720p.mkv');
      add('flix', 'Movies', 'The Dark Knight Rises (2012) 720p.mkv');
      add('flix', 'Movies', 'Inception (2010) 720p.mkv');
      readNames();

      expect(names('dark knight'), hasLength(2));
      expect(names('KNIGHT ris'), ['The Dark Knight Rises']);
      expect(names('incep'), ['Inception']);
      expect(names('interstellar'), isEmpty);
      expect(names(''), isEmpty);
      expect(names('"'), isEmpty);
    });

    test('ignores accents, and does not find tags of the copies', () {
      add('flix', 'Movies', 'Les.Misérables.2012.720p.BRrip.x264.YIFY.mp4');
      readNames();

      expect(names('miserables'), ['Les Misérables']);
      expect(names('yify'), isEmpty);
      expect(names('720p'), isEmpty);
    });

    test('says what the title is and how many copies there are', () {
      add('flix', 'Movies/A Film (2001)', 'A Film (2001) 720p.mkv');
      add('icc', 'Movies', 'A Film (2001) 1080p.mkv');
      add('icc', 'Movies/A Film (2001)', 'Trailer - A Film (2001).mp4');
      readNames();

      final hit = store.searchTitles('film', sourceIds: all).single;
      expect(hit.kind, TitleKind.movie);
      expect((hit.name, hit.year), ('A Film', 2001));
      expect(hit.posterPath, isNull);
      expect(hit.copies, 2, reason: 'the trailer is not a copy');
    });

    test('leaves out titles that are only on other sources', () {
      add('flix', 'Movies', 'Only Here (2001).mkv');
      add('flix', 'Movies', 'On Both (2002).mkv');
      add('icc', 'Movies', 'On Both (2002).mkv');
      readNames();

      expect(names('only'), ['Only Here']);
      expect(names('only', sources: ['icc']), isEmpty);
      expect(names('only', sources: []), isEmpty);
      final both = store.searchTitles('both', sourceIds: ['icc']).single;
      expect(both.copies, 1);
    });

    test('follows a title that is renamed or removed', () {
      add('flix', 'Movies', 'Tenit (2020).mkv');
      readNames();

      db.execute("UPDATE titles SET name = 'Tenet', original_name = 'テネット'");
      expect(names('tenet'), ['Tenet']);
      expect(names('テネット'), ['Tenet']);
      expect(names('tenit'), isEmpty);

      db.execute('DELETE FROM titles');
      expect(names('tenet'), isEmpty);
    });

    test('returns at most the number asked for', () {
      for (var i = 0; i < 8; i++) {
        add('flix', 'Movies', 'Film Number $i (2001).mkv');
      }
      readNames();

      expect(
        store.searchTitles('film', sourceIds: all, limit: 5),
        hasLength(5),
      );
    });
  });

  group('copiesOf', () {
    test('gives back what the name of each copy said', () {
      final file = add(
        'flix',
        'Movies',
        'Godzilla.Vs..Kong.2021.1080p.3D.BluRay.HSBS.x265-[YTS.MX].mp4',
      );
      db.execute('UPDATE files SET size = 2365113344 WHERE id = ?', [file]);
      final part = add(
        'icc',
        'Movies',
        'Godzilla vs Kong (2021) DVDRip XviD [Hindi+English] CD2.avi',
      );
      readNames();

      final copies = store.copiesOf(titleOf(file), sourceIds: all);
      expect(copies, hasLength(2));

      final sharp = copies.singleWhere((copy) => copy.fileId == file);
      expect(sharp.sourceId, 'flix');
      expect(sharp.path, 'Movies');
      expect(sharp.name, startsWith('Godzilla.Vs..Kong'));
      expect(sharp.url.host, 'files.test');
      expect(sharp.size, 2365113344);
      expect(sharp.height, 1080);
      expect(sharp.source, VideoSource.bluRay);
      expect(sharp.codec, VideoCodec.hevc);
      expect(sharp.is3d, isTrue);
      expect(sharp.group, 'YTS');
      expect(sharp.languages, isEmpty);
      expect(sharp.part, isNull);

      final disc = copies.singleWhere((copy) => copy.fileId == part);
      expect(disc.part, 2);
      expect(disc.source, VideoSource.dvd);
      expect(disc.codec, VideoCodec.xvid);
      expect(disc.languages, ['Hindi', 'English']);
      expect(disc.is3d, isFalse);
      expect(disc.size, isNull);
    });

    test('orders episodes, the sharpest copy first, extras last', () {
      final low = add('icc', 'Tv/Show Season 1', 'Show S01E02 480p.mkv');
      final high = add('flix', 'Tv/Show Season 1', 'Show S01E02 1080p.mkv');
      final first = add('icc', 'Tv/Show Season 1', 'Show S01E01.mkv');
      final next = add('icc', 'Tv/Show Season 2', 'Show S02E01.mkv');
      readNames();
      final film = add('icc', 'Movies/Film (2001)', 'Film (2001).mkv');
      final trailer = add(
        'icc',
        'Movies/Film (2001)',
        'Film (2001) Trailer.mp4',
      );
      readNames();

      expect(
        [
          for (final copy in store.copiesOf(titleOf(low), sourceIds: all))
            copy.fileId,
        ],
        [first, high, low, next],
      );
      final ofFilm = store.copiesOf(titleOf(film), sourceIds: all);
      expect([for (final copy in ofFilm) copy.fileId], [film, trailer]);
      expect(ofFilm.last.extra, ExtraKind.trailer);
    });

    test('leaves out copies on other sources', () {
      final file = add('flix', 'Movies', 'On Both (2002).mkv');
      add('icc', 'Movies', 'On Both (2002).mkv');
      readNames();

      final title = titleOf(file);
      expect(store.copiesOf(title, sourceIds: ['icc']), hasLength(1));
      expect(store.copiesOf(title, sourceIds: []), isEmpty);
      expect(store.copiesOf(title + 99, sourceIds: all), isEmpty);
    });

    test('reads a tag of a newer app as nothing', () {
      final file = add('flix', 'Movies', 'A (2001) 720p BluRay.mkv');
      readNames();
      db.execute("UPDATE file_meta SET source = 'hologram', extra = NULL");

      expect(
        store.copiesOf(titleOf(file), sourceIds: all).single.source,
        isNull,
      );
    });
  });

  test('counts films, shows, other videos and unread names', () {
    add('flix', 'Movies', 'A (2001).mkv');
    add('icc', 'Movies', 'A (2001).mkv');
    add('flix', 'Movies', 'B (2002).mkv');
    add('icc', 'Tv/Show Season 1', 'Show S01E01.mkv');
    add('icc', 'Tv/Show Season 1', 'Show S01E02.mkv');
    add('icc', 'Fun Zone/Funny Vedio/WMV', 'Coins.wmv');

    final before = store.counts();
    expect(
      (before.movies, before.shows, before.otherVideos, before.unreadFiles),
      (0, 0, 0, 6),
    );

    readNames();

    final after = store.counts();
    expect(
      (after.movies, after.shows, after.otherVideos, after.unreadFiles),
      (2, 1, 1, 0),
    );
  });

  group('schema', () {
    int addTitle({int kind = 0, int? tmdb}) {
      db.execute(
        'INSERT INTO titles (kind, name, tmdb_id, added_at) '
        "VALUES (?, 'A', ?, 0)",
        [kind, tmdb],
      );
      return db.lastInsertRowId;
    }

    test('a provider id belongs to one film and one show at most', () {
      addTitle(tmdb: 603);
      addTitle(kind: 1, tmdb: 603);
      addTitle();
      addTitle();

      expect(() => addTitle(tmdb: 603), throwsA(isA<SqliteException>()));
    });

    test('refuses values outside their range', () {
      expect(() => addTitle(kind: 2), throwsA(isA<SqliteException>()));
      final title = addTitle();
      for (final change in [
        'match_state = 6',
        'confidence = 101',
        "year = 'soon'",
      ]) {
        expect(
          () => db.execute('UPDATE titles SET $change WHERE id = ?', [title]),
          throwsA(isA<SqliteException>()),
          reason: change,
        );
      }
    });

    test('removing a title removes what belongs to it', () {
      final file = add('flix', 'Tv/Show Season 1', 'Show S01E01.mkv');
      readNames();
      final title = titleOf(file);
      db.execute(
        "INSERT INTO seasons (title, season, name) VALUES (?, 1, 'One')",
        [title],
      );
      db.execute(
        'INSERT INTO episodes (title, season, episode, name) '
        "VALUES (?, 1, 1, 'Pilot')",
        [title],
      );

      db.execute('DELETE FROM titles WHERE id = ?', [title]);

      expect(count('title_keys'), 0);
      expect(count('seasons'), 0);
      expect(count('episodes'), 0);
      // The video stays in the index; its name is read again.
      expect(db.select('SELECT title FROM file_meta').single.values, [null]);
    });

    test('keeps one cached answer per provider and question', () {
      void put(String provider, String key, String body) => db.execute(
        'INSERT OR REPLACE INTO metadata_cache '
        '(provider, key, body, fetched_at) VALUES (?, ?, dhara_pack(?), 0)',
        [provider, key, body],
      );
      put('tmdb', 'movie|a|2001', '[]');
      put('tmdb', 'movie|a|2001', '[1]');
      put('anilist', 'movie|a|2001', '{}');

      expect(count('metadata_cache'), 2);
      expect(
        db
            .select(
              'SELECT dhara_unpack(body) FROM metadata_cache '
              "WHERE provider = 'tmdb'",
            )
            .single
            .values,
        ['[1]'],
      );
    });
  });

  test('reads and searches a large library quickly', () {
    final folder = addFolder('icc', 'Movies/English');
    library.transaction(() {
      for (var i = 0; i < 20000; i++) {
        addFile(folder, 'Film Number $i (${1950 + i % 70}) 720p BluRay.mkv');
      }
    });

    final reading = Stopwatch()..start();
    var read = 0;
    while (true) {
      final files = store.unreadFiles();
      if (files.isEmpty) break;
      store.saveIdentities({
        for (final file in files)
          file.id: identifyVideo(
            path: file.path,
            name: file.name,
            videosInFolder: file.videosInFolder,
            latestYear: 2027,
          ),
      });
      read += files.length;
    }
    reading.stop();
    expect(read, 20000);
    expect(count('titles'), 20000);

    final searching = Stopwatch()..start();
    final hits = store.searchTitles('number 1234', sourceIds: ['icc']);
    searching.stop();
    expect(hits, isNotEmpty);

    // A few seconds and a few milliseconds on a slow machine; the limits
    // only catch a blow-up.
    expect(reading.elapsed, lessThan(const Duration(seconds: 60)));
    expect(searching.elapsed, lessThan(const Duration(milliseconds: 500)));
  });
}
