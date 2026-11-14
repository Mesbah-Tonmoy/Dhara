import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/features/metadata/episode_store.dart';
import 'package:dhara/features/metadata/match_store.dart';
import 'package:dhara/features/metadata/metadata_store.dart';
import 'package:dhara/features/metadata/tmdb_client.dart';
import 'package:dhara/features/metadata/video_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

TmdbDetails _details(int id, {List<int> seasons = const [1, 2]}) => TmdbDetails(
  summary: TmdbCandidate(id: id, kind: TitleKind.series, title: 'Show $id'),
  genres: const ['Drama', 'Mystery'],
  seasons: [
    for (final number in seasons)
      TmdbSeasonSummary(
        number: number,
        name: 'Season $number',
        episodeCount: 2,
        airDate: '201$number-09-01',
        posterPath: '/s$number.jpg',
      ),
  ],
);

TmdbSeason _season(int number, List<String> names) => TmdbSeason(
  number: number,
  name: 'Season $number',
  overview: 'What happens in season $number.',
  episodes: [
    for (final (index, name) in names.indexed)
      TmdbEpisode(
        number: index + 1,
        name: name,
        overview: 'About $name.',
        airDate: '2017-09-0${index + 1}',
        runtime: 45,
        stillPath: '/still$number-${index + 1}.jpg',
      ),
  ],
);

void main() {
  late LibraryDb library;
  late Database db;
  late EpisodeStore store;
  late DateTime clock;
  var urls = 0;

  setUp(() {
    library = LibraryDb.inMemory();
    db = library.db;
    clock = DateTime(2026, 11, 14, 12);
    store = EpisodeStore(library, now: () => clock);
  });

  tearDown(() => library.close());

  /// Puts a video into the index, reads its name and returns its title.
  int add(String path, String name) {
    db.execute(
      "INSERT INTO sources (source_id) VALUES ('icc') "
      'ON CONFLICT (source_id) DO NOTHING',
    );
    db.execute(
      'INSERT INTO folders (source, url, path, depth) VALUES (1, ?, ?, 1)',
      ['http://icc.test/${urls++}/', path],
    );
    db.execute(
      'INSERT INTO files (folder, name, url, added_at) VALUES (?, ?, ?, 0)',
      [db.lastInsertRowId, name, 'http://icc.test/${urls++}/$name'],
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

  /// A show with videos of the given episodes, matched to [tmdbId].
  int addShow(String name, int tmdbId, List<String> episodes) {
    late int title;
    for (final episode in episodes) {
      title = add('Tv/$name', '$name $episode.mkv');
    }
    MatchStore(library).apply(
      title,
      TmdbCandidate(id: tmdbId, kind: TitleKind.series, title: name),
      confidence: 100,
    );
    return title;
  }

  int count(String table) =>
      db.select('SELECT count(*) AS n FROM $table').single['n'] as int;

  group('showsToFetch', () {
    test('lists matched shows with the seasons the library has', () {
      final signal = addShow('The Quiet Signal', 70001, [
        'S02E01',
        'S01E02',
        'S01E01',
      ]);
      // Not shows, or not matched.
      add('Tv/Other Show', 'Other Show S01E01.mkv');
      final film = add('Movies', 'A Film (2001).mkv');
      MatchStore(library).apply(
        film,
        const TmdbCandidate(id: 5, kind: TitleKind.movie, title: 'A Film'),
        confidence: 100,
      );

      final shows = store.showsToFetch();

      expect(shows, hasLength(1));
      expect(shows.single.title, signal);
      expect(shows.single.tmdbId, 70001);
      expect(shows.single.seasons, [1, 2]);
    });

    test('lists a show numbered straight through without seasons', () {
      addShow('One Piece', 37854, ['- 1071']);

      expect(store.showsToFetch().single.seasons, isEmpty);
    });

    test('leaves out a show that has no video any more', () {
      final title = addShow('The Quiet Signal', 70001, ['S01E01']);
      db.execute('DELETE FROM file_meta WHERE title = ?', [title]);

      expect(store.showsToFetch(), isEmpty);
    });

    test('leaves a show alone for two weeks once it was asked about', () {
      addShow('The Quiet Signal', 70001, ['S01E01']);
      final show = store.showsToFetch().single;
      store.saveShow(show, _details(70001), [
        _season(1, ['Static']),
      ]);

      expect(store.showsToFetch(), isEmpty);
      clock = clock.add(const Duration(days: 13));
      expect(store.showsToFetch(), isEmpty);
      clock = clock.add(const Duration(days: 2));
      expect(store.showsToFetch().single.tmdbId, 70001);
    });

    test('asks again at once when the library gets another season', () {
      addShow('The Quiet Signal', 70001, ['S01E01']);
      store.saveShow(store.showsToFetch().single, _details(70001), [
        _season(1, ['Static']),
      ]);

      add('Tv/The Quiet Signal', 'The Quiet Signal S02E01.mkv');

      expect(store.showsToFetch().single.seasons, [1, 2]);
    });

    test('does not trust a note from the future', () {
      addShow('The Quiet Signal', 70001, ['S01E01']);
      store.saveShow(store.showsToFetch().single, _details(70001), const []);

      clock = clock.subtract(const Duration(days: 1));

      expect(store.showsToFetch(), hasLength(1));
    });
  });

  group('saveShow', () {
    test('keeps genres, seasons and the episodes asked for', () {
      final title = addShow('The Quiet Signal', 70001, ['S01E01', 'S01E02']);

      store.saveShow(store.showsToFetch().single, _details(70001), [
        _season(1, ['Static', 'Carrier Wave']),
      ]);

      expect(
        db
            .select('SELECT genres FROM titles WHERE id = ?', [title])
            .single
            .values,
        ['Drama, Mystery'],
      );
      expect(
        [
          for (final row in db.select(
            'SELECT season, name, overview, poster_path, air_date, '
            'episode_count FROM seasons WHERE title = ? ORDER BY season',
            [title],
          ))
            row.values,
        ],
        [
          [
            1,
            'Season 1',
            'What happens in season 1.',
            '/s1.jpg',
            '2011-09-01',
            2,
          ],
          // Listed by the show, but its episodes were not asked for.
          [2, 'Season 2', null, '/s2.jpg', '2012-09-01', 2],
        ],
      );
      expect(
        [
          for (final row in db.select(
            'SELECT season, episode, name, overview, still_path, air_date, '
            'runtime FROM episodes WHERE title = ? ORDER BY episode',
            [title],
          ))
            row.values,
        ],
        [
          [1, 1, 'Static', 'About Static.', '/still1-1.jpg', '2017-09-01', 45],
          [
            1,
            2,
            'Carrier Wave',
            'About Carrier Wave.',
            '/still1-2.jpg',
            '2017-09-02',
            45,
          ],
        ],
      );
    });

    test('replaces what was kept before', () {
      addShow('The Quiet Signal', 70001, ['S01E01']);
      final show = store.showsToFetch().single;
      store.saveShow(show, _details(70001), [
        _season(1, ['Old Name', 'Dropped']),
      ]);

      store.saveShow(show, _details(70001, seasons: [1]), [
        _season(1, ['New Name']),
      ]);

      expect(count('seasons'), 1);
      expect(db.select('SELECT name FROM episodes').single.values, [
        'New Name',
      ]);
      expect(count('metadata_cache'), 1);
    });

    test('a show TMDB no longer has is noted and keeps what it had', () {
      addShow('The Quiet Signal', 70001, ['S01E01']);
      final show = store.showsToFetch().single;
      store.saveShow(show, _details(70001), [
        _season(1, ['Static']),
      ]);
      clock = clock.add(const Duration(days: 20));

      store.saveShow(store.showsToFetch().single, null, const []);

      expect(store.showsToFetch(), isEmpty);
      expect(count('episodes'), 1);
    });

    test('does nothing for a title that is gone', () {
      store.saveShow(
        const ShowToFetch(title: 99, tmdbId: 1, seasons: [1]),
        _details(1),
        [
          _season(1, ['x']),
        ],
      );

      expect(count('seasons'), 0);
      expect(count('metadata_cache'), 0);
    });
  });

  test('the copies of a show carry the names TMDB gives the episodes', () {
    final title = addShow('The Quiet Signal', 70001, [
      'S01E01',
      'S01E02_From The File',
      'S02E01_Kept',
    ]);
    store.saveShow(store.showsToFetch().single, _details(70001), [
      _season(1, ['Static', 'Carrier Wave']),
    ]);

    final copies = MetadataStore(library).copiesOf(title, sourceIds: ['icc']);

    expect(
      [
        for (final copy in copies)
          (copy.season, copy.episode, copy.episodeName),
      ],
      [(1, 1, 'Static'), (1, 2, 'Carrier Wave'), (2, 1, 'Kept')],
    );
  });
}
