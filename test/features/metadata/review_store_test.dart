import 'dart:convert';

import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/features/metadata/match_store.dart';
import 'package:dhara/features/metadata/metadata_store.dart';
import 'package:dhara/features/metadata/review_store.dart';
import 'package:dhara/features/metadata/tmdb_cache.dart';
import 'package:dhara/features/metadata/tmdb_client.dart';
import 'package:dhara/features/metadata/video_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

TmdbCandidate _film(int id, String title, int year) =>
    TmdbCandidate(id: id, kind: TitleKind.movie, title: title, year: year);

void main() {
  late LibraryDb library;
  late Database db;
  late ReviewStore store;
  var urls = 0;

  setUp(() {
    library = LibraryDb.inMemory();
    db = library.db;
    store = ReviewStore(library, now: () => DateTime(2026, 11, 14));
  });

  tearDown(() => library.close());

  /// Puts a video into the index, reads its name and returns its title.
  int add(String path, String name, {String source = 'icc'}) {
    db.execute(
      'INSERT INTO sources (source_id) VALUES (?) '
      'ON CONFLICT (source_id) DO NOTHING',
      [source],
    );
    db.execute(
      'INSERT INTO folders (source, url, path, depth) '
      'SELECT id, ?, ?, 1 FROM sources WHERE source_id = ?',
      ['http://$source.test/${urls++}/', path, source],
    );
    db.execute(
      'INSERT INTO files (folder, name, url, added_at) VALUES (?, ?, ?, 0)',
      [db.lastInsertRowId, name, 'http://$source.test/${urls++}/$name'],
    );
    final file = db.lastInsertRowId;
    MetadataStore(library).saveIdentities({
      file: identifyVideo(path: path, name: name, latestYear: 2027),
    });
    return db.select('SELECT title FROM file_meta WHERE file = ?', [
          file,
        ]).single['title']
        as int;
  }

  /// Keeps [films] as what TMDB answered to a search.
  void answer(String name, int? year, List<TmdbCandidate> films) =>
      MetadataStore(library).cacheAnswer(
        CachedTmdb.provider,
        CachedTmdb.searchKey(TitleKind.movie, name, year),
        jsonEncode([for (final film in films) film.toJson()]),
      );

  test('lists unsure titles before those not found, each by name', () {
    final matches = MatchStore(library);
    final sure = add('Movies', 'Sure (2001).mkv');
    final zebra = add('Movies', 'zebra (2002).mkv');
    final apple = add('Movies', 'Apple (2003).mkv');
    final lost = add('Movies', 'Lost (2004).mkv');
    add('Movies', 'Waiting (2005).mkv');
    matches
      ..apply(sure, _film(1, 'Sure', 2001), confidence: 95)
      ..apply(zebra, _film(2, 'Zebra', 2002), confidence: 70)
      ..apply(apple, _film(3, 'Apple', 2003), confidence: 61)
      ..markNotFound(lost, confidence: 30);

    final items = store.items(sourceIds: ['icc']);

    expect([for (final item in items) item.name], ['Apple', 'Zebra', 'Lost']);
    expect([for (final item in items) item.notFound], [false, false, true]);
    expect([for (final item in items) item.confidence], [61, 70, 30]);
    expect(items[1].spelledName, 'zebra', reason: 'as the file spells it');
    expect(store.items(sourceIds: ['icc'], limit: 2), hasLength(2));
    expect(store.items(sourceIds: ['flix']), isEmpty);
    expect(store.items(sourceIds: []), isEmpty);
  });

  test('counts the videos of a title without its trailers', () {
    final title = add('Movies/Lost (2004)', 'Lost (2004) 720p.mkv');
    add('Movies/Lost (2004)', 'Trailer - Lost (2004).mp4');
    add('Movies', 'Lost (2004) 1080p.mkv', source: 'flix');
    MatchStore(library).markNotFound(title);

    final item = store.items(sourceIds: ['icc', 'flix']).single;

    expect(item.copies, 2);
    expect(item.sampleName, 'Lost (2004) 720p.mkv');
    expect(item.samplePath, 'Movies/Lost (2004)');
  });

  group('keptCandidates', () {
    test('gathers the answers to every way the title was asked by', () {
      final title = add(
        'English Movies/(2006)/Silent Hills (2006) 720p',
        'Silent.Hill.2006.BluRay.720p.x264.YIFY.mp4',
      );
      MatchStore(library).markNotFound(title);
      answer('Silent Hills', 2006, const []);
      answer('Silent Hills', null, [_film(7, 'Silent Hills Forever', 2020)]);
      answer('Silent Hill', 2006, [
        _film(2, 'Silent Hill', 2006),
        _film(7, 'Silent Hills Forever', 2020),
      ]);
      answer('Something Else', 2006, [_film(9, 'Something Else', 2006)]);

      final item = store.items(sourceIds: ['icc']).single;
      expect((item.spelledName, item.spelledYear), ('Silent Hills', 2006));
      expect(item.altName, 'Silent Hill');

      expect([for (final film in store.keptCandidates(item)) film.id], [7, 2]);
    });

    test('skips what cannot be read, and has nothing for a new title', () {
      final title = add('Movies', 'Lost (2004).mkv');
      MatchStore(library).markNotFound(title);
      final item = store.items(sourceIds: ['icc']).single;
      expect(store.keptCandidates(item), isEmpty);

      MetadataStore(library).cacheAnswer(
        CachedTmdb.provider,
        CachedTmdb.searchKey(TitleKind.movie, 'Lost', 2004),
        'not json',
      );
      answer('Lost', null, [_film(4, 'Lost', 2004)]);

      expect(store.keptCandidates(item).single.id, 4);
    });
  });

  test('leaveAsIs settles a title for good', () {
    final title = add('Movies', 'Lost (2004).mkv');
    MatchStore(library).markNotFound(title);

    store.leaveAsIs(title);

    expect(store.items(sourceIds: ['icc']), isEmpty);
    expect(db.select('SELECT match_state FROM titles').single.values, [
      MatchState.leftAlone,
    ]);
    expect(db.select('SELECT fixed FROM title_keys').single.values, [1]);
    expect(MatchStore(library).pendingTitles(), isEmpty);
  });
}
