import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/features/metadata/match_store.dart';
import 'package:dhara/features/metadata/metadata_store.dart';
import 'package:dhara/features/metadata/tmdb_client.dart';
import 'package:dhara/features/metadata/video_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

TmdbCandidate _film(int id, String title, int year) => TmdbCandidate(
  id: id,
  kind: TitleKind.movie,
  title: title,
  originalTitle: 'Original $title',
  year: year,
  overview: 'About $title.',
  votes: 321,
  rating: 7.5,
  language: 'en',
  posterPath: '/p$id.jpg',
  backdropPath: '/b$id.jpg',
);

void main() {
  late LibraryDb library;
  late Database db;
  late MatchStore store;
  late DateTime clock;
  var urls = 0;

  setUp(() {
    library = LibraryDb.inMemory();
    db = library.db;
    clock = DateTime(2026, 11, 14, 12);
    store = MatchStore(library, now: () => clock);
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

  Map<String, Object?> title(int id) =>
      db.select('SELECT * FROM titles WHERE id = ?', [id]).single;

  int count(String table) =>
      db.select('SELECT count(*) AS n FROM $table').single['n'] as int;

  group('pendingTitles', () {
    test('lists titles not looked up yet, with what to ask by', () {
      final plain = add('Movies/English', 'Stillwater (2018) 1080p.mkv');
      final named = add(
        'English Movies/(2008)/The Wave (2008) 720p',
        'Die.Welle.Aka.The.Wave.2008.720p.BluRay.x264.mp4',
      );
      final show = add('Tv/Some Show Season 02 (2020)', 'Some Show S02E01.mkv');

      final pending = store.pendingTitles();

      expect([for (final entry in pending) entry.id], [plain, named, show]);
      expect(pending[0].name, 'Stillwater');
      expect(pending[0].year, 2018);
      expect(pending[0].altName, isNull);
      expect(pending[0].kind, TitleKind.movie);
      expect(pending[1].altName, 'Die Welle Aka The Wave');
      expect(pending[2].kind, TitleKind.series);
      expect(pending[2].query.year, 2020);
    });

    test('goes on after a given id, a few at a time', () {
      final ids = [
        for (var i = 0; i < 5; i++) add('Movies', 'Film $i (2001).mkv'),
      ];

      expect([
        for (final entry in store.pendingTitles(limit: 2)) entry.id,
      ], ids.take(2));
      expect([
        for (final entry in store.pendingTitles(after: ids[1])) entry.id,
      ], ids.skip(2));
      expect(store.pendingTitles(after: ids.last), isEmpty);
    });

    test('leaves out titles that were looked up or have no video', () {
      final matched = add('Movies', 'A (2001).mkv');
      final missing = add('Movies', 'B (2002).mkv');
      final gone = add('Movies', 'C (2003).mkv');
      final waiting = add('Movies', 'D (2004).mkv');
      store.apply(matched, _film(1, 'A', 2001), confidence: 95);
      store.markNotFound(missing);
      db.execute('DELETE FROM file_meta WHERE title = ?', [gone]);

      expect([for (final entry in store.pendingTitles()) entry.id], [waiting]);
    });
  });

  test('reviewableTitles lists what is unsure or not found, as spelled', () {
    final sure = add('Movies', 'Sure (2001).mkv');
    final unsure = add(
      'English Movies/(2006)/Silent Hills (2006) 720p',
      'Silent.Hill.2006.BluRay.720p.x264.YIFY.mp4',
    );
    final lost = add('Movies', 'lost film (2004).mkv');
    add('Movies', 'Waiting (2005).mkv');
    store
      ..apply(sure, _film(1, 'Sure', 2001), confidence: 95)
      ..apply(unsure, _film(2, 'Silent Hill', 2006), confidence: 70)
      ..markNotFound(lost);

    final titles = store.reviewableTitles();

    expect([for (final entry in titles) entry.id], [unsure, lost]);
    // By what the files call it, not by what TMDB does.
    expect(titles.first.name, 'Silent Hills');
    expect(titles.first.year, 2006);
    expect(titles.first.altName, 'Silent Hill');
    expect(titles.last.name, 'lost film');
    expect(store.reviewableTitles(after: unsure).single.id, lost);
    expect(store.reviewableTitles(limit: 1), hasLength(1));
  });

  group('apply', () {
    test('a sure match gives the title the film\'s data', () {
      final id = add('Movies', 'vivarium (2019) 720p.mkv');

      final (outcome, now) = store.apply(
        id,
        _film(42, 'Vivarium', 2019),
        confidence: 92,
      );

      expect((outcome, now), (MatchOutcome.matched, id));
      final row = title(id);
      expect(row['name'], 'Vivarium');
      expect(row['original_name'], 'Original Vivarium');
      expect(row['year'], 2019);
      expect(row['tmdb_id'], 42);
      expect(row['match_state'], MatchState.matched);
      expect(row['confidence'], 92);
      expect(row['overview'], 'About Vivarium.');
      expect(row['rating'], 7.5);
      expect(row['votes'], 321);
      expect(row['language'], 'en');
      expect(row['poster_path'], '/p42.jpg');
      expect(row['backdrop_path'], '/b42.jpg');
      expect(row['matched_at'], clock.millisecondsSinceEpoch);
      // The title is found by its new name; its spelling stays on record.
      expect(
        db
            .select(
              "SELECT rowid FROM titles_fts WHERE titles_fts MATCH 'original'",
            )
            .single
            .values,
        [id],
      );
      expect(db.select('SELECT name, fixed FROM title_keys').single.values, [
        'vivarium',
        0,
      ]);
    });

    test('a match below the line is kept but put up for review', () {
      final id = add('Movies', 'Hell.mkv');

      final (outcome, _) = store.apply(
        id,
        _film(7, 'Hell', 2011),
        confidence: 78,
      );

      expect(outcome, MatchOutcome.unsure);
      expect(title(id)['match_state'], MatchState.unsure);
      expect(title(id)['tmdb_id'], 7);
      expect(title(id)['confidence'], 78);
    });

    test('two spellings of one film become one title', () {
      final first = add('Movies/English', 'Boyka Undisputed (2016) 1080p.mkv');
      final second = add(
        'English Movies/(2016)/Boyka-Undisputed IV (2016) 720p',
        'boyka.mkv',
        source: 'flix',
      );
      final film = _film(5, 'Boyka: Undisputed IV', 2016);
      store.apply(first, film, confidence: 89);

      final (outcome, now) = store.apply(second, film, confidence: 100);

      expect((outcome, now), (MatchOutcome.merged, first));
      expect(count('titles'), 1);
      expect(db.select('SELECT DISTINCT title FROM file_meta').single.values, [
        first,
      ]);
      expect(
        [
          for (final row in db.select('SELECT title FROM title_keys'))
            row['title'],
        ],
        [first, first],
        reason: 'both spellings lead to it from now on',
      );
      expect(count('file_meta'), 2);
    });

    test('a sure match settles what was unsure about the other title', () {
      final first = add('Movies', 'Hell.mkv');
      final second = add('Movies', 'Hell (2011) 720p.mkv');
      final film = _film(7, 'Hell', 2011);
      store.apply(first, film, confidence: 70);

      final (outcome, now) = store.apply(second, film, confidence: 100);

      expect((outcome, now), (MatchOutcome.merged, first));
      expect(title(first)['match_state'], MatchState.matched);
      expect(title(first)['confidence'], 100);
    });

    test('an unsure match is never merged into another title', () {
      final first = add('Movies', 'Hell (2011) 720p.mkv');
      final second = add('Movies', 'Hell.mkv');
      final film = _film(7, 'Hell', 2011);
      store.apply(first, film, confidence: 100);

      final (outcome, now) = store.apply(second, film, confidence: 70);

      expect((outcome, now), (MatchOutcome.unsureNotApplied, second));
      expect(count('titles'), 2);
      expect(title(second)['match_state'], MatchState.unsure);
      expect(title(second)['tmdb_id'], isNull);
      expect(title(second)['name'], 'Hell');
    });

    test('by hand it is final, and tied to its spellings', () {
      final id = add('Movies', 'Hell.mkv');

      final (outcome, _) = store.apply(
        id,
        _film(7, 'Hell', 2011),
        confidence: 10,
        byHand: true,
      );

      expect(outcome, MatchOutcome.matched);
      expect(title(id)['match_state'], MatchState.byHand);
      expect(title(id)['confidence'], 100);
      expect(db.select('SELECT fixed FROM title_keys').single.values, [1]);
    });

    test('by hand it also merges, and the merged title is final', () {
      final first = add('Movies', 'Hell (2011) 720p.mkv');
      final second = add('Movies', 'Hell.mkv');
      final film = _film(7, 'Hell', 2011);
      store.apply(first, film, confidence: 70);

      final (outcome, now) = store.apply(
        second,
        film,
        confidence: 0,
        byHand: true,
      );

      expect((outcome, now), (MatchOutcome.merged, first));
      expect(title(first)['match_state'], MatchState.byHand);
      expect(db.select('SELECT DISTINCT fixed FROM title_keys').single.values, [
        1,
      ]);
    });

    test('does nothing for a title that is gone or of the other kind', () {
      final show = add('Tv/Show Season 1', 'Show S01E01.mkv');

      expect(store.apply(show, _film(7, 'Show', 2011), confidence: 100), (
        MatchOutcome.skipped,
        show,
      ));
      expect(store.apply(999, _film(7, 'Show', 2011), confidence: 100), (
        MatchOutcome.skipped,
        999,
      ));
      expect(title(show)['match_state'], MatchState.pending);
    });

    test('a film and a show may share a TMDB id', () {
      final film = add('Movies', 'Twins (2019).mkv');
      final show = add('Tv/Twins Season 1', 'Twins S01E01.mkv');

      store.apply(film, _film(7, 'Twins', 2019), confidence: 100);
      final (outcome, _) = store.apply(
        show,
        const TmdbCandidate(id: 7, kind: TitleKind.series, title: 'Twins'),
        confidence: 100,
      );

      expect(outcome, MatchOutcome.matched);
      expect(count('titles'), 2);
    });
  });

  group('not found', () {
    test('is noted, with how close the best candidate came', () {
      final id = add('Movies', 'Nothing Like It (2001).mkv');

      store.markNotFound(id, confidence: 35);

      expect(title(id)['match_state'], MatchState.notFound);
      expect(title(id)['confidence'], 35);
      expect(title(id)['matched_at'], clock.millisecondsSinceEpoch);
    });

    test('does not undo a match', () {
      final id = add('Movies', 'A (2001).mkv');
      store.apply(id, _film(1, 'A', 2001), confidence: 95);

      store.markNotFound(id);

      expect(title(id)['match_state'], MatchState.matched);
    });

    test('is tried again after a month', () {
      final old = add('Movies', 'Old (2001).mkv');
      store.markNotFound(old);
      clock = clock.add(const Duration(days: 20));
      final recent = add('Movies', 'Recent (2002).mkv');
      store.markNotFound(recent);
      clock = clock.add(const Duration(days: 15));

      expect(store.retryNotFound(), 1);

      expect(title(old)['match_state'], MatchState.pending);
      expect(title(recent)['match_state'], MatchState.notFound);
      expect([for (final entry in store.pendingTitles()) entry.id], [old]);
    });
  });

  test('counts the titles in each state', () {
    final ids = [
      for (var i = 0; i < 7; i++) add('Movies', 'Film $i (200$i).mkv'),
    ];
    store.apply(ids[0], _film(10, 'A', 2000), confidence: 95);
    store.apply(ids[1], _film(11, 'B', 2001), confidence: 90);
    store.apply(ids[2], _film(12, 'C', 2002), confidence: 70);
    store.markNotFound(ids[3]);
    store.apply(ids[4], _film(14, 'E', 2004), confidence: 0, byHand: true);
    // A title without a video does not count.
    db.execute('DELETE FROM file_meta WHERE title = ?', [ids[5]]);

    final counts = store.counts();

    expect(counts.matched, 2);
    expect(counts.unsure, 1);
    expect(counts.notFound, 1);
    expect(counts.byHand, 1);
    expect(counts.pending, 1);
    expect(counts.lookedUp, 4);
    expect(counts.toReview, 2);
    expect(const MatchCounts().lookedUp, 0);
  });
}
