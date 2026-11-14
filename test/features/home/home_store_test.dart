import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/features/home/home_store.dart';
import 'package:dhara/features/metadata/metadata_store.dart';
import 'package:dhara/features/metadata/video_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

const _all = ['flix', 'icc'];

void main() {
  late LibraryDb library;
  late Database db;
  var urls = 0;

  setUp(() {
    library = LibraryDb.inMemory();
    db = library.db;
  });

  tearDown(() => library.close());

  HomeStore home([List<String> sources = _all]) =>
      HomeStore(library, sourceIds: sources);

  /// Puts a video into the index, reads its name, and returns its title.
  /// [modified] and [addedAt] are in days, to keep the tests readable.
  int add(
    String path,
    String name, {
    String source = 'icc',
    int? modified,
    int addedAt = 1000,
    String? url,
  }) {
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
      'INSERT INTO files (folder, name, url, modified, added_at) '
      'VALUES (?, ?, ?, ?, ?)',
      [
        db.lastInsertRowId,
        name,
        url ?? 'http://$source.test/${urls++}/$name',
        modified,
        addedAt,
      ],
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

  int film(String name, int year, {String source = 'icc', int? modified}) =>
      add(
        'Movies/English',
        '$name ($year) 1080p.mkv',
        source: source,
        modified: modified,
      );

  int episode(
    String show,
    int season,
    int number, {
    String source = 'icc',
    String quality = '720p',
    int? modified,
  }) => add(
    'Tv/$show/Season $season',
    '$show S${'$season'.padLeft(2, '0')}E${'$number'.padLeft(2, '0')} '
        '$quality.mkv',
    source: source,
    modified: modified,
  );

  /// What a match on TMDB would have noted on [title].
  void describe(
    int title, {
    int state = 1,
    int? year,
    double? rating,
    int? votes,
    String? poster,
    String? backdrop,
    String? genres,
    String? language,
    String? overview,
  }) => db.execute(
    'UPDATE titles SET match_state = ?1, tmdb_id = id + 1000, '
    'year = ifnull(?2, year), rating = ?3, votes = ?4, poster_path = ?5, '
    'backdrop_path = ?6, genres = ?7, language = ?8, overview = ?9 '
    'WHERE id = ?10',
    [
      state,
      year,
      rating,
      votes,
      poster,
      backdrop,
      genres,
      language,
      overview,
      title,
    ],
  );

  List<String> names(List<TitleCard> cards) => [
    for (final card in cards) card.name,
  ];

  /// Notes that the video at [url] was watched; [left] is where it can be
  /// resumed, if it can.
  void watched(
    String url, {
    required int at,
    int? left,
    bool finished = false,
    int length = 6000,
  }) {
    db.execute(
      'INSERT OR REPLACE INTO watch_history '
      '(url, watched_at, position_ms, duration_ms, finished) '
      'VALUES (?, ?, ?, ?, ?)',
      [url, at, finished ? length : left ?? 0, length, finished ? 1 : 0],
    );
    if (left != null) {
      db.execute(
        'INSERT OR REPLACE INTO playback '
        '(url, position_ms, duration_ms, updated_at) VALUES (?, ?, ?, ?)',
        [url, left, length, at],
      );
    }
  }

  group('newest', () {
    test('lists the films of the newest year first, then by votes', () {
      describe(film('Old Hit', 1999), votes: 9000);
      describe(film('Quiet One', 2024), votes: 12);
      describe(film('Loud One', 2024), votes: 800);
      describe(film('This Year', 2026), votes: 3);
      episode('Some Show', 1, 1);

      expect(names(home().newest(TitleKind.movie)), [
        'This Year',
        'Loud One',
        'Quiet One',
        'Old Hit',
      ]);
      expect(names(home().newest(TitleKind.series)), ['Some Show']);
    });

    test('a card says what the title is and what the sources hold', () {
      final id = film('Vivarium', 2019);
      add('Movies', 'Vivarium (2019) 2160p.mkv', source: 'flix');
      add('Movies', 'Vivarium (2019) Trailer.mkv', source: 'flix');
      describe(
        id,
        rating: 6.1,
        votes: 2500,
        poster: '/p.jpg',
        backdrop: '/b.jpg',
        genres: 'Science Fiction, Thriller',
        overview: 'A couple looks for a house.',
      );
      db.execute('UPDATE titles SET runtime = 98 WHERE id = ?', [id]);

      final card = home().newest(TitleKind.movie).single;

      expect(card.id, id);
      expect(card.kind, TitleKind.movie);
      expect(card.name, 'Vivarium');
      expect(card.year, 2019);
      expect(card.rating, 6.1);
      expect(card.posterPath, '/p.jpg');
      expect(card.backdropPath, '/b.jpg');
      expect(card.genres, ['Science Fiction', 'Thriller']);
      expect(card.runtime, 98);
      expect(card.isAnime, isFalse);
      expect(card.videos, 2, reason: 'the trailer is not a copy');
      expect(card.episodes, 0);
      expect(card.height, 2160);
      expect(card.overview, isNull, reason: 'only the banner reads it');
    });

    test('a show counts its episodes, however many copies of each', () {
      episode('The Bay', 1, 1);
      episode('The Bay', 1, 2);
      episode('The Bay', 1, 2, source: 'flix', quality: '1080p');
      episode('The Bay', 2, 1);

      final card = home().newest(TitleKind.series).single;

      expect(card.kind, TitleKind.series);
      expect(card.videos, 4);
      expect(card.episodes, 3);
      expect(card.height, 1080);
    });

    test('only lists what an enabled source holds, and counts only that', () {
      film('Here', 2020);
      film('There', 2021, source: 'flix');
      add('Movies', 'Here (2020) 2160p.mkv', source: 'flix');

      final card = home(['icc']).newest(TitleKind.movie).single;
      expect(card.name, 'Here');
      expect(card.videos, 1);
      expect(card.height, 1080);

      expect(names(home(['flix']).newest(TitleKind.movie)), ['There', 'Here']);
      expect(home([]).newest(TitleKind.movie), isEmpty);
      expect(home(['gone']).newest(TitleKind.movie), isEmpty);
    });

    test('leaves out what TMDB does not know and what was set aside', () {
      film('Looked Up', 2020);
      describe(film('Unsure', 2021), state: 2);
      describe(film('Not Found', 2022), state: 3);
      describe(film('By Hand', 2023), state: 4);
      describe(film('Left Alone', 2024), state: 5);
      final aside = film('Set Aside', 2025);
      db.execute('UPDATE titles SET set_aside = 1 WHERE id = ?', [aside]);

      expect(names(home().newest(TitleKind.movie)), [
        'Left Alone',
        'By Hand',
        'Unsure',
        'Looked Up',
      ]);
    });

    test('a title whose only video is a trailer is not listed', () {
      add('Movies', 'Coming Soon (2027) Trailer.mkv');
      film('Out Now', 2026);

      expect(names(home().newest(TitleKind.movie)), ['Out Now']);
    });

    test('stops when the row is full, past what is not available', () {
      for (var i = 0; i < 40; i++) {
        // Every third film is on a source that is switched off.
        film('Film $i', 1980 + i, source: i % 3 == 0 ? 'flix' : 'icc');
      }

      final row = home(['icc']).newest(TitleKind.movie, limit: 8);

      expect(names(row), [
        'Film 38',
        'Film 37',
        'Film 35',
        'Film 34',
        'Film 32',
        'Film 31',
        'Film 29',
        'Film 28',
      ]);
    });

    test('walks its index in order, without sorting', () {
      final plan = [
        for (final row in db.select(
          'EXPLAIN QUERY PLAN SELECT t.id FROM titles t '
          'INDEXED BY titles_newest WHERE t.kind = 0 '
          'AND t.match_state != 3 AND t.set_aside = 0 '
          'ORDER BY t.year DESC, t.votes DESC',
        ))
          '${row['detail']}',
      ];
      expect(plan, isNot(contains(contains('TEMP B-TREE'))));

      final rated = [
        for (final row in db.select(
          'EXPLAIN QUERY PLAN SELECT t.id FROM titles t '
          'INDEXED BY titles_rated WHERE t.rating IS NOT NULL '
          'AND t.votes >= 300 ORDER BY t.rating DESC, t.votes DESC',
        ))
          '${row['detail']}',
      ];
      expect(rated, isNot(contains(contains('TEMP B-TREE'))));
    });
  });

  group('topRated', () {
    test('lists the best rated films and shows that enough people voted '
        'on', () {
      describe(film('Good', 2010), rating: 7.9, votes: 4000);
      describe(film('Great', 2001), rating: 8.7, votes: 900);
      describe(film('One Fan', 2020), rating: 10, votes: 1);
      describe(episode('Fine Show', 1, 1), rating: 8.2, votes: 300);
      film('Unrated', 2015);

      expect(names(home().topRated()), ['Great', 'Fine Show', 'Good']);
      expect(names(home().topRated(limit: 1)), ['Great']);
      expect(names(home().topRated(minVotes: 1)).first, 'One Fan');
    });

    test('of two with the same rating, the one with more votes leads', () {
      describe(film('Fewer', 2010), rating: 8, votes: 400);
      describe(film('More', 2011), rating: 8, votes: 5000);

      expect(names(home().topRated()), ['More', 'Fewer']);
    });
  });

  group('anime', () {
    test('lists animation from Japan and what AniList knows', () {
      describe(
        episode('Mushishi', 1, 1),
        year: 2005,
        genres: 'Animation, Mystery',
        language: 'ja',
      );
      describe(
        film('Toy Story', 1995),
        genres: 'Animation, Family',
        language: 'en',
      );
      describe(film('Tokyo Story', 1953), genres: 'Drama', language: 'ja');
      final known = film('Your Name', 2016);
      db.execute('UPDATE titles SET anilist_id = 21519 WHERE id = ?', [known]);

      final row = home().anime();

      expect(names(row), ['Your Name', 'Mushishi']);
      expect(row.every((card) => card.isAnime), isTrue);
    });
  });

  group('recentlyAdded', () {
    test('lists titles by their newest video, each once', () {
      film('Last Month', 2020, modified: 500);
      episode('Running Show', 1, 1, modified: 100);
      film('Last Week', 2021, modified: 800);
      episode('Running Show', 1, 2, modified: 900);
      episode('Running Show', 1, 3, modified: 950);

      expect(names(home().recentlyAdded()), [
        'Running Show',
        'Last Week',
        'Last Month',
      ]);
    });

    test('a video without a date counts from when the app first saw it', () {
      film('Dated', 2020, modified: 500);
      add('Movies', 'Undated (2021) 720p.mkv', addedAt: 700);
      add('Movies', 'Seen Early (2022) 720p.mkv', addedAt: 300);

      expect(names(home().recentlyAdded()), ['Undated', 'Dated', 'Seen Early']);
    });

    test('a date after the app first saw the video is not believed', () {
      film('Honest', 2020, modified: 900);
      film('From The Future', 2021, modified: 99999);

      // It counts as seen on day 1000, when the app found it.
      expect(names(home().recentlyAdded()), ['From The Future', 'Honest']);
      film('Newer', 2022, modified: 999);
      expect(names(home().recentlyAdded()).take(2), [
        'From The Future',
        'Newer',
      ]);
    });

    test('a new trailer does not bring its film up', () {
      film('The Film', 2020, modified: 100);
      add('Movies', 'The Film (2020) Trailer.mkv', modified: 900);
      film('Another', 2021, modified: 500);

      expect(names(home().recentlyAdded()), ['Another', 'The Film']);
    });

    test('only goes by the videos of enabled sources', () {
      film('Both', 2020, modified: 100);
      add('Movies', 'Both (2020) 720p.mkv', source: 'flix', modified: 900);
      film('Only Here', 2021, modified: 500);

      expect(names(home(['icc']).recentlyAdded()), ['Only Here', 'Both']);
      expect(names(home().recentlyAdded()), ['Both', 'Only Here']);
      expect(home([]).recentlyAdded(), isEmpty);
    });

    test('fills the row past what Home does not show', () {
      for (var i = 0; i < 30; i++) {
        final id = film('Film $i', 2000, modified: i);
        if (i.isOdd) describe(id, state: 3);
      }

      final row = home().recentlyAdded(limit: 6);

      expect(names(row), [
        'Film 28',
        'Film 26',
        'Film 24',
        'Film 22',
        'Film 20',
        'Film 18',
      ]);
    });

    test('finds the newest videos through the index', () {
      final plan = [
        for (final row in db.select(
          'EXPLAIN QUERY PLAN SELECT m.title FROM files f '
          'INDEXED BY files_recent '
          'CROSS JOIN file_meta m ON m.file = f.id '
          'CROSS JOIN folders d ON d.id = f.folder '
          'WHERE m.title IS NOT NULL AND m.extra IS NULL '
          'AND d.source IN (1, 2) '
          'ORDER BY min(ifnull(f.modified, f.added_at), f.added_at) DESC '
          'LIMIT 100',
        ))
          '${row['detail']}',
      ];
      expect(plan.first, contains('files_recent'));
      expect(plan, isNot(contains(contains('TEMP B-TREE'))));
    });
  });

  group('featured', () {
    void addFeaturable(int count) {
      for (var i = 0; i < count; i++) {
        describe(
          i.isEven ? film('Film $i', 2020 + i % 5) : episode('Show $i', 1, 1),
          rating: 7.5,
          votes: 500 + i,
          backdrop: '/b$i.jpg',
          overview: 'About number $i.',
        );
      }
    }

    test('picks well rated titles that have a backdrop', () {
      addFeaturable(6);
      describe(film('No Backdrop', 2026), rating: 9, votes: 9000);
      describe(
        film('Poorly Rated', 2026),
        rating: 4.2,
        votes: 9000,
        backdrop: '/poor.jpg',
      );
      describe(
        film('Hardly Rated', 2026),
        rating: 9,
        votes: 4,
        backdrop: '/few.jpg',
      );

      final picked = home().featured(day: 20000);

      expect(picked, hasLength(5));
      expect(
        names(
          picked,
        ).toSet().intersection({'No Backdrop', 'Poorly Rated', 'Hardly Rated'}),
        isEmpty,
      );
      expect(picked.first.overview, startsWith('About number'));
      expect(picked.first.backdropPath, isNotNull);
    });

    test('shows the same titles all day, others on other days', () {
      addFeaturable(24);

      final today = names(home().featured(day: 20000));

      expect(names(home().featured(day: 20000)), today);
      final otherDays = {
        for (var day = 20001; day < 20008; day++)
          names(home().featured(day: day)).join(','),
      };
      expect(otherDays.length, greaterThan(3));
      expect(otherDays, isNot(contains(today.join(','))));
    });

    test('settles for anything with a backdrop in a thin library', () {
      describe(film('Well Rated', 2020), rating: 8, votes: 900, backdrop: '/a');
      describe(film('Unrated', 2021), backdrop: '/b');
      describe(episode('Show', 1, 1), rating: 5, votes: 3, backdrop: '/c');
      film('Nothing Known', 2022);

      expect(names(home().featured(day: 1)).toSet(), {
        'Well Rated',
        'Unrated',
        'Show',
      });
      expect(home([]).featured(day: 1), isEmpty);
    });
  });

  group('continueWatching', () {
    test('lists what was left unfinished, the latest first', () {
      final vivarium = add(
        'Movies',
        'Vivarium (2019) 1080p.mkv',
        url: 'http://icc.test/vivarium.mkv',
      );
      add('Movies', 'Tenet (2020) 1080p.mkv', url: 'http://icc.test/tenet.mkv');
      watched('http://icc.test/vivarium.mkv', at: 100, left: 1500);
      watched('http://icc.test/tenet.mkv', at: 200, left: 3000);

      final [first, second] = home().continueWatching();

      expect(first.title?.name, 'Tenet');
      expect(first.url, 'http://icc.test/tenet.mkv');
      expect(first.fileName, 'Tenet (2020) 1080p.mkv');
      expect(first.position, const Duration(seconds: 3));
      expect(first.duration, const Duration(seconds: 6));
      expect(first.progress, .5);
      expect(first.watchedAt, DateTime.fromMillisecondsSinceEpoch(200));
      expect(second.title?.id, vivarium);
      expect(second.title?.videos, 1);
    });

    test('a show is in it once, with the episode watched last', () {
      const base = 'http://icc.test/bay';
      for (final number in [1, 2, 3]) {
        add(
          'Tv/The Bay/Season 1',
          'The Bay S01E0$number 720p.mkv',
          url: '$base$number.mkv',
        );
      }
      db.execute(
        'INSERT INTO episodes (title, season, episode, name) '
        "SELECT id, 1, 2, 'Second One' FROM titles",
      );
      watched('${base}1.mkv', at: 100, left: 1000);
      watched('${base}2.mkv', at: 300, left: 2000);

      final item = home().continueWatching().single;

      expect(item.title?.name, 'The Bay');
      expect((item.season, item.episode), (1, 2));
      expect(item.episodeName, 'Second One');
      expect(item.position, const Duration(seconds: 2));
    });

    test('a title whose latest video was watched to the end is not in '
        'it', () {
      const base = 'http://icc.test/bay';
      for (final number in [1, 2]) {
        add(
          'Tv/The Bay/Season 1',
          'The Bay S01E0$number 720p.mkv',
          url: '$base$number.mkv',
        );
      }
      // Episode 1 was left half way, then episode 2 was watched whole.
      watched('${base}1.mkv', at: 100, left: 1000);
      watched('${base}2.mkv', at: 300, finished: true);
      add('Movies', 'Tenet (2020).mkv', url: 'http://icc.test/tenet.mkv');
      watched('http://icc.test/tenet.mkv', at: 200, finished: true);

      expect(home().continueWatching(), isEmpty);
    });

    test('a video that cannot be resumed any more is not in it', () {
      add('Movies', 'Tenet (2020).mkv', url: 'http://icc.test/tenet.mkv');
      watched('http://icc.test/tenet.mkv', at: 200);

      expect(home().continueWatching(), isEmpty);
    });

    test('keeps a video played from a pasted address', () {
      watched('http://elsewhere.test/clip.mkv', at: 100, left: 1200);
      watched('http://elsewhere.test/other.mkv', at: 50, left: 600);

      final [first, second] = home().continueWatching();

      expect(first.url, 'http://elsewhere.test/clip.mkv');
      expect(first.title, isNull);
      expect(first.fileName, isNull);
      expect(second.url, 'http://elsewhere.test/other.mkv');
    });

    test('leaves out what is on a source that is switched off', () {
      add(
        'Movies',
        'Tenet (2020).mkv',
        source: 'flix',
        url: 'http://flix.test/tenet.mkv',
      );
      watched('http://flix.test/tenet.mkv', at: 200, left: 3000);

      expect(home(['icc']).continueWatching(), isEmpty);
      expect(home().continueWatching(), hasLength(1));
    });

    test('also lists a title TMDB does not know', () {
      final id = add(
        'Movies',
        'Home Video (2020).mkv',
        url: 'http://icc.test/home.mkv',
      );
      describe(id, state: 3);
      watched('http://icc.test/home.mkv', at: 200, left: 3000);

      expect(home().continueWatching().single.title?.name, 'Home Video');
    });

    test('is no longer than asked', () {
      for (var i = 0; i < 9; i++) {
        watched('http://elsewhere.test/$i.mkv', at: i, left: 1000);
      }

      final items = home().continueWatching(limit: 4);

      expect(
        [for (final item in items) item.url.split('/').last],
        ['8.mkv', '7.mkv', '6.mkv', '5.mkv'],
      );
    });
  });

  group('content', () {
    test('is all of Home at once', () {
      describe(
        film('Vivarium', 2019),
        rating: 8.1,
        votes: 2500,
        backdrop: '/b.jpg',
      );
      describe(
        episode('Mushishi', 1, 1),
        genres: 'Animation',
        language: 'ja',
        rating: 8.6,
        votes: 700,
      );
      watched('http://elsewhere.test/clip.mkv', at: 100, left: 1200);

      final content = home().content(today: DateTime(2026, 11, 15));

      expect(names(content.featured), ['Vivarium']);
      expect(content.continueWatching, hasLength(1));
      expect(names(content.recentlyAdded).toSet(), {'Vivarium', 'Mushishi'});
      expect(names(content.movies), ['Vivarium']);
      expect(names(content.series), ['Mushishi']);
      expect(names(content.anime), ['Mushishi']);
      expect(names(content.topRated), ['Mushishi', 'Vivarium']);
      expect(content.hasNoTitles, isFalse);
    });

    test('is empty for an empty library, or with every source off', () {
      expect(home().content(today: DateTime(2026)).hasNoTitles, isTrue);

      film('Vivarium', 2019);
      final content = home([]).content(today: DateTime(2026));
      expect(content.hasNoTitles, isTrue);
      expect(content.featured, isEmpty);
      expect(content.topRated, isEmpty);
    });

    test('the banner changes with the calendar day, not within it', () {
      for (var i = 0; i < 24; i++) {
        describe(
          film('Film $i', 2020),
          rating: 7.5,
          votes: 500,
          backdrop: '/b$i.jpg',
        );
      }

      final morning = home().content(today: DateTime(2026, 11, 15, 6));
      final night = home().content(today: DateTime(2026, 11, 15, 23, 59));
      final nextDay = home().content(today: DateTime(2026, 11, 16, 0, 1));

      expect(names(night.featured), names(morning.featured));
      expect(names(nextDay.featured), isNot(names(morning.featured)));
    });
  });

  test('reads Home quickly from a large library', () {
    // 100,000 videos: 15,000 films with two copies each, and 5,000 shows
    // with 14 episodes each, on three sources.
    const sources = ['flix', 'icc', 'sam'];
    library.transaction(() {
      for (final (index, source) in sources.indexed) {
        db.execute('INSERT INTO sources (id, source_id) VALUES (?, ?)', [
          index + 1,
          source,
        ]);
        db.execute(
          'INSERT INTO folders (id, source, url, path, depth) '
          'VALUES (?, ?, ?, ?, 0)',
          [index + 1, index + 1, 'http://$source.test/', 'All'],
        );
      }
      final addTitle = db.prepare(
        'INSERT INTO titles (id, kind, name, year, tmdb_id, match_state, '
        'rating, votes, genres, language, poster_path, backdrop_path, '
        'added_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)',
      );
      final addFile = db.prepare(
        'INSERT INTO files (id, folder, name, url, modified, added_at) '
        'VALUES (?, ?, ?, ?, ?, ?)',
      );
      final addMeta = db.prepare(
        'INSERT INTO file_meta (file, parser, kind, title, season, episode, '
        'height) VALUES (?, 1, ?, ?, ?, ?, ?)',
      );
      var file = 0;
      for (var title = 1; title <= 20000; title++) {
        final isShow = title > 15000;
        // One in thirty is not known to TMDB.
        final known = title % 30 != 0;
        addTitle.execute([
          title,
          if (isShow) 1 else 0,
          'Title $title',
          1960 + title % 67,
          title,
          if (known) 1 else 3,
          if (known) 4 + (title % 55) / 10 else null,
          if (known) title * 7 % 5000 else null,
          title % 41 == 0 ? 'Animation, Drama' : 'Drama',
          title % 9 == 0 ? 'ja' : 'en',
          '/p$title.jpg',
          if (title % 3 == 0) null else '/b$title.jpg',
        ]);
        for (var copy = 0; copy < (isShow ? 14 : 2); copy++) {
          file++;
          addFile.execute([
            file,
            1 + file % 3,
            'Title $title $copy.mkv',
            'http://files.test/$file.mkv',
            // Every fifth video has no date.
            if (file % 5 == 0) null else file * 13 % 90000,
            100000,
          ]);
          addMeta.execute([
            file,
            if (isShow) 1 else 0,
            title,
            if (isShow) 1 else null,
            if (isShow) copy + 1 else null,
            const [480, 720, 1080, 2160][file % 4],
          ]);
        }
      }
      for (final statement in [addTitle, addFile, addMeta]) {
        statement.close();
      }
      for (var i = 1; i <= 300; i++) {
        db.execute(
          'INSERT INTO watch_history '
          '(url, watched_at, position_ms, duration_ms, finished) '
          'VALUES (?, ?, 1000, 5000, 0)',
          ['http://files.test/${i * 31}.mkv', i],
        );
        db.execute(
          'INSERT INTO playback (url, position_ms, duration_ms, updated_at) '
          'VALUES (?, 1000, 5000, ?)',
          ['http://files.test/${i * 31}.mkv', i],
        );
      }
    });
    expect(db.select('SELECT count(*) FROM files').single.values, [100000]);

    Duration time(void Function() read) {
      // The best of three: the first run also fills SQLite's page cache.
      var best = const Duration(days: 1);
      for (var i = 0; i < 3; i++) {
        final watch = Stopwatch()..start();
        read();
        watch.stop();
        if (watch.elapsed < best) best = watch.elapsed;
      }
      return best;
    }

    late HomeContent content;
    final all = time(
      () => content = home(sources).content(today: DateTime(2026, 11, 15)),
    );
    // With two of three sources off, every row has to look further.
    final one = time(
      () => home(['sam']).content(today: DateTime(2026, 11, 15)),
    );
    // ignore: avoid_print
    print(
      'Home from 100,000 videos: ${all.inMicroseconds / 1000} ms; '
      'with one source of three: ${one.inMicroseconds / 1000} ms',
    );

    expect(content.featured, hasLength(5));
    expect(content.continueWatching, hasLength(20));
    for (final row in [
      content.recentlyAdded,
      content.movies,
      content.series,
      content.anime,
      content.topRated,
    ]) {
      expect(row, hasLength(30));
    }
    expect(content.topRated.first.rating, 9.4);
    // The aim is 50 ms; the limit only catches a blow-up on a slow machine.
    expect(all, lessThan(const Duration(milliseconds: 400)));
    expect(one, lessThan(const Duration(milliseconds: 800)));
  });
}
