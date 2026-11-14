import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/features/details/details_store.dart';
import 'package:dhara/features/details/next_to_play.dart';
import 'package:dhara/features/home/home_store.dart';
import 'package:dhara/features/metadata/match_store.dart';
import 'package:dhara/features/metadata/metadata_store.dart';
import 'package:dhara/features/metadata/review_store.dart';
import 'package:dhara/features/metadata/video_identity.dart';
import 'package:dhara/features/sources/source.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late LibraryDb library;
  late Database db;
  var urls = 0;

  setUp(() {
    library = LibraryDb.inMemory();
    db = library.db;
  });

  tearDown(() => library.close());

  DetailsStore store([List<String> sources = const ['flix', 'icc']]) =>
      DetailsStore(library, sourceIds: sources);

  /// Puts a video into the index, reads its name, and returns its title.
  int add(String path, String name, {String source = 'icc', String? url}) {
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
      [db.lastInsertRowId, name, url ?? 'http://$source.test/${urls++}/$name'],
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

  int film(String name, int year, {String? url}) =>
      add('Movies', '$name ($year) 1080p.mkv', url: url);

  int episode(String show, int season, int number, {String? url}) => add(
    'Tv/$show/Season $season',
    '$show S0${season}E0$number 720p.mkv',
    url: url,
  );

  void describe(
    int title, {
    String? genres,
    int? votes,
    String? language,
    int state = 1,
  }) => db.execute(
    'UPDATE titles SET match_state = ?, tmdb_id = id + 1000, genres = ?, '
    'votes = ?, language = ?, original_name = name || \' (original)\', '
    "overview = 'About ' || name, rating = 7.5 WHERE id = ?",
    [state, genres, votes, language, title],
  );

  void watched(
    String url, {
    required int at,
    int? left,
    bool finished = false,
  }) {
    db.execute(
      'INSERT OR REPLACE INTO watch_history '
      '(url, watched_at, position_ms, duration_ms, finished) '
      'VALUES (?, ?, ?, 6000, ?)',
      [url, at, finished ? 6000 : left ?? 0, finished ? 1 : 0],
    );
    if (left != null) {
      db.execute(
        'INSERT OR REPLACE INTO playback '
        '(url, position_ms, duration_ms, updated_at) VALUES (?, ?, 6000, ?)',
        [url, left, at],
      );
    }
  }

  List<String> names(List<TitleCard> cards) => [
    for (final card in cards) card.name,
  ];

  group('page', () {
    test('holds what is known of a title, and its copies', () {
      final id = film('Vivarium', 2019);
      add('Movies', 'Vivarium (2019) 2160p.mkv', source: 'flix');
      describe(
        id,
        genres: 'Science Fiction, Thriller',
        votes: 2500,
        language: 'en',
      );

      final page = store().page(id)!;

      expect(page.title.name, 'Vivarium');
      expect(page.title.overview, 'About Vivarium');
      expect(page.title.videos, 2);
      expect(page.title.height, 2160);
      expect(page.title.genres, ['Science Fiction', 'Thriller']);
      expect(page.originalName, 'Vivarium (original)');
      expect(page.language, 'en');
      expect(page.votes, 2500);
      expect(page.matchState, MatchState.matched);
      expect(page.isMatched, isTrue);
      expect([for (final copy in page.copies) copy.height], [2160, 1080]);
      expect(page.episodes, isEmpty);
      expect(page.watched, isEmpty);
    });

    test('is there for a title TMDB does not know, and for one whose '
        'servers are switched off', () {
      final unknown = film('Home Video', 2020);
      describe(unknown, state: MatchState.notFound);
      final away = add('Movies', 'Elsewhere (2021).mkv', source: 'flix');

      expect(store().page(unknown)!.isMatched, isFalse);

      final page = store(['icc']).page(away)!;
      expect(page.title.name, 'Elsewhere');
      expect(page.title.videos, 0);
      expect(page.copies, isEmpty);
      expect(store([]).page(away)!.copies, isEmpty);
    });

    test('is not there for a title that is gone or was set aside', () {
      final id = film('Vivarium', 2019);
      expect(store().page(id + 99), isNull);

      db.execute('UPDATE titles SET set_aside = 1 WHERE id = ?', [id]);
      expect(store().page(id), isNull);
    });

    test('knows how far each copy was watched', () {
      final id = film('Vivarium', 2019, url: 'http://icc.test/v1.mkv');
      film('Vivarium', 2019, url: 'http://icc.test/v2.mkv');
      watched('http://icc.test/v1.mkv', at: 500, left: 1500);
      watched('http://icc.test/v2.mkv', at: 100, finished: true);
      watched('http://icc.test/other.mkv', at: 900, left: 100);

      final seen = store().page(id)!.watched;

      expect(seen.keys, {'http://icc.test/v1.mkv', 'http://icc.test/v2.mkv'});
      expect(seen['http://icc.test/v1.mkv']!.progress, .25);
      expect(seen['http://icc.test/v1.mkv']!.finished, isFalse);
      expect(seen['http://icc.test/v2.mkv']!.progress, 1);
      expect(
        seen['http://icc.test/v1.mkv']!.at,
        DateTime.fromMillisecondsSinceEpoch(500),
      );
    });

    test('of a show carries what TMDB says of its episodes', () {
      final id = episode('The Bay', 1, 1);
      episode('The Bay', 1, 2);
      db
        ..execute(
          "INSERT INTO seasons (title, season, name) VALUES (?, 1, 'One')",
          [id],
        )
        ..execute(
          'INSERT INTO episodes (title, season, episode, name, overview, '
          "still_path, runtime) VALUES (?, 1, 2, 'Second', 'More.', "
          "'/s.jpg', 44)",
          [id],
        );

      final page = store().page(id)!;

      expect(page.title.kind, TitleKind.series);
      expect(page.title.episodes, 2);
      expect(page.seasonNames, {1: 'One'});
      final info = page.episodes.single;
      expect((info.season, info.episode), (1, 2));
      expect(info.name, 'Second');
      expect(info.overview, 'More.');
      expect(info.stillPath, '/s.jpg');
      expect(info.runtime, 44);
      expect(page.copies.last.episodeName, 'Second');
    });
  });

  group('more like this', () {
    test('are titles of the same kind that share its first genre, the '
        'most voted first', () {
      final id = film('Vivarium', 2019);
      describe(id, genres: 'Thriller, Mystery', votes: 100);
      describe(film('Loud Thriller', 2001), genres: 'Thriller', votes: 9000);
      describe(
        film('Quiet Thriller', 2020),
        genres: 'Drama, Thriller',
        votes: 12,
      );
      describe(film('A Comedy', 2019), genres: 'Comedy', votes: 5000);
      describe(episode('Thriller Show', 1, 1), genres: 'Thriller', votes: 800);
      describe(film('Not Found', 2019), genres: 'Thriller', state: 3);

      expect(names(store().page(id)!.similar), [
        'Loud Thriller',
        'Quiet Thriller',
      ]);
      expect(store().page(id, similarTitles: 1)!.similar, hasLength(1));
    });

    test('without genres, are titles of about the same year and language', () {
      final id = film('Vivarium', 2019);
      describe(id, language: 'en');
      describe(film('Same Time', 2020), language: 'en', votes: 10);
      describe(film('Same Time Elsewhere', 2020), language: 'ko', votes: 99);
      describe(film('Long Ago', 1999), language: 'en', votes: 9000);

      expect(names(store().page(id)!.similar), ['Same Time']);
    });

    test('only what an enabled server holds', () {
      final id = film('Vivarium', 2019);
      describe(id, genres: 'Thriller');
      final away = add('Movies', 'Elsewhere (2021).mkv', source: 'flix');
      describe(away, genres: 'Thriller', votes: 500);

      expect(store(['icc']).page(id)!.similar, isEmpty);
      expect(names(store().page(id)!.similar), ['Elsewhere']);
    });
  });

  group('nextToPlay', () {
    final sources = SourceStore(
      starter: [
        for (final id in ['icc', 'flix'])
          Source(
            id: id,
            name: id,
            type: SourceType.h5ai,
            category: SourceCategory.mixed,
            baseUrls: [Uri.parse('http://$id.test/')],
          ),
      ],
    );

    PlayChoice? choice(int id) => nextToPlay(store().page(id)!, sources);

    test('a film nobody watched plays its best copy', () {
      final id = film('Vivarium', 2019);
      add('Movies', 'Vivarium (2019) 2160p.mkv', source: 'flix');

      final next = choice(id)!;

      expect(next.copy.height, 2160);
      expect(next.resume, isFalse);
      expect(next.label, 'Play');
    });

    test('a film left unfinished resumes the copy that was watched', () {
      final id = film('Vivarium', 2019, url: 'http://icc.test/v1.mkv');
      add('Movies', 'Vivarium (2019) 2160p.mkv', source: 'flix');
      watched('http://icc.test/v1.mkv', at: 500, left: 1500);

      final next = choice(id)!;

      expect('${next.copy.url}', 'http://icc.test/v1.mkv');
      expect(next.label, 'Resume');
    });

    test('a show starts with its first episode', () {
      episode('The Bay', 1, 2);
      final id = episode('The Bay', 1, 1);

      final next = choice(id)!;

      expect((next.copy.season, next.copy.episode), (1, 1));
      expect(next.label, 'Play S1 · E1');
    });

    test('a show goes on where it was left, and after an episode that '
        'ended, with the next', () {
      final id = episode('The Bay', 1, 1, url: 'http://icc.test/b1.mkv');
      episode('The Bay', 1, 2, url: 'http://icc.test/b2.mkv');
      episode('The Bay', 2, 1, url: 'http://icc.test/b3.mkv');
      watched('http://icc.test/b1.mkv', at: 100, left: 2000);
      expect(choice(id)!.label, 'Resume S1 · E1');

      watched('http://icc.test/b1.mkv', at: 200, finished: true);
      expect(choice(id)!.label, 'Play S1 · E2');

      watched('http://icc.test/b2.mkv', at: 300, finished: true);
      expect(choice(id)!.label, 'Play S2 · E1');

      // Nothing after the last one: from the beginning again.
      watched('http://icc.test/b3.mkv', at: 400, finished: true);
      expect(choice(id)!.label, 'Play S1 · E1');
    });

    test('is nothing when no copy can be played', () {
      final id = film('Vivarium', 2019, url: 'ftp://icc.test/v1.mkv');

      expect(choice(id), isNull);
    });
  });

  group('one title to review', () {
    test('is read whatever its state', () {
      final id = film('Vivarium', 2019);
      describe(id);
      final review = ReviewStore(library);

      expect(review.items(sourceIds: ['icc']), isEmpty);
      final item = review.items(sourceIds: ['icc'], only: id).single;
      expect(item.id, id);
      expect(item.spelledName, 'Vivarium');
      expect(item.spelledYear, 2019);
      expect(review.items(sourceIds: ['flix'], only: id), isEmpty);
    });
  });
}
